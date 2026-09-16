import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
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

  AuthService({required Database db, required AuditLogger audit, http.Client? httpClient,
      String Function()? otpGenerator})
      : _db = db,
        _audit = audit,
        _http = httpClient ?? http.Client(),
        _otpGenerator = otpGenerator ?? _newOtp;

  Future<void> requestRegistrationOtp(String rawEmail) async {
    final email = _email(rawEmail);
    final existing = await _db.query('app_users', where: 'email = ?', whereArgs: [email]);
    if (existing.isNotEmpty) throw const AuthException('An account already exists for this email. Sign in instead.');
    if (!AppConfig.isPlunkConfigured || AppConfig.plunkFromEmail.isEmpty) {
      throw const AuthException('Email OTP is not configured. Set PLUNK_API_KEY and PLUNK_FROM_EMAIL in local .env.');
    }
    final code = _otpGenerator();
    _pending[email] = _PendingOtp(code, DateTime.now().add(otpExpiry));
    try {
      final response = await _http.post(
        Uri.parse('https://next-api.useplunk.com/v1/send'),
        headers: {'Authorization': 'Bearer ${AppConfig.plunkApiKey}', 'Content-Type': 'application/json'},
        body: jsonEncode({
          'to': email,
          'from': AppConfig.plunkFromEmail,
          'subject': 'Your CrimeIntel verification code',
          'body': '<p>Your verification code is <strong>$code</strong>.</p><p>It expires in one minute.</p>',
        }),
      ).timeout(const Duration(seconds: 20));
      final body = jsonDecode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300 ||
          body is! Map<String, dynamic> || body['success'] != true) {
        _pending.remove(email);
        throw const AuthException('Could not send the verification code. Check the developer Plunk configuration.');
      }
      await _audit.log(context: const SystemContext(), action: LogAction.OTP_SENT,
          targetType: 'Registration', targetId: email, payload: {'email': email, 'expiresInSeconds': 60});
    } catch (error) {
      if (error is AuthException) rethrow;
      _pending.remove(email);
      throw AuthException('Could not send the verification code. Check your connection and try again.', cause: error);
    }
  }

  Future<void> verifyAndCreatePassword({required String rawEmail, required String code, required String password}) async {
    final email = _email(rawEmail);
    final pending = _pending[email];
    if (pending == null || !DateTime.now().isBefore(pending.expiresAt) || pending.code != code.trim()) {
      await _audit.log(context: const SystemContext(), action: LogAction.LOGIN_FAIL,
          targetType: 'Registration', targetId: email, payload: {'reason': 'invalid_or_expired_otp'});
      throw const AuthException('That verification code is invalid or has expired. Request a new code.');
    }
    _validatePassword(password);
    final salt = base64UrlEncode(List<int>.generate(16, (_) => Random.secure().nextInt(256)));
    try {
      await _db.insert('app_users', {
        'id': IdGenerator.generate('USER'), 'email': email,
        'passwordSalt': salt, 'passwordHash': _derive(password, salt),
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });
      _pending.remove(email);
      await _audit.log(context: const SystemContext(), action: LogAction.OTP_OK,
          targetType: 'Registration', targetId: email, payload: {'email': email});
    } catch (error) {
      throw AuthException('Could not create the account. Please try again.', cause: error);
    }
  }

  Future<String> signIn({required String rawEmail, required String password}) async {
    final email = _email(rawEmail);
    final rows = await _db.query('app_users', where: 'email = ?', whereArgs: [email], limit: 1);
    if (rows.isEmpty || _derive(password, rows.first['passwordSalt'] as String) != rows.first['passwordHash']) {
      await _audit.log(context: const SystemContext(), action: LogAction.LOGIN_FAIL,
          targetType: 'Account', targetId: email, payload: {'reason': 'invalid_credentials'});
      throw const AuthException('Email or password is incorrect.');
    }
    return rows.first['id'] as String;
  }

  String _email(String value) {
    final email = value.trim().toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) throw const AuthException('Enter a valid email address.');
    return email;
  }

  static String _newOtp() =>
      (100000 + Random.secure().nextInt(900000)).toString();

  void _validatePassword(String password) {
    if (password.length < 12 || !RegExp(r'[A-Z]').hasMatch(password) || !RegExp(r'[a-z]').hasMatch(password) || !RegExp(r'[0-9]').hasMatch(password) || !RegExp(r'[^A-Za-z0-9]').hasMatch(password)) {
      throw const AuthException('Use 12+ characters with upper- and lower-case letters, a number, and a symbol.');
    }
  }

  String _derive(String password, String salt) {
    var bytes = utf8.encode('$salt:$password');
    for (var i = 0; i < _iterations; i++) bytes = sha256.convert(bytes).bytes;
    return base64UrlEncode(bytes);
  }

  void dispose() => _http.close();
}

class _PendingOtp {
  final String code;
  final DateTime expiresAt;
  const _PendingOtp(this.code, this.expiresAt);
}
