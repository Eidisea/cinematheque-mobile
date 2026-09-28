import 'package:flutter/material.dart';

import '../auth/staff_session.dart';
import '../theme/staff_theme.dart';

/// Staff sign-in (Firebase Authentication, email + password).
/// Customers never sign in — this screen exists only in the staff web app.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.session});

  final StaffSession session;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.signIn(email: _email.text, password: _password.text);
      // Success: the router moves on once the staff record is confirmed.
    } on StaffSignInException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
                child: AutofillGroup(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Cinematheque Centre Davao',
                            style: textTheme.labelLarge?.copyWith(color: StaffColors.brand, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        Text('Staff sign in', style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text('Use the account given to you by Cinematheque.',
                            style: textTheme.bodyMedium?.copyWith(color: StaffColors.textMuted)),
                        const SizedBox(height: 24),
                        ListenableBuilder(
                          listenable: widget.session,
                          builder: (context, _) {
                            final message = _error ?? widget.session.notice;
                            return message == null ? const SizedBox.shrink() : _ErrorBanner(message: message);
                          },
                        ),
                        TextFormField(
                          controller: _email,
                          decoration: const InputDecoration(labelText: 'Email'),
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email, AutofillHints.username],
                          textInputAction: TextInputAction.next,
                          enabled: !_busy,
                          validator: (v) {
                            final value = v?.trim() ?? '';
                            if (value.isEmpty) return 'Enter your email.';
                            if (!value.contains('@') || !value.contains('.')) return 'Enter a valid email address.';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _password,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            suffixIcon: IconButton(
                              tooltip: _showPassword ? 'Hide password' : 'Show password',
                              icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                              onPressed: () => setState(() => _showPassword = !_showPassword),
                            ),
                          ),
                          obscureText: !_showPassword,
                          autofillHints: const [AutofillHints.password],
                          textInputAction: TextInputAction.done,
                          enabled: !_busy,
                          onFieldSubmitted: (_) => _submit(),
                          validator: (v) => (v ?? '').isEmpty ? 'Enter your password.' : null,
                        ),
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: _busy ? null : _submit,
                          child: _busy
                              ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('Sign in'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: StaffColors.dangerTint,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: StaffColors.danger.withValues(alpha: 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, color: StaffColors.danger, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(message, style: const TextStyle(color: StaffColors.danger), semanticsLabel: 'Error: $message'),
            ),
          ],
        ),
      ),
    );
  }
}
