import 'package:flutter/material.dart';

import '../../../core/di/app_services.dart';
import '../../../core/errors/app_exceptions.dart';
import '../../../main.dart';
import '../../theme/app_theme.dart';
import '../home/home_shell.dart';

class LoginScreen extends StatefulWidget {
  final AppServices services;
  const LoginScreen({super.key, required this.services});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _otp = TextEditingController();
  bool _registering = false, _otpSent = false, _busy = false;
  String? _message;
  @override
  void dispose() { _email.dispose(); _password.dispose(); _otp.dispose(); super.dispose(); }

  Future<void> _submit() async {
    setState(() { _busy = true; _message = null; });
    try {
      if (_registering && !_otpSent) {
        await widget.services.auth.requestRegistrationOtp(_email.text);
        if (mounted) setState(() { _otpSent = true; _message = 'Code sent. It expires in one minute.'; });
      } else if (_registering) {
        await widget.services.auth.verifyAndCreatePassword(rawEmail: _email.text, code: _otp.text, password: _password.text);
        final userId = await widget.services.auth.signIn(rawEmail: _email.text, password: _password.text);
        await widget.services.completeLogin(userId);
        if (mounted) _enterApp();
      } else {
        final userId = await widget.services.auth.signIn(rawEmail: _email.text, password: _password.text);
        await widget.services.completeLogin(userId);
        if (mounted) _enterApp();
      }
    } on AppException catch (error) { if (mounted) setState(() => _message = error.message); }
    catch (_) { if (mounted) setState(() => _message = 'Sign-in is temporarily unavailable. Please try again.'); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  void _enterApp() => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ServicesScope(services: widget.services, child: const HomeShell())));

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: Card(child: Padding(
      padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Icon(Icons.shield_outlined, color: AppColors.primary, size: 42), const SizedBox(height: 12),
        Text(_registering ? 'Create account' : 'Investigator sign in', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 20), TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email address')),
        if (_registering && _otpSent) ...[const SizedBox(height: 12), TextField(controller: _otp, keyboardType: TextInputType.number, maxLength: 6, decoration: const InputDecoration(labelText: '6-digit verification code'))],
        if (!_registering || _otpSent) ...[const SizedBox(height: 12), TextField(controller: _password, obscureText: true, decoration: InputDecoration(labelText: _registering ? 'Create strong password' : 'Password', helperText: _registering ? '12+ chars, uppercase, lowercase, number, symbol' : null))],
        if (_message != null) Padding(padding: const EdgeInsets.only(top: 14), child: Text(_message!, style: TextStyle(color: _message!.startsWith('Code sent') ? AppColors.accentEmerald : AppColors.accentRose))),
        const SizedBox(height: 18), FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'Please wait...' : (_registering && !_otpSent ? 'Send 1-minute OTP' : _registering ? 'Verify and create password' : 'Sign in'))),
        TextButton(onPressed: _busy ? null : () => setState(() { _registering = !_registering; _otpSent = false; _message = null; }), child: Text(_registering ? 'Already have an account? Sign in' : 'New user? Create an account')),
        const Text('Face authentication is unavailable until a Windows-compatible camera and enrolled recognition model are configured.', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
      ]),
    ))),
  );
}
