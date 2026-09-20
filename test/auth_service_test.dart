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
        'SENDGRID_API_KEY': 'sg_test',
        'SENDGRID_FROM_EMAIL': 'sender@example.test',
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
        expect(request.url.toString(), 'https://api.sendgrid.com/v3/mail/send');
        expect(request.headers['authorization'], 'Bearer sg_test');
        expect(request.headers['content-type'], 'application/json');
        expect(request.body,
            contains('"from":{"email":"sender@example.test"}'));
        expect(request.body,
            contains('"to":[{"email":"analyst@example.test"}]'));
        expect(request.body, contains('"type":"text/html"'));
        expect(request.body,
            contains('Your verification code is <strong>123456</strong>'));
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

  test('failed SendGrid delivery exposes a demo code and audits the fallback',
      () async {
    final Database db = await DatabaseHelper.openInMemory();
    final audit = AuditLogger(db);
    final auth = AuthService(
      db: db,
      audit: audit,
      httpClient: MockClient(
          (_) async => http.Response('{"errors":[{"message":"invalid key"}]}', 401)),
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

  test('DEMO_MODE skips SendGrid and exposes a demo code', () async {
    AppConfig.overrideForTest({
      'SENDGRID_API_KEY': 'sg_test',
      'SENDGRID_FROM_EMAIL': 'sender@example.test',
      'DEMO_MODE': 'true',
    });
    final Database db = await DatabaseHelper.openInMemory();
    final auth = AuthService(
      db: db,
      audit: AuditLogger(db),
      httpClient: MockClient(
          (_) async => fail('SendGrid must not be called in demo mode')),
      otpGenerator: () => '123456',
    );

    final delivery = await auth.requestRegistrationOtp('analyst@example.test');

    expect(delivery.demoCode, '123456');
    await db.close();
  });

  test('password reset verifies an OTP, replaces the password, and audits it',
      () async {
    final Database db = await DatabaseHelper.openInMemory();
    final audit = AuditLogger(db);
    final auth = AuthService(
      db: db,
      audit: audit,
      httpClient: MockClient((_) async => httpResponse()),
      otpGenerator: () => '123456',
    );
    await auth.requestRegistrationOtp('analyst@example.test');
    await auth.verifyAndCreatePassword(
        rawEmail: 'analyst@example.test',
        code: '123456',
        password: 'Original#Pass2026');

    await auth.requestPasswordResetOtp('analyst@example.test');
    await auth.verifyAndResetPassword(
        rawEmail: 'analyst@example.test',
        code: '123456',
        password: 'Replacement#Pass2026');

    await expectLater(
        auth.signIn(
            rawEmail: 'analyst@example.test', password: 'Original#Pass2026'),
        throwsA(isA<AuthException>()));
    expect(
        await auth.signIn(
            rawEmail: 'analyst@example.test', password: 'Replacement#Pass2026'),
        startsWith('USER-'));
    final reset = (await audit.getAllLogs())
        .singleWhere((entry) => entry.action == LogAction.PASSWORD_RESET);
    expect(reset.targetType, 'PasswordReset');
    expect(reset.targetId, 'analyst@example.test');
    await db.close();
  });

  test('password reset rejects a wrong OTP and logs the failed reset',
      () async {
    final Database db = await DatabaseHelper.openInMemory();
    final audit = AuditLogger(db);
    final auth = AuthService(
      db: db,
      audit: audit,
      httpClient: MockClient((_) async => httpResponse()),
      otpGenerator: () => '123456',
    );
    await auth.requestRegistrationOtp('analyst@example.test');
    await auth.verifyAndCreatePassword(
        rawEmail: 'analyst@example.test',
        code: '123456',
        password: 'Original#Pass2026');
    await auth.requestPasswordResetOtp('analyst@example.test');

    await expectLater(
        auth.verifyAndResetPassword(
            rawEmail: 'analyst@example.test',
            code: '000000',
            password: 'Replacement#Pass2026'),
        throwsA(isA<AuthException>()));
    final failure = (await audit.getAllLogs()).last;
    expect(failure.action, LogAction.LOGIN_FAIL);
    expect(failure.targetType, 'PasswordReset');
    await db.close();
  });

  test('password reset rejects an expired OTP', () async {
    var now = DateTime(2026, 9, 19, 12);
    final Database db = await DatabaseHelper.openInMemory();
    final audit = AuditLogger(db);
    final auth = AuthService(
      db: db,
      audit: audit,
      httpClient: MockClient((_) async => httpResponse()),
      otpGenerator: () => '123456',
      now: () => now,
    );
    await auth.requestRegistrationOtp('analyst@example.test');
    await auth.verifyAndCreatePassword(
        rawEmail: 'analyst@example.test',
        code: '123456',
        password: 'Original#Pass2026');
    await auth.requestPasswordResetOtp('analyst@example.test');
    now = now.add(AuthService.otpExpiry);

    await expectLater(
        auth.verifyAndResetPassword(
            rawEmail: 'analyst@example.test',
            code: '123456',
            password: 'Replacement#Pass2026'),
        throwsA(isA<AuthException>()));
    final failure = (await audit.getAllLogs()).last;
    expect(failure.action, LogAction.LOGIN_FAIL);
    expect(failure.targetType, 'PasswordReset');
    await db.close();
  });
}

http.Response httpResponse() => http.Response('', 202);
