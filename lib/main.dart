import 'package:flutter/material.dart';

import 'core/constants/constants.dart';
import 'core/di/app_services.dart';
import 'data/db/database_helper.dart';
import 'ui/screens/home/home_shell.dart';
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
    await services.logUnauthenticatedStart();
    return services;
  }

  void _retry() => setState(() => _startup = _bootstrap());

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: FutureBuilder<AppServices>(
        future: _startup,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _StartupSplash();
          }
          if (snapshot.hasError) {
            return StartupFailureView(
              error: snapshot.error!,
              onRetry: _retry,
            );
          }
          return ServicesScope(
            services: snapshot.data!,
            child: const HomeShell(),
          );
        },
      ),
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
