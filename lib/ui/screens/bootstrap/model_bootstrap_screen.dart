import 'dart:io';

import 'package:flutter/material.dart';

import '../../../llm/model_bootstrap.dart';
import '../../theme/app_theme.dart';

class ModelBootstrapScreen extends StatelessWidget {
  final ModelBootstrap bootstrap;
  final VoidCallback onRetry;

  const ModelBootstrapScreen({
    super.key,
    required this.bootstrap,
    required this.onRetry,
  });

  String _mb(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: bootstrap,
      builder: (context, _) {
        final state = bootstrap.state;
        final fatal = state.phase == ModelBootstrapPhase.fatal;
        final failed = state.phase == ModelBootstrapPhase.failed;
        final pulling = state.phase == ModelBootstrapPhase.pulling;
        return Scaffold(
          backgroundColor: AppColors.background,
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.memory_outlined,
                        size: 52, color: AppColors.primary),
                    const SizedBox(height: 20),
                    Text(
                      fatal
                          ? 'Ollama is required'
                          : 'Preparing local AI models',
                      style: const TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(state.status,
                        style: const TextStyle(color: AppColors.textSecondary)),
                    if (pulling) ...[
                      const SizedBox(height: 28),
                      Text(
                          '${state.model}  •  step ${state.modelIndex + 1} of 2',
                          style: const TextStyle(color: AppColors.textPrimary)),
                      const SizedBox(height: 10),
                      LinearProgressIndicator(
                        value: state.totalBytes == 0 ? null : state.progress,
                        color: AppColors.primary,
                        backgroundColor: AppColors.surfaceElevated,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        state.totalBytes == 0
                            ? 'Contacting Ollama…'
                            : '${(state.progress * 100).toStringAsFixed(0)}% '
                                '(${_mb(state.completedBytes)} of ${_mb(state.totalBytes)})',
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                    if (state.error != null) ...[
                      const SizedBox(height: 22),
                      SelectableText(state.error!,
                          style: const TextStyle(color: AppColors.accentRose)),
                    ],
                    const SizedBox(height: 28),
                    if (failed || fatal)
                      Wrap(
                        spacing: 12,
                        children: [
                          if (!fatal)
                            FilledButton.icon(
                              onPressed: onRetry,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Retry'),
                            ),
                          OutlinedButton.icon(
                            onPressed: () => exit(0),
                            icon: const Icon(Icons.close),
                            label: const Text('Quit'),
                          ),
                        ],
                      )
                    else
                      OutlinedButton.icon(
                        onPressed: () {
                          bootstrap.cancel();
                          exit(0);
                        },
                        icon: const Icon(Icons.close),
                        label: const Text('Cancel / Quit'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
