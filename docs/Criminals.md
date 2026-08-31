# CrimeIntel — Synthetic Criminal Dataset (Criminals.md)

**Purpose:** a fully **synthetic**, fictional dataset of 5 criminals for demoing the system. No real person is depicted. All names, faces, and events are invented. Teammates generate the actual images from the prompts below using their AI image tools.

> ⚠️ Every image must be AI-generated / synthetic. Do not use real photos of real people. Label all media `isSynthetic = true`.

The 5 are deliberately **interconnected** (shared phones, money flows, co-locations) so the relationship-graph, key-individual, and anomaly features have something real to find.

---

## The Network (design intent)

A fictional cross-city fraud + smuggling ring. **Criminal C-001 is the intended "key individual"** (highest centrality — connected to everyone). The graph should reveal that even though C-001 keeps a low public profile.

```
        C-002 ──calls──┐
                       ▼
   C-004 ──pays──►  C-001  ◄──calls── C-003
                       ▲
        C-005 ──pays───┘   (C-005 also co-located with C-003)
```

---

## Criminal Records

### C-001 — "The Hub"
- **Name:** Devraj Malhotra (alias "DM", "Seth")
- **DOB:** 1979-03-11 · **Gender:** M
- **Known for:** money laundering, orchestration of fraud network
- **Status:** UNDER_WATCH · **Risk:** HIGH
- **Last known location:** Pune
- **Role in graph:** central coordinator; rarely acts directly, connects all others.

### C-002 — "The Caller"
- **Name:** Farhan Qureshi (alias "FQ")
- **DOB:** 1990-07-22 · **Gender:** M
- **Known for:** phishing operations, SIM-box fraud
- **Status:** AT_LARGE · **Risk:** MED
- **Last known location:** Nagpur

### C-003 — "The Fixer"
- **Name:** Ravi Deshmukh (alias "Anna")
- **DOB:** 1985-12-02 · **Gender:** M
- **Known for:** logistics, smuggling routes
- **Status:** IN_CUSTODY · **Risk:** MED
- **Last known location:** Nashik

### C-004 — "The Financier"
- **Name:** Sunita Rao (alias "Madam")
- **DOB:** 1982-05-19 · **Gender:** F
- **Known for:** hawala transfers, shell accounts
- **Status:** AT_LARGE · **Risk:** HIGH
- **Last known location:** Mumbai

### C-005 — "The Runner"
- **Name:** Imran Shaikh (alias "Chotu")
- **DOB:** 1997-09-30 · **Gender:** M
- **Known for:** courier, cash pickups, low-level muscle
- **Status:** AT_LARGE · **Risk:** LOW
- **Last known location:** Thane

---

## Structured Records to seed (for the graph)

### CDR (calls) — creates the "who talks to whom" edges
- C-002 → C-001 (frequent, short calls)
- C-003 → C-001 (regular)
- C-005 → C-001 (occasional)
- C-002 → C-005 (a few)

### Financial transactions — creates "money flow" edges
- C-004 → C-001 (large, recurring) ← anomaly: unusually large bursts
- C-005 → C-001 (small, frequent cash deposits)
- C-004 → C-003 (medium)

### Co-location — creates "seen together" edges
- C-003 & C-005 co-located in Nashik on 2 dates
- C-001 & C-004 co-located in Mumbai on 1 date

### Anomaly to plant (so detection has a hit)
- A sudden **burst of large transfers** from C-004 → C-001 in a single week, far above their baseline — the system should flag this.

---

## Unstructured Records to seed (FIR / intel text — for entity extraction)

Write 4–6 short fictional FIR/intel snippets, e.g.:
- An FIR naming C-002 and a phone number, mentioning a vehicle (e.g. "white Swift, MH-12-XX-0000").
- An intel note linking "Seth" (C-001 alias) to a shell company.
- A surveillance note placing C-003 and C-005 at a Nashik warehouse.
- A report mentioning a hawala channel tied to "Madam" (C-004).

Each snippet should embed extractable entities: **person names/aliases, phone numbers, vehicles, locations, org names** — so entity extraction + graph building have material.

---

## Image Generation Prompts (for teammates' AI tools)

> Generate as synthetic AI faces/scenes. Neutral, non-graphic. No real people.

**Mugshots (one per criminal)** — plug the description in:
- C-001: "Photorealistic synthetic mugshot, South Asian man ~45, short greying hair, neutral expression, plain height-chart background, front-facing, neutral lighting. Fictional person."
- C-002: "…South Asian man ~34, stubble, short black hair…"
- C-003: "…South Asian man ~40, heavier build, moustache…"
- C-004: "…South Asian woman ~42, shoulder-length hair, composed expression…"
- C-005: "…South Asian man ~27, thin, short hair, casual…"

**Crime-scene / evidence images (non-graphic):**
- "Synthetic photo of a warehouse interior with stacked cardboard boxes, dim lighting, no people — evidence scene."
- "Synthetic photo of a cluttered desk with cash-counting machine and ledgers, no people."
- "Synthetic photo of a parked white hatchback on a night street, no visible plate detail — surveillance still."

**A deliberately BLURRY image (to demo the enhancer):**
- Generate one mugshot or scene, then **downscale + add blur/noise** so the Real-ESRGAN+GFPGAN enhancement has an obvious before/after. Keep the sharp original too, for honest side-by-side.

---

## Ingestion Notes
- Load these into SQLite on first run (see Schema.md).
- Tag all media `isSynthetic = true`.
- Ensure the seeded CDR/financial/co-location links produce the intended graph, with **C-001 as the highest-centrality node** and the **C-004→C-001 burst** as the flagged anomaly — so the demo's "aha" moments are guaranteed to appear.
