import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final email = TextEditingController(), pass = TextEditingController(), name = TextEditingController(), phone = TextEditingController();
  bool signUp = false, busy = false;

  Future<void> submit() async {
    setState(() => busy = true);
    try {
      if (signUp) {
        await db.auth.signUp(email: email.text.trim(), password: pass.text, data: {'full_name': name.text.trim(), 'phone': phone.text.trim()});
      } else {
        await db.auth.signInWithPassword(email: email.text.trim(), password: pass.text);
      }
    } catch (e) {
      if (mounted) snack(context, e.toString());
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(children: [
                const Text('Graphen', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: ink)),
                const Text('BAGS', style: TextStyle(letterSpacing: 8, color: gold, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                const Text('Style in Every Carry', style: TextStyle(fontStyle: FontStyle.italic)),
                const SizedBox(height: 28),
                if (signUp) ...[
                  TextField(controller: name, decoration: const InputDecoration(labelText: 'Full name')),
                  const SizedBox(height: 12),
                  TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone / WhatsApp')),
                  const SizedBox(height: 12),
                ],
                TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
                const SizedBox(height: 12),
                TextField(controller: pass, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
                const SizedBox(height: 20),
                ElevatedButton(onPressed: busy ? null : submit, child: Text(signUp ? 'Create account' : 'Sign in')),
                TextButton(onPressed: () => setState(() => signUp = !signUp), child: Text(signUp ? 'Have an account? Sign in' : 'New here? Create account')),
              ]),
            ),
          ),
        ),
      );
}
