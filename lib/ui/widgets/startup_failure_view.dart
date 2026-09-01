import 'package:flutter/material.dart';

import '../../core/errors/app_exceptions.dart';
import '../theme/app_theme.dart';

/// Shown when bootstrap fails.
///
/// Startup previously swallowed every exception into an empty dashboard, which
/// looked like "the database is empty" no matter what actually went wrong.
/// Failing visibly, with the real reason and a retry, is worth far more when
/// something breaks minutes before a demo.
class StartupFailureView extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const StartupFailureView({
    super.key,
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final message =
        error is AppException ? (error as AppException).message : '$error';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.error_outline,
                          color: AppColors.accentRose, size: 26),
                      SizedBox(width: 10),
                      Text(
                        'CrimeIntel could not start',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    message,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Try again'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
