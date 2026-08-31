# CrimeIntel — Data Schema (Schema)

Local storage: **SQLite** for records + logs, a **local vector index** for RAG, and a files folder for images. All on the investigator's machine.

---

## 1. Criminal Record

```
Criminal {
  id            : String (PK)
  name          : String
  aliases       : List<String>
  dob           : String
  gender        : String
  knownFor      : String            // primary offenses
  status        : Enum { AT_LARGE, IN_CUSTODY, UNDER_WATCH, DECEASED }
  lastKnownLoc  : String
  riskLevel     : Enum { LOW, MED, HIGH }
  createdAt     : Long
  updatedAt     : Long
  isDeleted     : Boolean            // soft-delete only; history retained in log
}
```

## 2. Media (photos, crime scenes)

```
MediaItem {
  id            : String (PK)
  criminalId    : String (FK, nullable for scene-only)
  type          : Enum { MUGSHOT, PHOTO, CRIME_SCENE, DOCUMENT, ENHANCED }
  filePath      : String
  caption       : String
  sourceItemId  : String?            // if ENHANCED, points to the original
  isSynthetic   : Boolean = true
  createdAt     : Long
}
```

## 3. Structured Records (CDR / financial / history)

```
CdrRecord      { id, criminalId, callerId, calleeId, ts, durationSec, cellSite }
FinancialTxn   { id, criminalId, counterparty, amount, currency, ts, channel }
CriminalHistory{ id, criminalId, offense, date, dispositionNote }
```

## 4. Unstructured Records (FIR / intel)

```
TextRecord {
  id            : String (PK)
  criminalId    : String? (FK)
  kind          : Enum { FIR, INTEL, SURVEILLANCE_NOTE, REPORT }
  title         : String
  body          : String            // free text → entity extraction source
  createdAt     : Long
}
```

## 5. Extracted Entities & Graph

```
Entity {
  id            : String (PK)
  type          : Enum { PERSON, LOCATION, VEHICLE, PHONE, ORG }
  value         : String
  firstSeenIn   : String            // record id
}

Edge {
  id            : String (PK)
  srcEntityId   : String
  dstEntityId   : String
  relation      : Enum { CALLED, PAID, CO_OCCURRED, ASSOCIATED, LOCATED_AT }
  weight        : Int
  evidenceIds   : List<String>      // records supporting this link
}
```

Derived (computed, not stored long-term): centrality scores, community/cluster labels, anomaly flags.

## 6. Case Notes (assistant may create these)

```
CaseNote {
  id            : String (PK)
  criminalId    : String (FK)
  author        : Enum { INVESTIGATOR, ASSISTANT }
  text          : String
  createdAt     : Long
}
```

## 7. Attached News

```
NewsAttachment {
  id            : String (PK)
  criminalId    : String (FK)
  title         : String
  url           : String
  imagePath     : String?
  attachedBy    : Enum { INVESTIGATOR }   // human commits the attach
  createdAt     : Long
}
```

## 8. Immutable Audit Log (hash-chained)

```
LogEntry {
  seq           : Int (PK, monotonic)
  actor         : Enum { INVESTIGATOR, ASSISTANT, SYSTEM }
  action        : Enum { LOGIN_OK, LOGIN_FAIL, OTP_SENT, OTP_OK,
                         VIEW_RECORD, UPLOAD, UPDATE, DELETE,
                         CREATE_CASENOTE, ENHANCE_IMAGE, ATTACH_NEWS, LLM_QUERY }
  targetType    : String            // Criminal, MediaItem, TextRecord, ...
  targetId      : String
  payloadHash   : String            // hash of the action payload / prior state ref
  ts            : Long
  prevHash      : String            // hash of previous entry
  entryHash     : String            // H(all fields above + prevHash)
}
```

**Integrity rule:** `entryHash = SHA256(seq | actor | action | targetType | targetId | payloadHash | ts | prevHash)`. Verifying the chain = recompute each `entryHash` and confirm `prevHash` links. Any edit/removal breaks it → tamper is detectable. **No delete path for log rows exists in code.**

## 9. Auth / Identity (local)

```
Investigator {
  id            : String (PK)
  displayName   : String
  email         : String            // for OTP fallback
  faceEmbeddings: List<Vector>      // enrolled, local only
  createdAt     : Long
}
```

## 10. RAG Index

```
VectorChunk {
  id            : String (PK)
  sourceType    : String            // TextRecord, CaseNote, LogEntry, ...
  sourceId      : String
  text          : String
  embedding     : Vector
}
```

## 11. Privacy / Integrity Posture

- All data synthetic; `isSynthetic = true` on media.
- Face embeddings and secrets never leave the machine, never committed.
- Assistant can write only `CaseNote`; it can never write/edit/delete `Criminal`, `MediaItem`, or any `LogEntry`.
