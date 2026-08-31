# CrimeIntel — Application Flow (AppFlow)

---

## 1. Login Flow

```
Launch app
  │
  ▼
Face login screen → webcam capture
  │
  ├─ face embedding matches enrolled investigator → ✅ authenticated
  │
  └─ no match / no camera → "Use email OTP"
                              │
                              ▼
                        Generate 6-digit code → Plunk sends email
                              │
                              ▼
                        Investigator enters code → verify → ✅ authenticated
  │
  ▼
(All attempts — success, fail, OTP — written to the immutable log)
  │
  ▼
Home / Dashboard
```

## 2. Home / Dashboard

- Search bar + assistant chat entry.
- List of criminals (from synthetic DB).
- Quick tiles: relationship graph, recent logs, image enhancer.

## 3. Chat-over-Database (RAG) Flow

```
Investigator types a question
  │
  ▼
Retrieve top-k relevant records + log entries from local vector store
  │
  ▼
Grounded prompt (retrieved context + source IDs) → Ollama 3B
  │
  ▼
Answer shown WITH the source record IDs it used
  │
  ├─ nothing relevant retrieved → "I don't find that in the database."
  │
  ▼
(The query itself is logged)
```

## 4. Criminal Page Flow

```
Open a criminal
  │  → the moment it opens, a "record viewed" entry is logged (with who + when)
  ▼
See: profile, photos, crime-scene images, records, linked entities, case notes, attached news
  │
  ├─ [Enhance image] → image enhancement flow (§7)
  ├─ [Attach news]   → news search flow (§6)
  ├─ [Add/Update record or image] → investigator action, logged; old state retained
  └─ [Ask assistant about this criminal] → scoped RAG chat
```

## 5. Assistant Actions Flow (bounded)

```
Investigator: "Summarize this and save a case note."
  │
  ▼
Assistant drafts → calls createCaseNote(criminalId, text)   ← the ONLY tool it has
  │
  ▼
Case note saved + logged
  │
  ✗ Assistant CANNOT add/remove images or change the criminal record —
    no such tool exists for it. If asked, it explains it can't.
```

## 6. News Search + Attach Flow

```
Investigator: "Find related news about this person/event."
  │
  ▼
Assistant runs a web search → returns candidate articles
  │
  ▼
Investigator picks one → [Attach to page] (title + link + optional image)
  │
  ▼
Attached to the criminal's page + logged (assistant proposes, human commits)
```

## 7. Image Enhancement Flow

```
Investigator selects a blurry photo/crime-scene image → [Enhance]
  │
  ▼
Local Real-ESRGAN (+ GFPGAN for faces) runs on-demand, one image
  │
  ▼
Enhanced image shown side-by-side, labeled:
   "AI-enhanced visualization — reconstructed detail, not forensic evidence."
  │
  ▼
(Enhancement action logged; investigator may save the output to the page)
```

## 8. Logs / Audit View Flow

```
Open Logs
  │
  ▼
Chronological, append-only feed of EVERYTHING:
   logins, views, uploads, updates, deletions, case notes, enhancements,
   news attachments, LLM queries
  │
  ▼
Each entry shows actor, action, target, time, and chain integrity ✓
  │
  ✗ No delete button anywhere. Deleted records appear as "deleted" events,
    with their prior state still referenced in the log.
```

## 9. Network / Relationship Analysis Flow

```
Open Graph (global or per-criminal)
  │
  ▼
Entities extracted from records → nodes; links (CDR/financial/co-occurrence) → edges
  │
  ▼
Force-directed graph rendered
  │
  ├─ Key individuals highlighted (centrality)
  ├─ Communities/clusters colored (Louvain/Leiden)
  └─ Suspicious patterns flagged (anomaly rules)
  │
  ▼
[Ask assistant to explain the network] → grounded narrative over the graph
```

## 10. State Summary

| Kind | Examples |
|---|---|
| Persistent (local) | criminal records, images, case notes, attached news, enrolled face embeddings, **immutable logs**, vector index |
| Ephemeral (session) | current chat, current graph view, auth session |
| Never mutated by assistant | criminal records, images (assistant may only add case notes) |
| Never deletable | log entries |
