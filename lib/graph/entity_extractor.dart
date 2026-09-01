import '../models/criminal.dart';
import '../models/text_record.dart';
import 'models/graph_models.dart';

/// One entity found in a specific piece of text.
class EntityMention {
  final EntityType type;

  /// Canonical surface form, e.g. `Devraj Malhotra`, `+91-98100-99001`.
  final String value;

  /// Id of the record the mention was found in (`FIR-2023-0492`, ...).
  final String sourceRecordId;

  /// Criminal this mention resolves to, when the entity is a known person or
  /// something owned by one. Null for unresolved entities.
  final String? resolvedCriminalId;

  const EntityMention({
    required this.type,
    required this.value,
    required this.sourceRecordId,
    this.resolvedCriminalId,
  });
}

/// Everything extraction produced.
class ExtractionResult {
  final List<Entity> entities;
  final List<EntityMention> mentions;

  /// Phone number to owning criminal id, learned from text.
  final Map<String, String> phoneOwners;

  const ExtractionResult({
    required this.entities,
    required this.mentions,
    required this.phoneOwners,
  });

  List<EntityMention> mentionsIn(String recordId) =>
      mentions.where((m) => m.sourceRecordId == recordId).toList();
}

/// Extracts people, phones, vehicles, organisations and locations from the
/// unstructured FIR / intel / surveillance text (`docs/TechSpec.md` §2.6).
///
/// This is **gazetteer-plus-pattern NER**, which is what `docs/TechSpec.md`
/// calls the "spaCy-style" option. Concretely:
///
/// * **People** are matched against a dictionary built from the criminal
///   records themselves — full names plus every alias. That is a real lookup
///   over real text, not a hardcoded node list.
/// * **Phones, vehicle registrations and organisations** come from patterns
///   applied to the record body.
/// * **Locations** are matched against a gazetteer assembled from the
///   locations that appear in the records.
///
/// The alternative — asking Granite for structured extraction — is sanctioned
/// by the TechSpec, but it makes the graph non-deterministic and unavailable
/// whenever Ollama is down. For a graph the demo depends on, deterministic
/// wins; the model is used for the *narrative* over the graph instead.
class EntityExtractor {
  /// Indian mobile format used throughout the dataset, plus a looser fallback.
  static final RegExp _phonePattern =
      RegExp(r'\+91[-\s]?\d{5}[-\s]?\d{5}|\b\d{10}\b');

  /// Indian vehicle registration, e.g. `MH-12-XX-4901`.
  static final RegExp _vehiclePattern =
      RegExp(r'\b[A-Z]{2}-\d{2}-[A-Z]{2}-\d{3,4}\b');

  /// Organisation-ish capitalised phrases ending in a company-type word.
  static final RegExp _orgPattern = RegExp(
    r'\b([A-Z][a-zA-Z]+(?:\s+[A-Z][a-zA-Z]+)*)\s+'
    r'(Impex|Traders|Enterprises|Freight|Logistics|Exports|Imports|Holdings|Pvt|Ltd)\b',
  );

  /// Runs extraction over every text record.
  ExtractionResult extract({
    required List<Criminal> criminals,
    required List<TextRecord> textRecords,
  }) {
    final entities = <String, Entity>{};
    final mentions = <EntityMention>[];
    final phoneOwners = <String, String>{};

    // Gazetteer: every name and alias -> criminal id, compiled to
    // word-boundary patterns. Substring matching would be wrong here: the
    // alias "DM" occurs inside "admin", and "Anna" inside "Annapurna", so a
    // naive `contains` invents links that are not in the text.
    final personPatterns = <(RegExp, String)>[];
    for (final c in criminals) {
      personPatterns.add((wordPattern(c.name), c.id));
      for (final alias in c.aliases) {
        if (alias.trim().length >= 2) {
          personPatterns.add((wordPattern(alias), c.id));
        }
      }
    }

    // Location gazetteer, assembled from the records rather than hardcoded.
    final locationPatterns = <(RegExp, String)>[];
    final seenLocations = <String>{};
    for (final c in criminals) {
      final loc = c.lastKnownLoc.trim();
      if (loc.isNotEmpty && seenLocations.add(loc.toLowerCase())) {
        locationPatterns.add((wordPattern(loc), loc));
      }
    }

    void addEntity(Entity entity) =>
        entities.putIfAbsent(entity.id, () => entity);

    for (final record in textRecords) {
      final body = '${record.title}\n${record.body}';

      // --- People ---
      final peopleHere = <String>{};
      for (final (pattern, criminalId) in personPatterns) {
        if (!pattern.hasMatch(body)) continue;
        if (!peopleHere.add(criminalId)) continue;

        final criminal = criminals.firstWhere((c) => c.id == criminalId);
        final entityId = 'E-PERSON-$criminalId';
        addEntity(Entity(
          id: entityId,
          type: EntityType.PERSON,
          value: criminal.name,
          firstSeenIn: record.id,
        ));
        mentions.add(EntityMention(
          type: EntityType.PERSON,
          value: criminal.name,
          sourceRecordId: record.id,
          resolvedCriminalId: criminalId,
        ));
      }

      // --- Phones ---
      for (final match in _phonePattern.allMatches(body)) {
        final phone = match.group(0)!.trim();
        final entityId = 'E-PHONE-${slug(phone)}';
        addEntity(Entity(
          id: entityId,
          type: EntityType.PHONE,
          value: phone,
          firstSeenIn: record.id,
        ));

        // Ownership inference: if exactly one person is named in this record,
        // a phone number in it is attributed to them. With several people
        // present the association is ambiguous, so we decline to guess.
        final owner = peopleHere.length == 1 ? peopleHere.first : null;
        if (owner != null) phoneOwners.putIfAbsent(phone, () => owner);

        mentions.add(EntityMention(
          type: EntityType.PHONE,
          value: phone,
          sourceRecordId: record.id,
          resolvedCriminalId: owner,
        ));
      }

      // --- Vehicles ---
      for (final match in _vehiclePattern.allMatches(body)) {
        final plate = match.group(0)!;
        final entityId = 'E-VEHICLE-${slug(plate)}';
        addEntity(Entity(
          id: entityId,
          type: EntityType.VEHICLE,
          value: plate,
          firstSeenIn: record.id,
        ));
        mentions.add(EntityMention(
          type: EntityType.VEHICLE,
          value: plate,
          sourceRecordId: record.id,
          resolvedCriminalId: peopleHere.length == 1 ? peopleHere.first : null,
        ));
      }

      // --- Organisations ---
      for (final match in _orgPattern.allMatches(body)) {
        final org = match.group(0)!.trim();
        final entityId = 'E-ORG-${slug(org)}';
        addEntity(Entity(
          id: entityId,
          type: EntityType.ORG,
          value: org,
          firstSeenIn: record.id,
        ));
        mentions.add(EntityMention(
          type: EntityType.ORG,
          value: org,
          sourceRecordId: record.id,
          resolvedCriminalId: peopleHere.length == 1 ? peopleHere.first : null,
        ));
      }

      // --- Locations ---
      for (final (pattern, location) in locationPatterns) {
        if (!pattern.hasMatch(body)) continue;
        final entityId = 'E-LOC-${slug(location)}';
        addEntity(Entity(
          id: entityId,
          type: EntityType.LOCATION,
          value: location,
          firstSeenIn: record.id,
        ));
        mentions.add(EntityMention(
          type: EntityType.LOCATION,
          value: location,
          sourceRecordId: record.id,
        ));
      }
    }

    // Every criminal gets a person node even if no narrative text names them,
    // so the graph shows the full roster rather than only the talkative ones.
    for (final c in criminals) {
      addEntity(Entity(
        id: 'E-PERSON-${c.id}',
        type: EntityType.PERSON,
        value: c.name,
        firstSeenIn: c.id,
      ));
    }

    return ExtractionResult(
      entities: entities.values.toList(),
      mentions: mentions,
      phoneOwners: phoneOwners,
    );
  }

  /// Case-insensitive, whole-word matcher for a gazetteer term.
  static RegExp wordPattern(String term) =>
      RegExp(r'\b' + RegExp.escape(term.trim()) + r'\b', caseSensitive: false);

  static String slug(String input) => input
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '')
      .toUpperCase();
}
