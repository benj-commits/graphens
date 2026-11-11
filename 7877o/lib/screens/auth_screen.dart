import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final email = TextEditingController();
  final pass = TextEditingController();
  final name = TextEditingController();
  final phone = TextEditingController();
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..forward();

  bool signUp = false;
  bool busy = false;
  bool hidePassword = true;
  String? message;
  String? error;

  @override
  void dispose() {
    email.dispose();
    pass.dispose();
    name.dispose();
    phone.dispose();
    _entrance.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
      message = null;
    });

    try {
      if (signUp) {
        final response = await db.auth.signUp(
          email: email.text.trim(),
          password: pass.text,
          data: {'full_name': name.text.trim(), 'phone': phone.text.trim()},
        );
        if (response.session == null && mounted) {
          setState(() => message = 'Account created. Check your email to confirm, then sign in.');
        }
      } else {
        final result = await db.auth.signInWithPassword(
          email: email.text.trim(),
          password: pass.text,
        );
        if (result.user != null) {
          final authenticated = await tryBiometricAuth();
          if (!authenticated && mounted) {
            setState(() => message = 'Biometric sign-in is optional. You can continue with password sign-in.');
          }
        }
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  InputDecoration _decoration(String label, IconData icon) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: gold),
        filled: true,
        fillColor: const Color(0xFFFFFDF9),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Color(0xFFE9E0D3))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Color(0xFFE9E0D3))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: gold, width: 1.5)),
      );

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width > 760;
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF2E5D2), Color(0xFFFBF6EE), Color(0xFFEDE2D2)]),
              ),
            ),
          ),
          Positioned(top: -100, right: -80, child: _glow(250, const Color(0x35B8893A))),
          Positioned(bottom: -125, left: -100, child: _glow(300, const Color(0x20B8893A))),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(22),
                child: FadeTransition(
                  opacity: CurvedAnimation(parent: _entrance, curve: Curves.easeOut),
                  child: SlideTransition(
                    position: Tween<Offset>(begin: const Offset(0, .08), end: Offset.zero).animate(CurvedAnimation(parent: _entrance, curve: Curves.easeOutCubic)),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: isWide ? 900 : 460),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .93),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: const Color(0xFFE9DDC8)),
                          boxShadow: [BoxShadow(color: ink.withValues(alpha: .10), blurRadius: 40, offset: const Offset(0, 20))],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: isWide ? Row(children: [Expanded(flex: 5, child: _brandPanel()), Expanded(flex: 6, child: _formPanel())]) : _formPanel(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _glow(double size, Color color) => IgnorePointer(
        child: Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
      );

  Widget _brandPanel() => Container(
        height: 610,
        padding: const EdgeInsets.all(38),
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF171512), Color(0xFF393024)]),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('GRAPHEN  /  BAGS', style: TextStyle(color: Color(0xFFE3BD7A), letterSpacing: 3, fontWeight: FontWeight.w700)),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.shopping_bag_outlined, size: 52, color: Color(0xFFE3BD7A)),
              const SizedBox(height: 22),
              Text(
                signUp ? 'Carry your\nstyle forward.' : 'Style in\nevery carry.',
                style: const TextStyle(color: Colors.white, fontSize: 38, height: 1.12, fontWeight: FontWeight.w700, letterSpacing: -.8),
              ),
              const SizedBox(height: 14),
              const Text('Thoughtful design. Beautifully made. Ready for wherever life takes you.', style: TextStyle(color: Color(0xFFD4CABC), height: 1.6, fontSize: 15)),
            ]),
            const Text('A little luxury for every day.', style: TextStyle(color: Color(0xFFE3BD7A), fontStyle: FontStyle.italic)),
          ],
        ),
      );

  Widget _formPanel() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 34),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (MediaQuery.sizeOf(context).width <= 760) ...[
                const Icon(Icons.shopping_bag_outlined, color: gold, size: 40),
                const SizedBox(height: 8),
                const Text('GRAPHEN BAGS', textAlign: TextAlign.center, style: TextStyle(color: ink, letterSpacing: 3, fontWeight: FontWeight.w800)),
                const SizedBox(height: 26),
              ],
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: SlideTransition(position: Tween<Offset>(begin: const Offset(.04, 0), end: Offset.zero).animate(animation), child: child)),
                child: Column(
                  key: ValueKey(signUp),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(signUp ? 'Create account' : 'Welcome back', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: ink)),
                    const SizedBox(height: 6),
                    Text(signUp ? 'Join us and find your everyday favorite.' : 'Sign in to continue your Graphen experience.', style: const TextStyle(color: Color(0xFF77716A), height: 1.4)),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              AnimatedSize(duration: const Duration(milliseconds: 250), curve: Curves.easeInOut, child: signUp ? Column(children: [
                TextFormField(controller: name, textCapitalization: TextCapitalization.words, decoration: _decoration('Full name', Icons.person_outline), validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your full name' : null),
                const SizedBox(height: 13),
                TextFormField(controller: phone, keyboardType: TextInputType.phone, decoration: _decoration('Phone / WhatsApp', Icons.phone_outlined), validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your phone number' : null),
                const SizedBox(height: 13),
              ]) : const SizedBox.shrink()),
              TextFormField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: _decoration('Email address', Icons.email_outlined),
                validator: (v) => v == null || !v.trim().contains('@') ? 'Enter a valid email address' : null,
              ),
              const SizedBox(height: 13),
              TextFormField(
                controller: pass,
                obscureText: hidePassword,
                autofillHints: [signUp ? AutofillHints.newPassword : AutofillHints.password],
                decoration: _decoration('Password', Icons.lock_outline).copyWith(
                  suffixIcon: IconButton(
                    tooltip: hidePassword ? 'Show password' : 'Hide password',
                    icon: Icon(hidePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: Colors.black45),
                    onPressed: () => setState(() => hidePassword = !hidePassword),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Enter your password';
                  if (signUp && v.length < 10) return 'Use at least 10 characters';
                  return null;
                },
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                _notice(error!, isError: true),
              ],
              if (message != null) ...[
                const SizedBox(height: 12),
                _notice(message!),
              ],
              const SizedBox(height: 20),
              SizedBox(
                height: 54,
                child: ElevatedButton(
                  onPressed: busy ? null : submit,
                  style: ElevatedButton.styleFrom(backgroundColor: ink, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                  child: busy
                      ? const SizedBox(width: 21, height: 21, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text(signUp ? 'Create my account' : 'Sign in', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward_rounded, size: 19),
                        ]),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: busy ? null : () => setState(() { signUp = !signUp; error = null; message = null; }),
                child: Text(signUp ? 'Already have an account?  Sign in' : 'New to Graphen?  Create an account', style: const TextStyle(color: ink, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      );

  Widget _notice(String text, {bool isError = false}) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: isError ? const Color(0xFFFFF0ED) : const Color(0xFFF0F7ED), borderRadius: BorderRadius.circular(12)),
        child: Text(text, style: TextStyle(color: isError ? const Color(0xFF9B3025) : const Color(0xFF356B36), fontSize: 13)),
      );
}
