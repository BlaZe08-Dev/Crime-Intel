import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../audit/audit_logger.dart';
import '../audit/models/log_entry.dart';
import '../core/config/app_config.dart';
import '../core/errors/app_exceptions.dart';
import '../core/security/actor_context.dart';
import '../core/utils/id_generator.dart';

/// Local account registration and credential verification.
///
/// OTPs are deliberately memory-only: restarting the app invalidates pending
/// registration and password-reset codes. Passwords are salted, iterated SHA-256 derivations;
/// neither OTPs nor plaintext passwords are persisted or written to audit data.
class AuthService {
  static const otpExpiry = Duration(minutes: 1);
  static const _iterations = 120000;

  final Database _db;
  final AuditLogger _audit;
  final http.Client _http;
  final String Function() _otpGenerator;
  final DateTime Function() _now;
  final Map<String, _PendingOtp> _pending = {};

  AuthService(
      {required Database db,
      required AuditLogger audit,
      http.Client? httpClient,
      String Function()? otpGenerator,
      DateTime Function()? now})
      : _db = db,
        _audit = audit,
        _http = httpClient ?? http.Client(),
        _otpGenerator = otpGenerator ?? _newOtp,
        _now = now ?? DateTime.now;

  Future<OtpDelivery> requestRegistrationOtp(String rawEmail) =>
      _requestOtp(rawEmail, _OtpPurpose.registration);

  Future<OtpDelivery> requestPasswordResetOtp(String rawEmail) =>
      _requestOtp(rawEmail, _OtpPurpose.passwordReset);

  Future<OtpDelivery> _requestOtp(String rawEmail, _OtpPurpose purpose) async {
    final email = _email(rawEmail);
    final existing =
        await _db.query('app_users', where: 'email = ?', whereArgs: [email]);
    if (purpose == _OtpPurpose.registration && existing.isNotEmpty) {
      throw const AuthException(
          'An account already exists for this email. Sign in instead.');
    }
    if (purpose == _OtpPurpose.passwordReset && existing.isEmpty) {
      throw const AuthException('No account exists for this email.');
    }
    final code = _otpGenerator();
    _pending[email] = _PendingOtp(code, _now().add(otpExpiry), purpose);

    if (AppConfig.demoMode) {
      await _logOtpSent(email, purpose,
          demoFallback: true, reason: 'DEMO_MODE=true');
      return OtpDelivery.demo(code);
    }

    http.Response? response;
    try {
      if (!AppConfig.isSendgridConfigured) {
        throw const AuthException(
            'SENDGRID_API_KEY or SENDGRID_FROM_EMAIL is not configured.');
      }
      response = await _http
          .post(
            Uri.parse('https://api.sendgrid.com/v3/mail/send'),
            headers: {
              'Authorization': 'Bearer ${AppConfig.sendgridApiKey}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'personalizations': [
                {
                  'to': [
                    {'email': email}
                  ]
                }
              ],
              'from': {'email': AppConfig.sendgridFromEmail},
              'subject': 'Your CrimeIntel verification code',
              'content': [
                {
                  'type': 'text/html',
                  'value':
                      '<p>Your verification code is <strong>$code</strong>. It expires in one minute.</p>',
                }
              ],
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const AuthException(
            'SendGrid did not accept the verification email.');
      }
      await _logOtpSent(email, purpose);
      return const OtpDelivery.emailed();
    } catch (error, stackTrace) {
      debugPrint(
        'SendGrid OTP send failed; using demo fallback: $error\n'
        'HTTP status: ${response?.statusCode ?? 'no response'}\n'
        'HTTP response body: ${response?.body ?? 'no response body'}\n'
        '$stackTrace',
      );
      await _logOtpSent(email, purpose,
          demoFallback: true, reason: 'SendGrid send failed');
      return OtpDelivery.demo(code);
    }
  }

  Future<void> _logOtpSent(String email, _OtpPurpose purpose,
          {bool demoFallback = false, String? reason}) =>
      _audit.log(
        context: const SystemContext(),
        action: LogAction.OTP_SENT,
        targetType: purpose.targetType,
        targetId: email,
        payload: {
          'email': email,
          'expiresInSeconds': 60,
          if (demoFallback) 'delivery': 'demo fallback, not emailed',
          if (reason != null) 'reason': reason,
        },
      );

  Future<void> verifyAndCreatePassword(
      {required String rawEmail,
      required String code,
      required String password}) async {
    final email = _email(rawEmail);
    final pending = _pending[email];
    if (!_isValidOtp(pending, code, _OtpPurpose.registration)) {
      await _audit.log(
          context: const SystemContext(),
          action: LogAction.LOGIN_FAIL,
          targetType: 'Registration',
          targetId: email,
          payload: {'reason': 'invalid_or_expired_otp'});
      throw const AuthException(
          'That verification code is invalid or has expired. Request a new code.');
    }
    _validatePassword(password);
    final salt = base64UrlEncode(
        List<int>.generate(16, (_) => Random.secure().nextInt(256)));
    try {
      // Record OTP success before creating the account. If audit logging fails,
      // no credential is persisted, preserving the all-actions-are-logged rule.
      await _audit.log(
          context: const SystemContext(),
          action: LogAction.OTP_OK,
          targetType: 'Registration',
          targetId: email,
          payload: {'email': email});
      await _db.insert('app_users', {
        'id': IdGenerator.generate('USER'),
        'email': email,
        'passwordSalt': salt,
        'passwordHash': _derive(password, salt),
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });
      _pending.remove(email);
    } catch (error) {
      throw AuthException('Could not create the account. Please try again.',
          cause: error);
    }
  }

  Future<void> verifyAndResetPassword(
      {required String rawEmail,
      required String code,
      required String password}) async {
    final email = _email(rawEmail);
    final pending = _pending[email];
    if (!_isValidOtp(pending, code, _OtpPurpose.passwordReset)) {
      await _audit.log(
          context: const SystemContext(),
          action: LogAction.LOGIN_FAIL,
          targetType: _OtpPurpose.passwordReset.targetType,
          targetId: email,
          payload: {'reason': 'invalid_or_expired_otp'});
      throw const AuthException(
          'That verification code is invalid or has expired. Request a new code.');
    }
    _validatePassword(password);
    final salt = base64UrlEncode(
        List<int>.generate(16, (_) => Random.secure().nextInt(256)));
    try {
      // Password values are never included in the audit payload or persisted
      // outside the replacement salt and derived hash.
      await _audit.log(
          context: const SystemContext(),
          action: LogAction.PASSWORD_RESET,
          targetType: _OtpPurpose.passwordReset.targetType,
          targetId: email,
          payload: {'email': email});
      await _db.update('app_users',
          {'passwordSalt': salt, 'passwordHash': _derive(password, salt)},
          where: 'email = ?', whereArgs: [email]);
      _pending.remove(email);
    } catch (error) {
      throw AuthException('Could not reset the password. Please try again.',
          cause: error);
    }
  }

  bool _isValidOtp(_PendingOtp? pending, String code, _OtpPurpose purpose) =>
      pending != null &&
      pending.purpose == purpose &&
      _now().isBefore(pending.expiresAt) &&
      pending.code == code.trim();

  Future<String> signIn(
      {required String rawEmail, required String password}) async {
    final email = _email(rawEmail);
    final rows = await _db.query('app_users',
        where: 'email = ?', whereArgs: [email], limit: 1);
    if (rows.isEmpty ||
        _derive(password, rows.first['passwordSalt'] as String) !=
            rows.first['passwordHash']) {
      await _audit.log(
          context: const SystemContext(),
          action: LogAction.LOGIN_FAIL,
          targetType: 'Account',
          targetId: email,
          payload: {'reason': 'invalid_credentials'});
      throw const AuthException('Email or password is incorrect.');
    }
    return rows.first['id'] as String;
  }

  String _email(String value) {
    final email = value.trim().toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      throw const AuthException('Enter a valid email address.');
    }
    return email;
  }

  static String _newOtp() =>
      (100000 + Random.secure().nextInt(900000)).toString();

  void _validatePassword(String password) {
    if (password.length < 12 ||
        !RegExp(r'[A-Z]').hasMatch(password) ||
        !RegExp(r'[a-z]').hasMatch(password) ||
        !RegExp(r'[0-9]').hasMatch(password) ||
        !RegExp(r'[^A-Za-z0-9]').hasMatch(password)) {
      throw const AuthException(
          'Use 12+ characters with upper- and lower-case letters, a number, and a symbol.');
    }
  }

  String _derive(String password, String salt) {
    var bytes = Uint8List.fromList(utf8.encode('$salt:$password'));
    for (var i = 0; i < _iterations; i++) {
      bytes = Uint8List.fromList(sha256.convert(bytes).bytes);
    }
    return base64UrlEncode(bytes);
  }

  void dispose() => _http.close();
}

/// Whether a registration OTP was delivered by email or intentionally exposed
/// in the UI as the documented demo safety net.
class OtpDelivery {
  final String? demoCode;
  const OtpDelivery._(this.demoCode);
  const OtpDelivery.emailed() : this._(null);
  const OtpDelivery.demo(String code) : this._(code);
  bool get isDemoFallback => demoCode != null;
}

class _PendingOtp {
  final String code;
  final DateTime expiresAt;
  final _OtpPurpose purpose;
  const _PendingOtp(this.code, this.expiresAt, this.purpose);
}

enum _OtpPurpose {
  registration('Registration'),
  passwordReset('PasswordReset');

  final String targetType;
  const _OtpPurpose(this.targetType);
}
