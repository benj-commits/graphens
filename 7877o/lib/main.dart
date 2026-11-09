import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'api.dart';
import 'config.dart';
import 'theme.dart';
import 'screens/customer_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabasePublishable);
  runApp(const GraphenApp());
}

class GraphenApp extends StatelessWidget {
  const GraphenApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Graphen Bags',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const AuthGate(),
      );
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _booting = true;

  @override
  void initState() {
    super.initState();
    _ensureGuestSession();
  }

  Future<void> _ensureGuestSession() async {
    if (db.auth.currentSession != null) {
      if (mounted) setState(() => _booting = false);
      return;
    }

    try {
      await db.auth.signInAnonymously();
    } catch (_) {
      // If anonymous sign-in is unavailable, continue without forcing auth.
    }

    if (mounted) setState(() => _booting = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_booting) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return const CustomerShell();
  }
}
