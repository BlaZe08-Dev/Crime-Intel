import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'core/constants/constants.dart';
import 'data/db/database_helper.dart';
import 'ingest/ingestion_service.dart';
import 'ui/screens/dashboard/dashboard_screen.dart';
import 'ui/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize SQLite FFI for desktop platforms (Windows, Linux, macOS)
  DatabaseHelper.initFfi();

  // Initialize database and seed synthetic dataset if first run
  final ingestionService = IngestionService.instance;
  await ingestionService.seedDatabaseIfEmpty();

  runApp(const CrimeIntelApp());
}

class CrimeIntelApp extends StatelessWidget {
  const CrimeIntelApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const DashboardScreen(),
    );
  }
}
