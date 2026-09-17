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
/// registration codes. Passwords are salted, iterated SHA-256 derivations;
/// neither OTPs nor plaintext passwords are persisted or written to audit data.
class AuthService {
  static const otpExpiry = Duration(minutes: 1);
  static const _iterations = 120000;

  final Database _db;
  final AuditLogger _audit;
  final http.Client _http;
  final String Function() _otpGenerator;
  final Map<String, _PendingOtp> _pending = {};

  AuthService(
      {required Database db,
      required AuditLogger audit,
      http.Client? httpClient,
      String Function()? otpGenerator})
      : _db = db,
        _audit = audit,
        _http = httpClient ?? http.Client(),
        _otpGenerator = otpGenerator ?? _newOtp;

  Future<OtpDelivery> requestRegistrationOtp(String rawEmail) async {
    final email = _email(rawEmail);
    final existing =
        await _db.query('app_users', where: 'email = ?', whereArgs: [email]);
    if (existing.isNotEmpty) {
      throw const AuthException(
          'An account already exists for this email. Sign in instead.');
    }
    final code = _otpGenerator();
    _pending[email] = _PendingOtp(code, DateTime.now().add(otpExpiry));

    if (AppConfig.demoMode) {
      await _logOtpSent(email, demoFallback: true, reason: 'DEMO_MODE=true');
      return OtpDelivery.demo(code);
    }

    http.Response? response;
    try {
      if (!AppConfig.isResendConfigured) {
        throw const AuthException('RESEND_API_KEY is not configured.');
      }
      response = await _http
          .post(
            Uri.parse('https://api.resend.com/emails'),
            headers: {
              'Authorization': 'Bearer ${AppConfig.resendApiKey}',
              'Content-Type': 'application/json'
            },
            body: jsonEncode({
              'from': 'onboarding@resend.dev',
              'to': [email],
              'subject': 'Your CrimeIntel verification code',
              'html':
                  '<p>Your verification code is <strong>$code</strong>.</p><p>It expires in one minute.</p>',
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const AuthException(
            'Resend did not accept the verification email.');
      }
      await _logOtpSent(email);
      return const OtpDelivery.emailed();
    } catch (error, stackTrace) {
      debugPrint(
        'Resend OTP send failed; using demo fallback: $error\n'
        'HTTP status: ${response?.statusCode ?? 'no response'}\n'
        'HTTP response body: ${response?.body ?? 'no response body'}\n'
        '$stackTrace',
      );
      await _logOtpSent(email,
          demoFallback: true, reason: 'Resend send failed');
      return OtpDelivery.demo(code);
    }
  }

  Future<void> _logOtpSent(String email,
          {bool demoFallback = false, String? reason}) =>
      _audit.log(
        context: const SystemContext(),
        action: LogAction.OTP_SENT,
        targetType: 'Registration',
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
    if (pending == null ||
        !DateTime.now().isBefore(pending.expiresAt) ||
        pending.code != code.trim()) {
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
  const _PendingOtp(this.code, this.expiresAt);
}
