import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/di/app_services.dart';
import '../../../core/errors/app_exceptions.dart';
import '../../../main.dart';
import '../../theme/app_theme.dart';
import '../home/home_shell.dart';
import 'widgets/network_reveal_panel.dart';

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
  bool _registering = false,
      _resetting = false,
      _otpSent = false,
      _busy = false;
  Timer? _resendCooldown;
  int _resendSeconds = 0;
  String? _message;
  int _otpRowGeneration = 0;

  @override
  void dispose() {
    _resendCooldown?.cancel();
    _email.dispose();
    _password.dispose();
    _otp.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if ((_registering || _resetting) && !_otpSent) {
        await _requestOtp();
      } else if (_registering) {
        await widget.services.auth.verifyAndCreatePassword(
            rawEmail: _email.text, code: _otp.text, password: _password.text);
        final userId = await widget.services.auth
            .signIn(rawEmail: _email.text, password: _password.text);
        await widget.services.completeLogin(userId);
        if (mounted) _enterApp();
      } else if (_resetting) {
        await widget.services.auth.verifyAndResetPassword(
            rawEmail: _email.text, code: _otp.text, password: _password.text);
        if (mounted) {
          setState(() {
            _resetting = false;
            _otpSent = false;
            _otp.clear();
            _password.clear();
            _otpRowGeneration++;
            _message = 'Password reset. Sign in with your new password.';
          });
        }
      } else {
        final userId = await widget.services.auth
            .signIn(rawEmail: _email.text, password: _password.text);
        await widget.services.completeLogin(userId);
        if (mounted) _enterApp();
      }
    } on AppException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } catch (_) {
      if (mounted) {
        setState(() =>
            _message = 'Sign-in is temporarily unavailable. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resendOtp() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await _requestOtp();
    } on AppException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } catch (_) {
      if (mounted) {
        setState(
            () => _message = 'Unable to resend the code. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestOtp() async {
    final delivery = _registering
        ? await widget.services.auth.requestRegistrationOtp(_email.text)
        : await widget.services.auth.requestPasswordResetOtp(_email.text);
    if (!mounted) return;
    setState(() {
      _otpSent = true;
      _otp.clear();
      _otpRowGeneration++;
      _message = delivery.isDemoFallback
          ? 'Demo mode: your code is ${delivery.demoCode}. It expires in one minute.'
          : 'Code sent. It expires in one minute.';
    });
    _startResendCooldown();
  }

  void _startResendCooldown() {
    _resendCooldown?.cancel();
    setState(() => _resendSeconds = 30);
    _resendCooldown = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _resendSeconds <= 1) {
        timer.cancel();
        if (mounted) setState(() => _resendSeconds = 0);
        return;
      }
      setState(() => _resendSeconds--);
    });
  }

  void _enterApp() => Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) =>
          ServicesScope(services: widget.services, child: const HomeShell())));

  void _toggleMode() => setState(() {
        if (_resetting) {
          _resetting = false;
        } else {
          _registering = !_registering;
        }
        _otpSent = false;
        _otp.clear();
        _otpRowGeneration++;
        _message = null;
        _resendSeconds = 0;
        _resendCooldown?.cancel();
      });

  void _startReset() => setState(() {
        _resetting = true;
        _otpSent = false;
        _otp.clear();
        _otpRowGeneration++;
        _message = null;
        _password.clear();
      });

  bool get _showOtpRow => (_registering || _resetting) && _otpSent;
  bool get _showPassword => (!_registering && !_resetting) || _otpSent;

  String get _title => _registering
      ? 'Create account'
      : _resetting
          ? 'Reset your password'
          : 'Investigator sign-in';

  String get _subtitle => _registering
      ? "Use your official email. We'll send a 6-digit code to verify it."
      : _resetting
          ? "Use your account email. We'll send a 6-digit code to reset your password."
          : 'Sign in with your investigator email and password.';

  String get _submitLabel {
    if (_busy) return 'Please wait…';
    if ((_registering || _resetting) && !_otpSent) {
      return _resetting ? 'Send reset code' : 'Send code';
    }
    if (_registering) return 'Verify and create password';
    if (_resetting) return 'Verify and reset password';
    return 'Sign in';
  }

  bool get _messageIsSuccess =>
      _message != null &&
      (_message!.startsWith('Code sent') ||
          _message!.startsWith('Demo mode:') ||
          _message!.startsWith('Password reset'));

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.background,
        body: LayoutBuilder(builder: (context, constraints) {
          final showIllustration = constraints.maxWidth >= 900;
          final form = _SignInForm(state: this);
          if (!showIllustration) {
            return SafeArea(child: Center(child: form));
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Expanded(flex: 11, child: NetworkRevealPanel()),
              Expanded(
                flex: 9,
                child: ColoredBox(
                  color: AppColors.surface,
                  child: Center(child: form),
                ),
              ),
            ],
          );
        }),
      );
}

class _SignInForm extends StatelessWidget {
  final _LoginScreenState state;
  const _SignInForm({required this.state});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const _WaitingNodeBadge(),
            const SizedBox(height: 16),
            _StepIndicator(verifyActive: state._showOtpRow),
            const SizedBox(height: 12),
            Text(state._title,
                style: const TextStyle(
                    fontFamily: AppTheme.displayFamily,
                    fontWeight: FontWeight.bold,
                    fontSize: 28,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            Text(state._subtitle,
                style: const TextStyle(
                    fontSize: 14, color: AppColors.textSecondary)),
            const SizedBox(height: 28),
            const _FieldLabel('EMAIL ADDRESS'),
            const SizedBox(height: 8),
            _DarkTextField(
              controller: state._email,
              keyboardType: TextInputType.emailAddress,
              hintText: 'name@agency.gov.in',
              enabled: !state._busy,
            ),
            if (state._showOtpRow) ...[
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const _FieldLabel('VERIFICATION CODE'),
                  TextButton(
                    onPressed: state._busy || state._resendSeconds > 0
                        ? null
                        : state._resendOtp,
                    style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    child: Text(
                        state._resendSeconds > 0
                            ? 'Resend (${state._resendSeconds}s)'
                            : 'Resend',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.primary)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _OtpBoxes(
                key: ValueKey(state._otpRowGeneration),
                enabled: !state._busy,
                onChanged: (code) => state._otp.text = code,
              ),
            ],
            if (state._showPassword) ...[
              const SizedBox(height: 20),
              _FieldLabel(state._registering
                  ? 'CREATE PASSWORD'
                  : state._resetting
                      ? 'NEW PASSWORD'
                      : 'PASSWORD'),
              const SizedBox(height: 8),
              _DarkTextField(
                controller: state._password,
                obscureText: true,
                hintText: (state._registering || state._resetting)
                    ? '12+ chars, upper, lower, number, symbol'
                    : '••••••••••••',
                enabled: !state._busy,
              ),
            ],
            if (!state._registering && !state._resetting) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: state._busy ? null : state._startReset,
                  style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 0),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  child: const Text('Forgot password?',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.primary)),
                ),
              ),
            ],
            if (state._message != null) ...[
              const SizedBox(height: 12),
              Text(state._message!,
                  style: TextStyle(
                      fontSize: 12,
                      color: state._messageIsSuccess
                          ? AppColors.accentEmerald
                          : AppColors.accentRose)),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: state._busy ? null : state._submit,
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.background,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(state._submitLabel,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    if (!state._busy) ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward, size: 16),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: TextButton(
                onPressed: state._busy ? null : state._toggleMode,
                child: Text(
                    state._resetting
                        ? 'Back to sign in'
                        : state._registering
                            ? 'Already have an account? Sign in'
                            : 'New investigator? Register',
                    style: const TextStyle(
                        fontSize: 14, color: AppColors.textSecondary)),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_outline,
                    size: 14, color: AppColors.textMuted),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                      'Face authentication is unavailable until a Linux-compatible camera '
                      'and enrolled recognition model are configured.',
                      textAlign: TextAlign.center,
                      style: AppTheme.mono
                          .copyWith(fontSize: 11, color: AppColors.textMuted)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
          color: AppColors.textSecondary));
}

class _DarkTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final bool obscureText;
  final bool enabled;
  final TextInputType? keyboardType;
  const _DarkTextField({
    required this.controller,
    required this.hintText,
    this.obscureText = false,
    this.enabled = true,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border));
    return TextField(
      controller: controller,
      obscureText: obscureText,
      enabled: enabled,
      keyboardType: keyboardType,
      style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
        filled: true,
        fillColor: AppColors.background,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 17, vertical: 13.5),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
            borderSide: const BorderSide(color: AppColors.primary)),
      ),
    );
  }
}

class _WaitingNodeBadge extends StatelessWidget {
  const _WaitingNodeBadge();
  @override
  Widget build(BuildContext context) => SizedBox(
      width: 32,
      height: 32,
      child: CustomPaint(
        painter: const _DashedCirclePainter(color: AppColors.primary),
        child: Center(
            child: Text('+',
                style: AppTheme.mono
                    .copyWith(fontSize: 12, color: AppColors.primary))),
      ));
}

class _DashedCirclePainter extends CustomPainter {
  final Color color;
  const _DashedCirclePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width / 2 - 1;
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    const dashDegrees = 18.0, gapDegrees = 12.0;
    var angle = 0.0;
    while (angle < 360) {
      final start = angle * math.pi / 180;
      const sweep = dashDegrees * math.pi / 180;
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), start,
          sweep, false, paint);
      angle += dashDegrees + gapDegrees;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedCirclePainter oldDelegate) => false;
}

class _StepIndicator extends StatelessWidget {
  final bool verifyActive;
  const _StepIndicator({required this.verifyActive});

  @override
  Widget build(BuildContext context) {
    TextStyle style(bool active) => TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
        color: active ? AppColors.primary : AppColors.textMuted);
    return Row(
      children: [
        Text('1 IDENTIFY', style: style(!verifyActive)),
        const SizedBox(width: 16),
        Text('2 VERIFY', style: style(verifyActive)),
      ],
    );
  }
}

/// Six single-digit boxes that behave like one 6-character code field:
/// typing advances focus forward, backspace on an empty box moves back.
class _OtpBoxes extends StatefulWidget {
  final ValueChanged<String> onChanged;
  final bool enabled;
  const _OtpBoxes({super.key, required this.onChanged, this.enabled = true});

  @override
  State<_OtpBoxes> createState() => _OtpBoxesState();
}

class _OtpBoxesState extends State<_OtpBoxes> {
  static const _length = 6;
  late final _controllers =
      List.generate(_length, (_) => TextEditingController());
  late final _focusNodes = List.generate(_length, (_) => FocusNode());

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _emit() => widget.onChanged(_controllers.map((c) => c.text).join());

  void _onChanged(int index, String value) {
    if (value.length > 1) {
      value = value.substring(value.length - 1);
      _controllers[index].text = value;
    }
    _emit();
    if (value.isNotEmpty && index < _length - 1) {
      _focusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var i = 0; i < _length; i++)
          SizedBox(
            width: 48,
            height: 48,
            child: TextField(
              controller: _controllers[i],
              focusNode: _focusNodes[i],
              enabled: widget.enabled,
              autofocus: i == 0,
              textAlign: TextAlign.center,
              maxLength: 1,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary),
              decoration: InputDecoration(
                counterText: '',
                filled: true,
                fillColor: AppColors.background,
                contentPadding: EdgeInsets.zero,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.border)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.border)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        const BorderSide(color: AppColors.primary, width: 2)),
              ),
              onChanged: (value) => _onChanged(i, value),
            ),
          ),
      ],
    );
  }
}
