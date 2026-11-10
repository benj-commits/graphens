import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'api.dart';
import 'config.dart';
import 'theme.dart';
import 'screens/auth_screen.dart';
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

/// Keeps the customer app in step with Supabase auth events from sign-in,
/// sign-up, token refresh, and sign-out. No anonymous session is created, so
/// customers can actually reach the sign-in/sign-up screen.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late Session? _session;
  late final StreamSubscription<AuthState> _authSubscription;

  @override
  void initState() {
    super.initState();
    _session = db.auth.currentSession;
    _authSubscription = db.auth.onAuthStateChange.listen((state) {
      if (!mounted) return;
      setState(() => _session = state.session);
    });
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        child: _session == null
            ? const AuthScreen(key: ValueKey('auth'))
            : const CustomerShell(key: ValueKey('customer')),
      );
}
