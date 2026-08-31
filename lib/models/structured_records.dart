class CdrRecord {
  final String id;
  final String criminalId;
  final String callerId;
  final String calleeId;
  final int ts;
  final int durationSec;
  final String cellSite;

  const CdrRecord({
    required this.id,
    required this.criminalId,
    required this.callerId,
    required this.calleeId,
    required this.ts,
    required this.durationSec,
    required this.cellSite,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'criminalId': criminalId,
      'callerId': callerId,
      'calleeId': calleeId,
      'ts': ts,
      'durationSec': durationSec,
      'cellSite': cellSite,
    };
  }

  factory CdrRecord.fromMap(Map<String, dynamic> map) {
    return CdrRecord(
      id: map['id'] as String,
      criminalId: map['criminalId'] as String,
      callerId: map['callerId'] as String,
      calleeId: map['calleeId'] as String,
      ts: (map['ts'] as num).toInt(),
      durationSec: (map['durationSec'] as num).toInt(),
      cellSite: map['cellSite'] as String? ?? '',
    );
  }
}

class FinancialTxn {
  final String id;
  final String criminalId;
  final String counterparty;
  final double amount;
  final String currency;
  final int ts;
  final String channel;

  const FinancialTxn({
    required this.id,
    required this.criminalId,
    required this.counterparty,
    required this.amount,
    this.currency = 'INR',
    required this.ts,
    required this.channel,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'criminalId': criminalId,
      'counterparty': counterparty,
      'amount': amount,
      'currency': currency,
      'ts': ts,
      'channel': channel,
    };
  }

  factory FinancialTxn.fromMap(Map<String, dynamic> map) {
    return FinancialTxn(
      id: map['id'] as String,
      criminalId: map['criminalId'] as String,
      counterparty: map['counterparty'] as String,
      amount: (map['amount'] as num).toDouble(),
      currency: map['currency'] as String? ?? 'INR',
      ts: (map['ts'] as num).toInt(),
      channel: map['channel'] as String? ?? '',
    );
  }
}

class CriminalHistory {
  final String id;
  final String criminalId;
  final String offense;
  final String date;
  final String dispositionNote;

  const CriminalHistory({
    required this.id,
    required this.criminalId,
    required this.offense,
    required this.date,
    required this.dispositionNote,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'criminalId': criminalId,
      'offense': offense,
      'date': date,
      'dispositionNote': dispositionNote,
    };
  }

  factory CriminalHistory.fromMap(Map<String, dynamic> map) {
    return CriminalHistory(
      id: map['id'] as String,
      criminalId: map['criminalId'] as String,
      offense: map['offense'] as String,
      date: map['date'] as String,
      dispositionNote: map['dispositionNote'] as String? ?? '',
    );
  }
}
