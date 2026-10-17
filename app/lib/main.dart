import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'firebase_options.dart';
import 'models/staff.dart';
import 'screens/auth/auth_screen.dart';
import 'screens/main_layout.dart';
import 'services/auth_service.dart';
import 'services/sync_service.dart';
import 'utils/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  } catch (e) {
    debugPrint('Firebase init error: $e');
  }

  try {
    await Hive.initFlutter();
    await SyncService.instance.init();
  } catch (e) {
    debugPrint('Hive / SyncService init error: $e');
  }

  runApp(const PosApp());
}

class PosApp extends StatelessWidget {
  final Widget? home;
  const PosApp({super.key, this.home});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Shamamo POS',
      theme: AppTheme.darkTheme,
      home: home ?? const AppGate(),
    );
  }
}

class AppGate extends StatelessWidget {
  const AppGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = authSnapshot.data;
        if (user == null) {
          return const AuthScreen();
        }

        return FutureBuilder<Staff?>(
          future: AuthService().restoreCurrentStaff(),
          builder: (context, staffSnapshot) {
            if (staffSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            final staff = staffSnapshot.data;
            if (staff != null) {
              return MainLayout(currentStaff: staff);
            }

            return const AuthScreen();
          },
        );
      },
    );
  }
}
