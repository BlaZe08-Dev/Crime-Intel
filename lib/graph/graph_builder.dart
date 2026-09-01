import '../models/criminal.dart';
import '../models/structured_records.dart';
import '../models/text_record.dart';
import 'entity_extractor.dart';
import 'models/graph_models.dart';

/// Derives the relationship graph from the underlying records.
///
/// Nothing here is hand-authored. Every edge is computed from a CDR row, a
/// financial transaction, or a co-mention in FIR/intel text, and carries the
/// ids of the records that justify it in [Edge.evidenceIds] — so any link in
/// the UI can be traced back to the rows that produced it.
class GraphBuilder {
  /// Words that turn a shared mention into an actual co-location claim rather
  /// than two people merely appearing in the same document.
  static final RegExp _coLocationCue = RegExp(
    r'co-located|colocated|observed .* and |seen together|same sector|'
    r'identical geographic|triangulat|both present|accompanied by',
    caseSensitive: false,
  );

  /// Builds nodes and edges.
  GraphBuildResult build({
    required List<Criminal> criminals,
    required List<TextRecord> textRecords,
    required List<CdrRecord> cdr,
    required List<FinancialTxn> financial,
    required ExtractionResult extraction,
  }) {
    final entitiesById = {for (final e in extraction.entities) e.id: e};
    final accumulator = _EdgeAccumulator();

    String personNode(String criminalId) => 'E-PERSON-$criminalId';

    // --- Phone ownership -------------------------------------------------
    // Two sources, text first: an explicit subscriber attribution in an intel
    // note is stronger evidence than inferring from who placed a call.
    final phoneOwners = <String, String>{...extraction.phoneOwners};
    for (final call in cdr) {
      phoneOwners.putIfAbsent(call.callerId, () => call.criminalId);
    }

    // --- CDR -> CALLED ---------------------------------------------------
    for (final call in cdr) {
      final srcCriminal = phoneOwners[call.callerId] ?? call.criminalId;
      final dstCriminal = phoneOwners[call.calleeId];

      if (dstCriminal != null && dstCriminal != srcCriminal) {
        accumulator.add(
          src: personNode(srcCriminal),
          dst: personNode(dstCriminal),
          relation: RelationType.CALLED,
          evidenceId: call.id,
        );
      } else if (dstCriminal == null) {
        // Callee not attributable to anyone we know. Keep the link to the
        // handset rather than dropping it - an unattributed number that the
        // network keeps calling is itself an investigative lead.
        final phoneNode = 'E-PHONE-${EntityExtractor.slug(call.calleeId)}';
        entitiesById.putIfAbsent(
          phoneNode,
          () => Entity(
            id: phoneNode,
            type: EntityType.PHONE,
            value: call.calleeId,
            firstSeenIn: call.id,
          ),
        );
        accumulator.add(
          src: personNode(srcCriminal),
          dst: phoneNode,
          relation: RelationType.CALLED,
          evidenceId: call.id,
        );
      }
    }

    // --- Financial -> PAID -----------------------------------------------
    final namePatterns = <(RegExp, String)>[
      for (final c in criminals) (EntityExtractor.wordPattern(c.name), c.id),
    ];

    for (final txn in financial) {
      // The counterparty is free text like "Devraj Malhotra (Zenith Impex)";
      // resolve it back to a person by name.
      String? payeeId;
      for (final (pattern, criminalId) in namePatterns) {
        if (pattern.hasMatch(txn.counterparty)) {
          payeeId = criminalId;
          break;
        }
      }

      if (payeeId != null && payeeId != txn.criminalId) {
        accumulator.add(
          src: personNode(txn.criminalId),
          dst: personNode(payeeId),
          relation: RelationType.PAID,
          evidenceId: txn.id,
        );
      }
    }

    // --- Text co-mentions -> CO_OCCURRED / ASSOCIATED --------------------
    for (final record in textRecords) {
      final mentioned = extraction
          .mentionsIn(record.id)
          .where((m) => m.type == EntityType.PERSON)
          .map((m) => m.resolvedCriminalId)
          .whereType<String>()
          .toSet()
          .toList()
        ..sort();

      if (mentioned.length < 2) continue;

      final body = '${record.title}\n${record.body}';
      final relation = _coLocationCue.hasMatch(body)
          ? RelationType.CO_OCCURRED
          : RelationType.ASSOCIATED;

      // Undirected in meaning, so record one edge per unordered pair.
      for (var i = 0; i < mentioned.length; i++) {
        for (var j = i + 1; j < mentioned.length; j++) {
          accumulator.add(
            src: personNode(mentioned[i]),
            dst: personNode(mentioned[j]),
            relation: relation,
            evidenceId: record.id,
          );
        }
      }
    }

    // --- Attribute edges: person -> phone / vehicle / org / location -----
    for (final mention in extraction.mentions) {
      final owner = mention.resolvedCriminalId;
      if (owner == null || mention.type == EntityType.PERSON) continue;

      final prefix = switch (mention.type) {
        EntityType.PHONE => 'E-PHONE-',
        EntityType.VEHICLE => 'E-VEHICLE-',
        EntityType.ORG => 'E-ORG-',
        EntityType.LOCATION => 'E-LOC-',
        EntityType.PERSON => 'E-PERSON-',
      };
      final nodeId = '$prefix${EntityExtractor.slug(mention.value)}';
      if (!entitiesById.containsKey(nodeId)) continue;

      accumulator.add(
        src: personNode(owner),
        dst: nodeId,
        relation: mention.type == EntityType.LOCATION
            ? RelationType.LOCATED_AT
            : RelationType.ASSOCIATED,
        evidenceId: mention.sourceRecordId,
      );
    }

    final edges = accumulator.toEdges();

    // Drop nodes nothing connects to, so the canvas shows the network rather
    // than a field of orphans - except people, who stay visible even when
    // isolated because "this subject has no known links" is a finding.
    final connected = <String>{
      for (final e in edges) ...[e.srcEntityId, e.dstEntityId],
    };
    final nodes = entitiesById.values
        .where((e) => e.type == EntityType.PERSON || connected.contains(e.id))
        .toList();

    return GraphBuildResult(entities: nodes, edges: edges);
  }
}

/// Nodes and edges produced by a build.
class GraphBuildResult {
  final List<Entity> entities;
  final List<Edge> edges;

  const GraphBuildResult({required this.entities, required this.edges});
}

/// Collapses repeated observations of the same relationship into one weighted
/// edge, accumulating the evidence that supports it.
class _EdgeAccumulator {
  final Map<String, _EdgeDraft> _drafts = {};

  void add({
    required String src,
    required String dst,
    required RelationType relation,
    required String evidenceId,
  }) {
    // Symmetric relations are keyed on the unordered pair so that A-with-B and
    // B-with-A are one edge, not two.
    final symmetric = relation == RelationType.CO_OCCURRED ||
        relation == RelationType.ASSOCIATED;
    final pair = symmetric && src.compareTo(dst) > 0 ? [dst, src] : [src, dst];
    final key = '${pair[0]}|${pair[1]}|${relation.name}';

    _drafts
        .putIfAbsent(
          key,
          () => _EdgeDraft(src: pair[0], dst: pair[1], relation: relation),
        )
        .evidence
        .add(evidenceId);
  }

  List<Edge> toEdges() {
    var counter = 0;
    return _drafts.values.map((draft) {
      counter++;
      final evidence = draft.evidence.toList()..sort();
      return Edge(
        id: 'EDGE-${counter.toString().padLeft(3, '0')}',
        srcEntityId: draft.src,
        dstEntityId: draft.dst,
        relation: draft.relation,
        // Weight is the count of supporting records, so a link backed by five
        // transactions outranks one backed by a single call.
        weight: evidence.length,
        evidenceIds: evidence,
      );
    }).toList();
  }
}

class _EdgeDraft {
  final String src;
  final String dst;
  final RelationType relation;
  final Set<String> evidence = {};

  _EdgeDraft({required this.src, required this.dst, required this.relation});
}
