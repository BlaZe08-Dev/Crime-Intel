import 'package:crime_intel/audit/audit_logger.dart';
import 'package:crime_intel/audit/models/log_entry.dart';
import 'package:crime_intel/auth/auth_service.dart';
import 'package:crime_intel/core/config/app_config.dart';
import 'package:crime_intel/core/errors/app_exceptions.dart';
import 'package:crime_intel/data/db/database_helper.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(DatabaseHelper.initFfi);
  setUp(() => AppConfig.overrideForTest({
        'PLUNK_API_KEY': 'sk_test', 'PLUNK_FROM_EMAIL': 'demo@example.test',
      }));
  tearDown(AppConfig.resetForTest);

  test('OTP registration requires a strong password and logs auth events', () async {
    final Database db = await DatabaseHelper.openInMemory();
    final audit = AuditLogger(db);
    final auth = AuthService(
      db: db,
      audit: audit,
      httpClient: MockClient((_) async => httpResponse()),
      otpGenerator: () => '123456',
    );
    await auth.requestRegistrationOtp('analyst@example.test');
    await expectLater(
      auth.verifyAndCreatePassword(rawEmail: 'analyst@example.test', code: '123456', password: 'weak'),
      throwsA(isA<AuthException>()),
    );
    await auth.verifyAndCreatePassword(rawEmail: 'analyst@example.test', code: '123456', password: 'Strong#Pass2026');
    final id = await auth.signIn(rawEmail: 'analyst@example.test', password: 'Strong#Pass2026');
    expect(id, startsWith('USER-'));
    expect((await audit.getAllLogs()).map((entry) => entry.action),
        containsAll([LogAction.OTP_SENT, LogAction.OTP_OK]));
    await db.close();
  });
}

http.Response httpResponse() => http.Response('{"success":true}', 200);
