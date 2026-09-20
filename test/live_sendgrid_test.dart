@Tags(['live'])
library;

import 'dart:io';

import 'package:crime_intel/audit/audit_logger.dart';
import 'package:crime_intel/audit/models/log_entry.dart';
import 'package:crime_intel/auth/auth_service.dart';
import 'package:crime_intel/core/config/app_config.dart';
import 'package:crime_intel/data/db/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(DatabaseHelper.initFfi);

  test('Live SendGrid OTP delivery sends email using credentials from .env',
      () async {
    final envFile = File('.env');
    if (!envFile.existsSync()) {
      markTestSkipped('No .env found');
      return;
    }

    final lines = await envFile.readAsLines();
    String? apiKey;
    String? fromEmail;

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('#') || trimmed.isEmpty) continue;
      final idx = trimmed.indexOf('=');
      if (idx <= 0) continue;
      final key = trimmed.substring(0, idx).trim();
      final val = trimmed.substring(idx + 1).trim();
      if (key == 'SENDGRID_API_KEY') apiKey = val;
      if (key == 'SENDGRID_FROM_EMAIL') fromEmail = val;
    }

    if (apiKey == null ||
        apiKey.isEmpty ||
        fromEmail == null ||
        fromEmail.isEmpty) {
      markTestSkipped('SENDGRID_API_KEY or SENDGRID_FROM_EMAIL not configured');
      return;
    }

    AppConfig.overrideForTest({
      'SENDGRID_API_KEY': apiKey,
      'SENDGRID_FROM_EMAIL': fromEmail,
      'DEMO_MODE': 'false',
    });

    final Database db = await DatabaseHelper.openInMemory();
    final audit = AuditLogger(db);
    final auth = AuthService(
      db: db,
      audit: audit,
      otpGenerator: () => '739104',
    );

    try {
      final delivery = await auth.requestRegistrationOtp(fromEmail);
      expect(delivery.isDemoFallback, isFalse,
          reason: 'SendGrid delivery should succeed, not fall back to demo');
      expect(delivery.demoCode, isNull);

      final logs = await audit.getAllLogs();
      final sentLog =
          logs.singleWhere((entry) => entry.action == LogAction.OTP_SENT);
      expect(sentLog.targetId, fromEmail);
    } finally {
      auth.dispose();
      await db.close();
      AppConfig.resetForTest();
    }
  });
}
