import 'dart:async';

import 'package:flutter/material.dart';

import 'core/constants/constants.dart';
import 'core/di/app_services.dart';
import 'data/db/database_helper.dart';
import 'llm/model_bootstrap.dart';
import 'ui/screens/auth/login_screen.dart';
import 'ui/screens/bootstrap/model_bootstrap_screen.dart';
import 'ui/theme/app_theme.dart';
import 'ui/widgets/startup_failure_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  DatabaseHelper.initFfi();
  runApp(const CrimeIntelApp());
}

class CrimeIntelApp extends StatefulWidget {
  const CrimeIntelApp({super.key});

  @override
  State<CrimeIntelApp> createState() => _CrimeIntelAppState();
}

class _CrimeIntelAppState extends State<CrimeIntelApp> {
  late Future<AppServices> _startup;
  ModelBootstrap? _modelBootstrap;
  bool _modelsReady = false;

  @override
  void initState() {
    super.initState();
    _startup = _bootstrap();
  }

  /// Opens the database, seeds on first run, and derives the graph.
  ///
  /// The RAG index is not built here — it needs the embedding model, and the
  /// app must still open for records and logs when Ollama is not running.
  Future<AppServices> _bootstrap() async {
    final services = await AppServices.bootstrap();
    await services.prepareData();
    _modelBootstrap?.dispose();
    _modelBootstrap = ModelBootstrap(audit: services.audit)
      ..addListener(_onModelBootstrapChanged);
    // The first /api/tags check happens before the model page is built. When
    // both tags already exist, login follows without flashing that page.
    _modelsReady = await _modelBootstrap!.requiredModelsPresent();
    if (!_modelsReady) {
      unawaited(_modelBootstrap!.ensureModels().then((ready) {
        if (mounted) setState(() => _modelsReady = ready);
      }));
    }
    return services;
  }

  void _onModelBootstrapChanged() {
    if (mounted) setState(() {});
  }

  void _retry() {
    final modelBootstrap = _modelBootstrap;
    if (modelBootstrap != null) {
      modelBootstrap.ensureModels().then((ready) {
        if (mounted) setState(() => _modelsReady = ready);
      });
    } else {
      setState(() => _startup = _bootstrap());
    }
  }

  @override
  void dispose() {
    _modelBootstrap?.removeListener(_onModelBootstrapChanged);
    _modelBootstrap?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppServices>(
      future: _startup,
      builder: (context, snapshot) {
        final services = snapshot.data;
        Widget home;
        if (snapshot.connectionState != ConnectionState.done) {
          home = const _StartupSplash();
        } else if (snapshot.hasError) {
          home = StartupFailureView(
            error: snapshot.error!,
            onRetry: _retry,
          );
        } else if (_modelsReady) {
          home = LoginScreen(services: services!);
        } else {
          home = ModelBootstrapScreen(
            bootstrap: _modelBootstrap!,
            onRetry: _retry,
          );
        }

        final app = MaterialApp(
          title: AppConstants.appName,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.darkTheme,
          home: home,
        );

        if (services != null) {
          return ServicesScope(
            services: services,
            child: app,
          );
        }
        return app;
      },
    );
  }
}

/// Makes the composition root available to the widget tree.
class ServicesScope extends InheritedWidget {
  final AppServices services;

  const ServicesScope({
    super.key,
    required this.services,
    required super.child,
  });

  static AppServices of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ServicesScope>();
    assert(scope != null, 'No ServicesScope above this widget.');
    return scope!.services;
  }

  @override
  bool updateShouldNotify(ServicesScope oldWidget) =>
      services != oldWidget.services;
}

class _StartupSplash extends StatelessWidget {
  const _StartupSplash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shield_outlined, size: 48, color: AppColors.primary),
            SizedBox(height: 20),
            Text(
              AppConstants.appName,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Loading case database and deriving the network graph...',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            SizedBox(height: 24),
            SizedBox(
              width: 180,
              child: LinearProgressIndicator(
                color: AppColors.primary,
                backgroundColor: AppColors.surfaceElevated,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
