import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/formatting.dart';
import '../../data/models/staff_member.dart';
import '../data/staff_api.dart';
import '../staff_services.dart';
import '../theme/staff_theme.dart';
import '../widgets/admin_ui.dart';

/// Staff accounts, as on the website admin: everyone who can sign in to this app (AVT and
/// PDO have the same access), active or not, with Activate / Deactivate. A row opens the
/// account; "New staff account" adds one. Changes go through the server.
class StaffAccountsScreen extends StatefulWidget {
  const StaffAccountsScreen({super.key, required this.myUid});

  /// The signed-in staff member, who cannot deactivate themselves.
  final String? myUid;

  @override
  State<StaffAccountsScreen> createState() => _StaffAccountsScreenState();
}

class _StaffAccountsScreenState extends State<StaffAccountsScreen> {
  StreamSubscription<List<StaffMember>>? _sub;
  List<StaffMember>? _staff;
  Object? _error;
  String? _busy;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sub ??= StaffServices.of(context).data.watchStaff().listen(
          (v) => setState(() => _staff = v),
          onError: (Object e) => setState(() => _error = e),
        );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _setActive(StaffMember m, bool active) async {
    final api = StaffServices.of(context).api;
    if (api == null) return showMessage(context, 'The booking server is not configured for this build.');
    if (!active) {
      final ok = await confirmAction(
        context,
        title: 'Deactivate account?',
        message: '${m.fullName} will be signed out and can no longer sign in. You can activate the account again later.',
        confirm: 'Deactivate',
        danger: true,
      );
      if (!ok || !mounted) return;
    }
    setState(() => _busy = m.uid);
    try {
      await api.setStaffActive(m.uid, active);
      if (mounted) showMessage(context, active ? '${m.fullName} can sign in again.' : '${m.fullName} was deactivated.');
    } catch (e) {
      if (mounted) showMessage(context, staffApiMessage(e));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final pad = width < 600 ? 16.0 : 24.0;
    final staff = _staff;
    const head = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.48, color: StaffColors.gray600);

    Widget table(List<StaffMember> rows) => Panel(children: [
          Container(
            color: StaffColors.surfaceAlt,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: const Row(children: [
              Expanded(flex: 3, child: Text('NAME', style: head)),
              Expanded(flex: 3, child: Text('EMAIL', style: head)),
              SizedBox(width: 90, child: Text('POSITION', style: head)),
              SizedBox(width: 110, child: Text('STATUS', style: head)),
              SizedBox(width: 120, child: Text('ADDED', style: head)),
              SizedBox(width: 120, child: Text('ACTIONS', style: head, textAlign: TextAlign.right)),
            ]),
          ),
          for (final m in rows)
            Material(
              color: StaffColors.surface,
              child: InkWell(
                onTap: () => context.go('/settings/staff/${m.uid}'),
                hoverColor: StaffColors.surfaceAlt,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(children: [
                    Expanded(
                      flex: 3,
                      child: Text.rich(TextSpan(children: [
                        TextSpan(
                          text: m.fullName,
                          style: TextStyle(fontWeight: FontWeight.w600, color: m.isActive ? StaffColors.text : StaffColors.gray400),
                        ),
                        if (m.uid == widget.myUid) const TextSpan(text: '  you', style: TextStyle(fontSize: 12, color: StaffColors.textMuted)),
                      ])),
                    ),
                    Expanded(flex: 3, child: Text(m.email, overflow: TextOverflow.ellipsis)),
                    SizedBox(width: 90, child: Text(m.position.dbValue)),
                    SizedBox(
                      width: 110,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: StateLabel(m.isActive ? 'Active' : 'Inactive', m.isActive ? Tone.success : Tone.neutral),
                      ),
                    ),
                    SizedBox(
                      width: 120,
                      child: Text(m.createdAt == null ? '—' : DateFormat('MMM d, y').format(toManila(m.createdAt!)),
                          style: const TextStyle(fontSize: 13, color: StaffColors.textMuted)),
                    ),
                    SizedBox(
                      width: 120,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: m.uid == widget.myUid
                            ? null
                            : AdminButton(
                                label: m.isActive ? 'Deactivate' : 'Activate',
                                small: true,
                                kind: m.isActive ? AdminButtonKind.danger : AdminButtonKind.secondary,
                                busy: _busy == m.uid,
                                onPressed: () => _setActive(m, !m.isActive),
                              ),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
        ]);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(pad, 20, pad, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Expanded(child: PageTitle('Staff accounts')),
            AdminButton(label: 'New staff account', onPressed: () => context.go('/settings/staff/new')),
          ]),
          const SizedBox(height: 16),
          if (_error != null)
            const Notice('Could not load staff accounts. Check your connection and reload the page.')
          else if (staff == null)
            const Padding(padding: EdgeInsets.symmetric(vertical: 48), child: Center(child: CircularProgressIndicator()))
          else
            LayoutBuilder(
              builder: (context, box) => box.maxWidth >= 860
                  ? table(staff)
                  : SingleChildScrollView(scrollDirection: Axis.horizontal, child: SizedBox(width: 860, child: table(staff))),
            ),
        ],
      ),
    );
  }
}
