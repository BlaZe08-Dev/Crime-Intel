import 'package:crime_intel/audit/audit_logger.dart';
import 'package:crime_intel/data/db/database_helper.dart';
import 'package:crime_intel/data/repositories/crime_repository.dart';
import 'package:crime_intel/data/repositories/graph_repository.dart';
import 'package:crime_intel/graph/entity_extractor.dart';
import 'package:crime_intel/graph/graph_analytics.dart';
import 'package:crime_intel/graph/graph_service.dart';
import 'package:crime_intel/graph/models/graph_models.dart';
import 'package:crime_intel/ingest/ingestion_service.dart';
import 'package:crime_intel/models/criminal.dart';
import 'package:crime_intel/models/structured_records.dart';
import 'package:crime_intel/models/text_record.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(DatabaseHelper.initFfi);

  group('EntityExtractor', () {
    final extractor = EntityExtractor();

    Criminal criminal(String id, String name, List<String> aliases,
            {String loc = 'Pune'}) =>
        Criminal(
          id: id,
          name: name,
          aliases: aliases,
          dob: '1980-01-01',
          gender: 'M',
          knownFor: 'test',
          status: CriminalStatus.AT_LARGE,
          lastKnownLoc: loc,
          riskLevel: RiskLevel.MED,
          createdAt: 0,
          updatedAt: 0,
        );

    TextRecord record(String id, String body, {String? criminalId}) =>
        TextRecord(
          id: id,
          criminalId: criminalId,
          kind: TextRecordKind.INTEL,
          title: 'Test record',
          body: body,
          createdAt: 0,
        );

    test('finds people by name and by alias', () {
      final result = extractor.extract(
        criminals: [criminal('C-001', 'Devraj Malhotra', ['DM', 'Seth'])],
        textRecords: [record('R-1', 'Operative known as Seth was observed.')],
      );

      final people = result
          .mentionsIn('R-1')
          .where((m) => m.type == EntityType.PERSON)
          .toList();
      expect(people, hasLength(1));
      expect(people.single.resolvedCriminalId, 'C-001');
    });

    test('does not match an alias inside a longer word', () {
      // "DM" inside "admin" and "Anna" inside "Annapurna" are the exact
      // false positives a substring match would invent.
      final result = extractor.extract(
        criminals: [
          criminal('C-001', 'Devraj Malhotra', ['DM']),
          criminal('C-003', 'Ravi Deshmukh', ['Anna']),
        ],
        textRecords: [
          record('R-1', 'The admin office near Annapurna Road was searched.'),
        ],
      );

      final people = result
          .mentionsIn('R-1')
          .where((m) => m.type == EntityType.PERSON);
      expect(people, isEmpty);
    });

    test('extracts phones, vehicles and organisations from text', () {
      final result = extractor.extract(
        criminals: [criminal('C-002', 'Farhan Qureshi', ['FQ'], loc: 'Nagpur')],
        textRecords: [
          record(
            'R-1',
            'Farhan Qureshi used +91-98200-11223 and drove MH-12-XX-4901 '
            'on behalf of Zenith Impex in Nagpur.',
          ),
        ],
      );

      final types = result.mentionsIn('R-1').map((m) => m.type).toSet();
      expect(types, contains(EntityType.PHONE));
      expect(types, contains(EntityType.VEHICLE));
      expect(types, contains(EntityType.ORG));
      expect(types, contains(EntityType.LOCATION));

      // One person named, so the phone is attributed to them.
      expect(result.phoneOwners['+91-98200-11223'], 'C-002');
    });

    test('declines to attribute a phone when several people are named', () {
      final result = extractor.extract(
        criminals: [
          criminal('C-001', 'Devraj Malhotra', ['Seth']),
          criminal('C-004', 'Sunita Rao', ['Madam']),
        ],
        textRecords: [
          record('R-1', 'Devraj Malhotra and Sunita Rao share +91-90000-11111.'),
        ],
      );

      expect(result.phoneOwners, isEmpty);
    });
  });

  group('GraphAnalytics over the seeded dataset', () {
    late Database db;
    late NetworkSnapshot snapshot;

    setUp(() async {
      db = await DatabaseHelper.openInMemory();
      final audit = AuditLogger(db);
      final records = CrimeRepository(db, audit);
      await IngestionService(db: db, audit: audit).seedIfEmpty();

      snapshot = await GraphService(
        records: records,
        graph: GraphRepository(db),
      ).rebuild();
    });

    tearDown(() async => db.close());

    test('derives a non-trivial graph from the records', () {
      expect(snapshot.entities, isNotEmpty);
      expect(snapshot.edges, isNotEmpty);
      // Every edge must cite the rows that produced it.
      for (final edge in snapshot.edges) {
        expect(edge.evidenceIds, isNotEmpty,
            reason: 'edge ${edge.id} has no evidence');
      }
    });

    test('computes C-001 as the network hub', () {
      // Not asserted by hardcoding: the ranking comes from PageRank over
      // edges derived from CDR, financial and co-mention records. C-001 wins
      // because the data makes him win.
      expect(snapshot.hubCriminalId, 'C-001');
    });

    test('the hub ranks above every other person on PageRank', () {
      final ranked = snapshot.analysis.rankedKeyIndividuals;
      expect(ranked.first, 'E-PERSON-C-001');

      final hubScore =
          snapshot.analysis.centrality['E-PERSON-C-001']!.pageRank;
      for (final other in ranked.skip(1)) {
        expect(snapshot.analysis.centrality[other]!.pageRank,
            lessThanOrEqualTo(hubScore));
      }
    });

    test('flags the C-004 to C-001 transaction burst', () {
      final bursts = snapshot.analysis.anomalies
          .where((a) => a.kind == 'TRANSACTION_BURST')
          .toList();

      expect(bursts, isNotEmpty,
          reason: 'the planted burst should be detected');

      final burst = bursts.first;
      expect(burst.subjectCriminalId, 'C-004');
      expect(burst.severity, AnomalySeverity.high);
      // The three spike transactions, found statistically.
      expect(burst.evidenceIds, containsAll(['TXN-003', 'TXN-004']));
    });

    test('does not flag the small regular deposits as transaction anomalies',
        () {
      // Scoped to transaction rules on purpose. The connectivity-outlier flag
      // legitimately cites every link touching a well-connected subject, and
      // those citations include these transactions - that is evidence for
      // "this person is unusually connected", not a claim that any individual
      // transfer was abnormal.
      final flaggedByAmount = snapshot.analysis.anomalies
          .where((a) => a.kind.startsWith('TRANSACTION_'))
          .expand((a) => a.evidenceIds)
          .toSet();

      // C-005's steady 15k-20k deposits are normal for that pair.
      expect(flaggedByAmount, isNot(contains('TXN-006')));
      expect(flaggedByAmount, isNot(contains('TXN-007')));
      expect(flaggedByAmount, isNot(contains('TXN-008')));

      // ...while the C-004 spikes still are.
      expect(flaggedByAmount, contains('TXN-004'));
    });

    test('assigns every node to a community', () {
      for (final entity in snapshot.entities) {
        expect(snapshot.analysis.communities.containsKey(entity.id), isTrue);
      }
    });
  });

  group('centrality responds to the data, not to an id', () {
    test('adding a better-connected subject moves the hub', () {
      // The old implementation asked `criminal.id == 'C-001'`. This is the
      // case that check could never get right.
      final analytics = GraphAnalytics();

      final entities = [
        for (final id in ['A', 'B', 'C', 'D', 'E'])
          Entity(
            id: 'E-PERSON-$id',
            type: EntityType.PERSON,
            value: 'Person $id',
            firstSeenIn: id,
          ),
      ];

      // Everyone points at E; A is a bystander.
      final edges = [
        for (final src in ['A', 'B', 'C', 'D'])
          Edge(
            id: 'EDGE-$src',
            srcEntityId: 'E-PERSON-$src',
            dstEntityId: 'E-PERSON-E',
            relation: RelationType.CALLED,
            weight: 3,
            evidenceIds: ['R-$src'],
          ),
      ];

      final analysis = analytics.analyse(
        entities: entities,
        edges: edges,
        financial: const <FinancialTxn>[],
        criminalNames: const {},
      );

      expect(analysis.hubEntityId, 'E-PERSON-E');
    });
  });
}
