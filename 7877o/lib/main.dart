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

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<AuthState>(
        stream: db.auth.onAuthStateChange,
        builder: (context, _) => db.auth.currentSession == null ? const AuthScreen() : const CustomerShell(),
      );
}
