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
        'RESEND_API_KEY': 're_test',
      }));
  tearDown(AppConfig.resetForTest);

  test('OTP registration requires a strong password and logs auth events',
      () async {
    final Database db = await DatabaseHelper.openInMemory();
    final audit = AuditLogger(db);
    final auth = AuthService(
      db: db,
      audit: audit,
      httpClient: MockClient((request) async {
        expect(request.url.toString(), 'https://api.resend.com/emails');
        expect(request.headers['authorization'], 'Bearer re_test');
        expect(request.headers['content-type'], 'application/json');
        expect(request.body, contains('"from":"onboarding@resend.dev"'));
        expect(request.body, contains('"to":["analyst@example.test"]'));
        expect(request.body, contains('"html":'));
        return httpResponse();
      }),
      otpGenerator: () => '123456',
    );
    await auth.requestRegistrationOtp('analyst@example.test');
    await expectLater(
      auth.verifyAndCreatePassword(
          rawEmail: 'analyst@example.test', code: '123456', password: 'weak'),
      throwsA(isA<AuthException>()),
    );
    await auth.verifyAndCreatePassword(
        rawEmail: 'analyst@example.test',
        code: '123456',
        password: 'Strong#Pass2026');
    final id = await auth.signIn(
        rawEmail: 'analyst@example.test', password: 'Strong#Pass2026');
    expect(id, startsWith('USER-'));
    expect((await audit.getAllLogs()).map((entry) => entry.action),
        containsAll([LogAction.OTP_SENT, LogAction.OTP_OK]));
    await db.close();
  });

  test('failed Resend delivery exposes a demo code and audits the fallback',
      () async {
    final Database db = await DatabaseHelper.openInMemory();
    final audit = AuditLogger(db);
    final auth = AuthService(
      db: db,
      audit: audit,
      httpClient: MockClient(
          (_) async => http.Response('{"message":"invalid key"}', 401)),
      otpGenerator: () => '123456',
    );

    final delivery = await auth.requestRegistrationOtp('analyst@example.test');

    expect(delivery.isDemoFallback, isTrue);
    expect(delivery.demoCode, '123456');
    final sent = (await audit.getAllLogs())
        .singleWhere((entry) => entry.action == LogAction.OTP_SENT);
    expect(sent.targetId, 'analyst@example.test');
    await db.close();
  });

  test('DEMO_MODE skips Resend and exposes a demo code', () async {
    AppConfig.overrideForTest(
        {'RESEND_API_KEY': 're_test', 'DEMO_MODE': 'true'});
    final Database db = await DatabaseHelper.openInMemory();
    final auth = AuthService(
      db: db,
      audit: AuditLogger(db),
      httpClient: MockClient(
          (_) async => fail('Resend must not be called in demo mode')),
      otpGenerator: () => '123456',
    );

    final delivery = await auth.requestRegistrationOtp('analyst@example.test');

    expect(delivery.demoCode, '123456');
    await db.close();
  });
}

http.Response httpResponse() => http.Response('{"id":"email_123"}', 200);
