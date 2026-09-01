import '../auth/models/investigator.dart';
import '../models/case_note.dart';
import '../models/criminal.dart';
import '../models/media_item.dart';
import '../models/structured_records.dart';
import '../models/text_record.dart';

class SeedData {
  static const int baseTime = 1698800000000; // Late 2023 base epoch ms

  static final List<Criminal> criminals = [
    const Criminal(
      id: 'C-001',
      name: 'Devraj Malhotra',
      aliases: ['DM', 'Seth'],
      dob: '1979-03-11',
      gender: 'M',
      knownFor: 'money laundering, orchestration of fraud network',
      status: CriminalStatus.UNDER_WATCH,
      lastKnownLoc: 'Pune',
      riskLevel: RiskLevel.HIGH,
      createdAt: baseTime,
      updatedAt: baseTime + 86400000 * 30,
      isDeleted: false,
    ),
    const Criminal(
      id: 'C-002',
      name: 'Farhan Qureshi',
      aliases: ['FQ'],
      dob: '1990-07-22',
      gender: 'M',
      knownFor: 'phishing operations, SIM-box fraud',
      status: CriminalStatus.AT_LARGE,
      lastKnownLoc: 'Nagpur',
      riskLevel: RiskLevel.MED,
      createdAt: baseTime + 86400000 * 2,
      updatedAt: baseTime + 86400000 * 25,
      isDeleted: false,
    ),
    const Criminal(
      id: 'C-003',
      name: 'Ravi Deshmukh',
      aliases: ['Anna'],
      dob: '1985-12-02',
      gender: 'M',
      knownFor: 'logistics, smuggling routes',
      status: CriminalStatus.IN_CUSTODY,
      lastKnownLoc: 'Nashik',
      riskLevel: RiskLevel.MED,
      createdAt: baseTime + 86400000 * 5,
      updatedAt: baseTime + 86400000 * 20,
      isDeleted: false,
    ),
    const Criminal(
      id: 'C-004',
      name: 'Sunita Rao',
      aliases: ['Madam'],
      dob: '1982-05-19',
      gender: 'F',
      knownFor: 'hawala transfers, shell accounts',
      status: CriminalStatus.AT_LARGE,
      lastKnownLoc: 'Mumbai',
      riskLevel: RiskLevel.HIGH,
      createdAt: baseTime + 86400000 * 8,
      updatedAt: baseTime + 86400000 * 28,
      isDeleted: false,
    ),
    const Criminal(
      id: 'C-005',
      name: 'Imran Shaikh',
      aliases: ['Chotu'],
      dob: '1997-09-30',
      gender: 'M',
      knownFor: 'courier, cash pickups, low-level muscle',
      status: CriminalStatus.AT_LARGE,
      lastKnownLoc: 'Thane',
      riskLevel: RiskLevel.LOW,
      createdAt: baseTime + 86400000 * 10,
      updatedAt: baseTime + 86400000 * 15,
      isDeleted: false,
    ),
  ];

  static final List<CdrRecord> cdrRecords = [
    // C-002 -> C-001 (frequent, short calls)
    const CdrRecord(
      id: 'CDR-001',
      criminalId: 'C-002',
      callerId: '+91-98200-11223',
      calleeId: '+91-98100-99001', // C-001
      ts: baseTime + 86400000 * 3 + 3600000 * 2,
      durationSec: 45,
      cellSite: 'Nagpur-East-T3',
    ),
    const CdrRecord(
      id: 'CDR-002',
      criminalId: 'C-002',
      callerId: '+91-98200-11223',
      calleeId: '+91-98100-99001',
      ts: baseTime + 86400000 * 5 + 3600000 * 14,
      durationSec: 32,
      cellSite: 'Nagpur-Central-T1',
    ),
    const CdrRecord(
      id: 'CDR-003',
      criminalId: 'C-002',
      callerId: '+91-98200-11223',
      calleeId: '+91-98100-99001',
      ts: baseTime + 86400000 * 9 + 3600000 * 21,
      durationSec: 58,
      cellSite: 'Nagpur-North-T4',
    ),

    // C-003 -> C-001 (regular calls)
    const CdrRecord(
      id: 'CDR-004',
      criminalId: 'C-003',
      callerId: '+91-97300-44556',
      calleeId: '+91-98100-99001',
      ts: baseTime + 86400000 * 7 + 3600000 * 11,
      durationSec: 140,
      cellSite: 'Nashik-MIDC-T2',
    ),
    const CdrRecord(
      id: 'CDR-005',
      criminalId: 'C-003',
      callerId: '+91-97300-44556',
      calleeId: '+91-98100-99001',
      ts: baseTime + 86400000 * 14 + 3600000 * 18,
      durationSec: 115,
      cellSite: 'Nashik-Highway-T1',
    ),

    // C-005 -> C-001 (occasional)
    const CdrRecord(
      id: 'CDR-006',
      criminalId: 'C-005',
      callerId: '+91-96500-77889',
      calleeId: '+91-98100-99001',
      ts: baseTime + 86400000 * 11 + 3600000 * 8,
      durationSec: 50,
      cellSite: 'Thane-Station-T3',
    ),

    // C-002 -> C-005 (a few calls)
    const CdrRecord(
      id: 'CDR-007',
      criminalId: 'C-002',
      callerId: '+91-98200-11223',
      calleeId: '+91-96500-77889',
      ts: baseTime + 86400000 * 12 + 3600000 * 16,
      durationSec: 85,
      cellSite: 'Nagpur-Central-T1',
    ),
  ];

  static final List<FinancialTxn> financialTxns = [
    // Baseline transfers C-004 -> C-001
    const FinancialTxn(
      id: 'TXN-001',
      criminalId: 'C-004',
      counterparty: 'Devraj Malhotra (Zenith Impex)',
      amount: 250000.0,
      currency: 'INR',
      ts: baseTime + 86400000 * 2,
      channel: 'NEFT / Shell Account',
    ),
    const FinancialTxn(
      id: 'TXN-002',
      criminalId: 'C-004',
      counterparty: 'Devraj Malhotra (Zenith Impex)',
      amount: 300000.0,
      currency: 'INR',
      ts: baseTime + 86400000 * 9,
      channel: 'RTGS / Royal Holdings',
    ),

    // ANOMALY BURST: C-004 -> C-001 sudden surge in week 3
    const FinancialTxn(
      id: 'TXN-003',
      criminalId: 'C-004',
      counterparty: 'Devraj Malhotra (Zenith Impex)',
      amount: 2500000.0, // 10x baseline!
      currency: 'INR',
      ts: baseTime + 86400000 * 21 + 3600000 * 10,
      channel: 'Hawala Direct Transfer',
    ),
    const FinancialTxn(
      id: 'TXN-004',
      criminalId: 'C-004',
      counterparty: 'Devraj Malhotra (Zenith Impex)',
      amount: 3200000.0, // Anomaly spike
      currency: 'INR',
      ts: baseTime + 86400000 * 22 + 3600000 * 15,
      channel: 'Hawala Direct Transfer',
    ),
    const FinancialTxn(
      id: 'TXN-005',
      criminalId: 'C-004',
      counterparty: 'Devraj Malhotra (Zenith Impex)',
      amount: 1800000.0, // Anomaly spike
      currency: 'INR',
      ts: baseTime + 86400000 * 24 + 3600000 * 9,
      channel: 'Hawala Cash Pickup',
    ),

    // C-005 -> C-001 (small frequent cash deposits)
    const FinancialTxn(
      id: 'TXN-006',
      criminalId: 'C-005',
      counterparty: 'Devraj Malhotra (Pune Branch)',
      amount: 15000.0,
      currency: 'INR',
      ts: baseTime + 86400000 * 6,
      channel: 'Cash CDM Deposit',
    ),
    const FinancialTxn(
      id: 'TXN-007',
      criminalId: 'C-005',
      counterparty: 'Devraj Malhotra (Pune Branch)',
      amount: 20000.0,
      currency: 'INR',
      ts: baseTime + 86400000 * 13,
      channel: 'Cash CDM Deposit',
    ),
    const FinancialTxn(
      id: 'TXN-008',
      criminalId: 'C-005',
      counterparty: 'Devraj Malhotra (Pune Branch)',
      amount: 18500.0,
      currency: 'INR',
      ts: baseTime + 86400000 * 20,
      channel: 'Cash CDM Deposit',
    ),

    // C-004 -> C-003 (medium logistics payments)
    const FinancialTxn(
      id: 'TXN-009',
      criminalId: 'C-004',
      counterparty: 'Ravi Deshmukh (Nashik Freight)',
      amount: 120000.0,
      currency: 'INR',
      ts: baseTime + 86400000 * 10,
      channel: 'IMPS Freight Transfer',
    ),
  ];

  static final List<CriminalHistory> criminalHistories = [
    const CriminalHistory(
      id: 'HIST-001',
      criminalId: 'C-001',
      offense: 'Organized Money Laundering Probe (Prevention of Money Laundering Act)',
      date: '2018-04-12',
      dispositionNote: 'Discharged for lack of direct documentary link; key witnesses turned hostile.',
    ),
    const CriminalHistory(
      id: 'HIST-002',
      criminalId: 'C-001',
      offense: 'Shell Company Fraud & Offshore Tax Evasion',
      date: '2021-09-05',
      dispositionNote: 'Under surveillance; frozen two accounts linked to Zenith Impex.',
    ),
    const CriminalHistory(
      id: 'HIST-003',
      criminalId: 'C-002',
      offense: 'SIM-Box Spoofing & Phishing Syndicate (IT Act Sec 66D)',
      date: '2020-02-14',
      dispositionNote: 'Bail granted, subsequently jumped bail; non-bailable warrant active.',
    ),
    const CriminalHistory(
      id: 'HIST-004',
      criminalId: 'C-003',
      offense: 'Inter-state Contraband Transport & Smuggling',
      date: '2019-11-20',
      dispositionNote: 'Apprehended at Nashik toll post; currently lodged in judicial custody.',
    ),
    const CriminalHistory(
      id: 'HIST-005',
      criminalId: 'C-004',
      offense: 'Unlawful Hawala Currency Operations (FEMA Violation)',
      date: '2017-06-18',
      dispositionNote: 'Absconding from Mumbai jurisdiction; red-corner notice advisory pending.',
    ),
    const CriminalHistory(
      id: 'HIST-006',
      criminalId: 'C-005',
      offense: 'Extortion, Assault & Illegal Cash Carrier Service',
      date: '2022-01-10',
      dispositionNote: 'Charge sheeted; released on surety; acts as active field runner.',
    ),
  ];

  static final List<TextRecord> textRecords = [
    const TextRecord(
      id: 'FIR-2023-0492',
      criminalId: 'C-002',
      kind: TextRecordKind.FIR,
      title: 'FIR 492/2023: Cyber Phishing Network in Nagpur',
      body: 'FIR registered at Cyber Crime PS Nagpur against Farhan Qureshi (C-002, alias FQ) '
          'for operating an unauthorized SIM-box routing terminal. The accused utilized primary phone number '
          '+91-98200-11223 and was seen operating from a white Maruti Swift hatchback with registration '
          'MH-12-XX-4901 across Nagpur and Wardha road corridors.',
      createdAt: baseTime + 86400000 * 3,
    ),
    const TextRecord(
      id: 'INTEL-2023-0881',
      criminalId: 'C-001',
      kind: TextRecordKind.INTEL,
      title: 'Intel Memo: Seth & Zenith Impex Shell Routing',
      body: 'Classified intelligence intercept: Operative known as "Seth" (identified as Devraj Malhotra, '
          'C-001) operates as the ultimate controller behind Zenith Impex accounts in Pune. '
          'Multiple sub-nodes including Sunita Rao (Madam, C-004) and Farhan Qureshi (FQ, C-002) report '
          'directly to Seth for treasury distribution.',
      createdAt: baseTime + 86400000 * 6,
    ),
    const TextRecord(
      id: 'SURV-2023-0104',
      criminalId: 'C-003',
      kind: TextRecordKind.SURVEILLANCE_NOTE,
      title: 'Surveillance Log: Nashik Central Warehouse Depot',
      body: 'Surveillance unit observed Ravi Deshmukh (Anna, C-003) and Imran Shaikh (Chotu, C-005) '
          'co-located at the Godavari industrial warehouse on two consecutive nights (2023-11-08 and 2023-11-09). '
          'Consignments of encrypted mobile handsets were transferred into transport trucks.',
      createdAt: baseTime + 86400000 * 9,
    ),
    const TextRecord(
      id: 'REPORT-2023-1120',
      criminalId: 'C-004',
      kind: TextRecordKind.REPORT,
      title: 'FIU Financial Intelligence Alert: Hawala Surge in Mumbai',
      body: 'Financial Intelligence Unit alert flagging suspicious remittance patterns. '
          'Sunita Rao (Madam, C-004) orchestrated rapid cash collection via runner Imran Shaikh (Chotu, C-005) '
          'and remitted multi-crore amounts directly to shell entities in Pune controlled by Devraj Malhotra (C-001).',
      createdAt: baseTime + 86400000 * 23,
    ),
    const TextRecord(
      id: 'INTEL-2023-1205',
      criminalId: 'C-001',
      kind: TextRecordKind.INTEL,
      title: 'Triangulation Report: BKC Mumbai Co-Location',
      body: 'Cellular tower triangulation logs placed Devraj Malhotra (C-001) and Sunita Rao (C-004) '
          'in the identical geographic sector in Bandra Kurla Complex (BKC), Mumbai on 2023-11-14 '
          'between 14:00 and 16:30 hours.',
      createdAt: baseTime + 86400000 * 14,
    ),
    // Subscriber attribution for the number the rest of the network calls.
    // Criminals.md asks each snippet to embed extractable entities including
    // phone numbers; without this the handset that every other subject dials
    // has no owner, and entity extraction cannot resolve those calls to a
    // person. Deliberately names one subject only, so attribution is
    // unambiguous.
    const TextRecord(
      id: 'INTEL-2023-0902',
      criminalId: 'C-001',
      kind: TextRecordKind.INTEL,
      title: 'Subscriber Attribution: Pune Handset',
      body: 'Telecom nodal officer confirmed subscriber attribution for handset '
          '+91-98100-99001. The connection is registered to Devraj Malhotra at a '
          'Pune address and has been in continuous use since 2022. Billing is '
          'settled in cash by a third party.',
      createdAt: baseTime + 86400000 * 4,
    ),
  ];

  static final List<MediaItem> mediaItems = [
    const MediaItem(
      id: 'MEDIA-001',
      criminalId: 'C-001',
      type: MediaType.MUGSHOT,
      filePath: 'assets/synthetic/c001_mugshot.png',
      caption: 'Synthetic Mugshot: Devraj Malhotra (C-001)',
      isSynthetic: true,
      createdAt: baseTime,
    ),
    const MediaItem(
      id: 'MEDIA-002',
      criminalId: 'C-002',
      type: MediaType.MUGSHOT,
      filePath: 'assets/synthetic/c002_mugshot.png',
      caption: 'Synthetic Mugshot: Farhan Qureshi (C-002)',
      isSynthetic: true,
      createdAt: baseTime,
    ),
    const MediaItem(
      id: 'MEDIA-003',
      criminalId: 'C-003',
      type: MediaType.MUGSHOT,
      filePath: 'assets/synthetic/c003_mugshot.png',
      caption: 'Synthetic Mugshot: Ravi Deshmukh (C-003)',
      isSynthetic: true,
      createdAt: baseTime,
    ),
    const MediaItem(
      id: 'MEDIA-004',
      criminalId: 'C-004',
      type: MediaType.MUGSHOT,
      filePath: 'assets/synthetic/c004_mugshot.png',
      caption: 'Synthetic Mugshot: Sunita Rao (C-004)',
      isSynthetic: true,
      createdAt: baseTime,
    ),
    const MediaItem(
      id: 'MEDIA-005',
      criminalId: 'C-005',
      type: MediaType.MUGSHOT,
      filePath: 'assets/synthetic/c005_mugshot.png',
      caption: 'Synthetic Mugshot: Imran Shaikh (C-005)',
      isSynthetic: true,
      createdAt: baseTime,
    ),
    const MediaItem(
      id: 'MEDIA-SCENE-001',
      criminalId: 'C-003',
      type: MediaType.CRIME_SCENE,
      filePath: 'assets/synthetic/scene_warehouse.png',
      caption: 'Nashik Warehouse Depot Interior (Evidence Scene)',
      isSynthetic: true,
      createdAt: baseTime + 86400000 * 9,
    ),
    const MediaItem(
      id: 'MEDIA-SCENE-002',
      criminalId: 'C-004',
      type: MediaType.CRIME_SCENE,
      filePath: 'assets/synthetic/scene_desk_ledgers.png',
      caption: 'Cash Counting Desk and Ledger Confiscation',
      isSynthetic: true,
      createdAt: baseTime + 86400000 * 23,
    ),
    const MediaItem(
      id: 'MEDIA-BLURRY-001',
      criminalId: 'C-001',
      type: MediaType.CRIME_SCENE,
      filePath: 'assets/synthetic/blurry_surveillance_still.png',
      caption: 'Blurry Night Surveillance Frame (Candidate for Enhancement)',
      isSynthetic: true,
      createdAt: baseTime + 86400000 * 14,
    ),
  ];

  static final List<CaseNote> caseNotes = [
    const CaseNote(
      id: 'NOTE-001',
      criminalId: 'C-001',
      author: NoteAuthor.INVESTIGATOR,
      text: 'Subject Devraj Malhotra maintains no registered assets in his direct name. '
          'Zenith Impex accounts represent primary nexus for financial consolidation.',
      createdAt: baseTime + 86400000 * 7,
    ),
  ];

  static const Investigator defaultInvestigator = Investigator(
    id: 'INV-001',
    displayName: 'Lead Analyst K. Roy',
    email: 'investigator@crimeintel.local',
    faceEmbeddings: [],
    createdAt: baseTime,
  );
}
