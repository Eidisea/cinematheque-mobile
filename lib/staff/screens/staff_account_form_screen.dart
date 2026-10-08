import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/staff_member.dart';
import '../data/staff_api.dart';
import '../staff_services.dart';
import '../widgets/admin_ui.dart';
import '../widgets/form_ui.dart';

/// New / edit staff account, as on the website admin: name, email, position (AVT or PDO —
/// same access), and a password (required for new accounts; blank keeps the current one).
class StaffAccountFormScreen extends StatefulWidget {
  const StaffAccountFormScreen({super.key, this.uid});

  /// null → a new account.
  final String? uid;

  @override
  State<StaffAccountFormScreen> createState() => _StaffAccountFormScreenState();
}

class _StaffAccountFormScreenState extends State<StaffAccountFormScreen> {
  StreamSubscription<List<StaffMember>>? _sub;
  StaffMember? _existing;
  bool _loaded = false;

  final _first = TextEditingController();
  final _middle = TextEditingController();
  final _last = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  StaffPosition _position = StaffPosition.avt;
  Map<String, String> _errors = const {};
  bool _saving = false;

  bool get _isNew => widget.uid == null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isNew) {
      _loaded = true;
      return;
    }
    _sub ??= StaffServices.of(context).data.watchStaff().listen((all) {
      final m = all.where((s) => s.uid == widget.uid).firstOrNull;
      if (_existing == null && m != null) {
        _first.text = m.firstName;
        _middle.text = m.middleName ?? '';
        _last.text = m.lastName;
        _email.text = m.email;
        _position = m.position;
      }
      setState(() {
        _existing = m ?? _existing;
        _loaded = true;
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    for (final c in [_first, _middle, _last, _email, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final errors = <String, String>{};
    if (_first.text.trim().isEmpty) errors['firstName'] = 'Enter a first name.';
    if (_last.text.trim().isEmpty) errors['lastName'] = 'Enter a last name.';
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_email.text.trim())) errors['email'] = 'Enter a valid email address.';
    final password = _password.text;
    if (_isNew && password.isEmpty) errors['password'] = 'Enter a password of at least 8 characters.';
    if (password.isNotEmpty && password.length < 8) errors['password'] = 'Use at least 8 characters.';
    if (password.isNotEmpty && password != _confirm.text) errors['confirm'] = 'The passwords don’t match.';
    setState(() => _errors = errors);
    if (errors.isNotEmpty) return;

    final api = StaffServices.of(context).api;
    if (api == null) return showMessage(context, 'The booking server is not configured for this build.');
    final form = StaffAccountForm(
      firstName: _first.text.trim(),
      middleName: _middle.text.trim().isEmpty ? null : _middle.text.trim(),
      lastName: _last.text.trim(),
      email: _email.text.trim(),
      position: _position.dbValue,
      password: password.isEmpty ? null : password,
    );
    setState(() => _saving = true);
    try {
      if (_isNew) {
        await api.createStaff(form);
      } else {
        await api.updateStaff(widget.uid!, form);
      }
      if (!mounted) return;
      showMessage(context, _isNew ? 'Account created. Share the password with ${form.firstName} privately.' : 'Changes saved.');
      context.go('/settings/staff');
    } catch (e) {
      if (!mounted) return;
      if (e is StaffApiException && e.fields.isNotEmpty) setState(() => _errors = e.fields);
      showMessage(context, staffApiMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final pad = width < 600 ? 16.0 : 24.0;
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    if (!_isNew && _existing == null) {
      return Padding(padding: EdgeInsets.all(pad), child: const Notice('This account no longer exists.', tone: Tone.warning));
    }

    Widget field(String label, TextEditingController c, String key, {bool required = false, bool obscure = false, String? hint}) =>
        LabeledField(
          label: label,
          required: required,
          error: _errors[key],
          hint: hint,
          child: TextField(controller: c, obscureText: obscure, autocorrect: false, enableSuggestions: !obscure),
        );
    Widget cell(Widget child) => SizedBox(width: 240, child: child);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(pad, 20, pad, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BackLink('Staff accounts', onTap: () => context.go('/settings/staff')),
          const SizedBox(height: 8),
          PageTitle(_isNew ? 'New staff account' : 'Edit staff account'),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: FormPanel(title: 'Account', children: [
                Wrap(spacing: 16, children: [
                  cell(field('First name', _first, 'firstName', required: true)),
                  cell(field('Middle name', _middle, 'middleName')),
                  cell(field('Last name', _last, 'lastName', required: true)),
                ]),
                Wrap(spacing: 16, children: [
                  SizedBox(width: 496, child: field('Email', _email, 'email', required: true)),
                  cell(LabeledField(
                    label: 'Position',
                    hint: 'AVT and PDO have the same access.',
                    child: ChoiceToggle<StaffPosition>(
                      values: StaffPosition.values,
                      current: _position,
                      label: (p) => p.dbValue,
                      onSelect: (p) => setState(() => _position = p),
                    ),
                  )),
                ]),
                Wrap(spacing: 16, children: [
                  cell(field('Password', _password, 'password',
                      required: _isNew, obscure: true, hint: _isNew ? 'At least 8 characters.' : 'Leave blank to keep the current password.')),
                  cell(field('Confirm password', _confirm, 'confirm', obscure: true)),
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  AdminButton(label: _isNew ? 'Create account' : 'Save changes', busy: _saving, onPressed: _save),
                  const SizedBox(width: 8),
                  AdminButton(label: 'Cancel', kind: AdminButtonKind.secondary, onPressed: () => context.go('/settings/staff')),
                ]),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
