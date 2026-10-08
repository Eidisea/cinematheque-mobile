import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/formatting.dart';
import '../../data/models/payment.dart';
import '../../data/models/reservation.dart';
import '../data/staff_api.dart';
import '../staff_services.dart';
import '../theme/staff_theme.dart';
import '../widgets/admin_ui.dart';

/// One booking, as on the website admin: who booked, its state and screening, the actions
/// (Approve · Resend email · Cancel booking), every attendee's declared details, and the
/// booker, payment and email facts on the side.
class ReservationScreen extends StatefulWidget {
  const ReservationScreen({super.key, required this.reservationId});

  final String reservationId;

  @override
  State<ReservationScreen> createState() => _ReservationScreenState();
}

class _ReservationScreenState extends State<ReservationScreen> {
  StreamSubscription<Reservation?>? _sub;
  StreamSubscription<Payment?>? _paySub;
  Reservation? _reservation;
  Payment? _payment;
  bool _loaded = false;
  Object? _error;
  String? _busy; // the action running: approve / resend / cancel

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sub != null) return;
    final data = StaffServices.of(context).data;
    _sub = data
        .watchReservation(widget.reservationId)
        .listen(
          (r) => setState(() {
            _reservation = r;
            _loaded = true;
          }),
          onError: (Object e) => setState(() => _error = e),
        );
    _paySub = data.watchPayment(widget.reservationId).listen((p) => setState(() => _payment = p));
  }

  @override
  void dispose() {
    _sub?.cancel();
    _paySub?.cancel();
    super.dispose();
  }

  Future<void> _run(String action, Future<String> Function(StaffApi api) call) async {
    final api = StaffServices.of(context).api;
    final messenger = ScaffoldMessenger.of(context);
    if (api == null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('The booking server is not configured for this build.')));
      return;
    }
    setState(() => _busy = action);
    try {
      final done = await call(api);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(staffApiMessage(e))));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _cancel(Reservation r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel booking?'),
        content: Text(
          'Cancel ${r.bookingReference}? The booker is emailed and the seats are released.'
          '${_payment?.status == PaymentStatus.verified ? ' The payment is marked for refund.' : ''}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep booking')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: StaffColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel booking'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run('cancel', (api) async {
      await api.cancel(r.id);
      return 'Cancelled ${r.bookingReference}. The booker was emailed.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = StaffServices.of(context).clock.now();
    final width = MediaQuery.sizeOf(context).width;
    final pad = width < 600 ? 16.0 : 24.0;
    final r = _reservation;

    Widget body;
    if (_error != null) {
      body = const Notice('Could not load this booking. Check your connection and reload the page.');
    } else if (!_loaded) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (r == null) {
      body = const Notice('This booking no longer exists.', tone: Tone.warning);
    } else {
      body = _content(r, now);
    }

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(pad, 20, pad, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              onTap: () => context.go('/reservations'),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.arrow_back, size: 15, color: StaffColors.textMuted),
                  SizedBox(width: 6),
                  Text(
                    'Reservations',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: StaffColors.textMuted),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          body,
        ],
      ),
    );
  }

  Widget _content(Reservation r, DateTime now) {
    final payment = _payment;
    final refundDue = r.status == ReservationStatus.cancelled && (payment?.needsRefund ?? false);
    final (label, tone) = bookingState(r, now, refundDue: refundDue);
    final open = r.status != ReservationStatus.cancelled;

    final head = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            style: const TextStyle(fontSize: 13, color: StaffColors.textMuted),
            children: [
              const TextSpan(text: 'Booking '),
              TextSpan(text: r.bookingReference, style: staffMono),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Semantics(
          header: true,
          child: Text(
            '${r.booker.firstName} ${r.booker.lastName}',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, height: 1.3),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 18,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            StateLabel(label, tone),
            Figure('${r.seats.length}', r.seats.length == 1 ? 'seat' : 'seats'),
            Text(
              '${r.screening.eventTitle} · ${formatDateShort(r.screening.startAt)} · ${formatTime(r.screening.startAt)}',
              style: const TextStyle(fontSize: 13, color: StaffColors.textMuted),
            ),
          ],
        ),
      ],
    );

    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (canApprove(r, now))
          AdminButton(
            label: 'Approve',
            busy: _busy == 'approve',
            onPressed: _busy != null
                ? null
                : () => _run('approve', (api) async {
                    await api.approve(r.id);
                    return 'Approved ${r.bookingReference}. The e-ticket was emailed.';
                  }),
          ),
        AdminButton(
          label: 'Resend email',
          kind: AdminButtonKind.secondary,
          busy: _busy == 'resend',
          onPressed: _busy != null
              ? null
              : () => _run('resend', (api) async {
                  final result = await api.resendEmail(r.id);
                  return switch (result) {
                    'sent' => 'Email sent again to ${r.booker.email}.',
                    'not_configured' => 'Email is not set up on the server.',
                    _ => 'The email could not be sent. Try again later.',
                  };
                }),
        ),
        if (open)
          AdminButton(
            label: 'Cancel booking',
            kind: AdminButtonKind.danger,
            busy: _busy == 'cancel',
            onPressed: _busy != null ? null : () => _cancel(r),
          ),
      ],
    );

    final main = AdminSection(
      title: 'Attendee details',
      child: Panel(children: [for (final s in r.seats) _Attendee(seat: s)]),
    );

    final side = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminSection(
          title: 'Booker',
          child: _Facts({
            'Email': r.booker.email,
            'Mobile': r.booker.contactNo,
            'Booked': DateFormat('MMM d, y h:mm a').format(toManila(r.createdAt)),
            if (r.status == ReservationStatus.pending && r.expiresAt != null) 'Expires': '${formatTime(r.expiresAt!)} if unpaid',
            if (r.status == ReservationStatus.cancelled)
              'Cancelled': [
                switch (r.cancellationReason) {
                  CancellationReason.paymentExpired => 'Not paid within 15 min',
                  CancellationReason.customerCancelled => 'By the booker',
                  _ => 'By staff',
                },
                if (r.cancelledAt != null) DateFormat('MMM d, h:mm a').format(toManila(r.cancelledAt!)),
              ].join(', '),
          }),
        ),
        const SizedBox(height: 28),
        AdminSection(
          title: 'Payment',
          child: payment == null
              ? const QuietText('Free screening.')
              : _Facts(
                  {
                    'Amount': NumberFormat.currency(locale: 'en_PH', symbol: '₱').format(payment.amountCentavos / 100),
                    'Status': payment.status == PaymentStatus.verified
                        ? (r.status == ReservationStatus.cancelled ? 'Paid · refund due' : 'Paid')
                        : 'Not paid yet',
                    'Method': payment.method == null ? '—' : _methodName(payment.method!),
                    'Paid at': payment.paidAt == null ? '—' : DateFormat('MMM d, y h:mm a').format(toManila(payment.paidAt!)),
                    'PayMongo': payment.paymongoPaymentId ?? payment.checkoutSessionId ?? 'Checkout not started',
                  },
                  mono: const {'PayMongo'},
                ),
        ),
        const SizedBox(height: 28),
        AdminSection(
          title: 'Emails',
          child: r.emails.isEmpty
              ? const QuietText('None sent yet.')
              : _Facts({
                  for (final e in r.emails.entries)
                    _emailName(e.key): switch (e.value) {
                      'sent' => 'Sent',
                      'failed' => 'Failed — use Resend email',
                      _ => 'Sending…',
                    },
                }),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 1000;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(child: head),
                  actions,
                ],
              )
            else ...[
              head,
              const SizedBox(height: 12),
              actions,
            ],
            const SizedBox(height: 16),
            if (refundDue) ...[
              Notice(
                'PayMongo payment ${payment?.paymongoPaymentId ?? '(ID not recorded)'}',
                title: 'Refund due.',
                tone: Tone.warning,
              ),
              const SizedBox(height: 16),
            ],
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: main),
                  const SizedBox(width: 24),
                  SizedBox(width: 360, child: side),
                ],
              )
            else ...[
              main,
              const SizedBox(height: 28),
              side,
            ],
          ],
        );
      },
    );
  }
}

String _methodName(String m) =>
    const {'card': 'Card', 'gcash': 'GCash', 'paymaya': 'Maya', 'grab_pay': 'GrabPay', 'qrph': 'QR Ph'}[m] ?? m;

String _emailName(String kind) =>
    const {'pending': 'Received', 'confirmed': 'E-ticket', 'cancelled': 'Cancellation'}[kind] ?? kind;

/// One attendee as the website lists them: seat, name, then the declared details.
class _Attendee extends StatelessWidget {
  const _Attendee({required this.seat});

  final ReservedSeat seat;

  @override
  Widget build(BuildContext context) {
    final a = seat.attendee;
    const muted = TextStyle(fontSize: 13, color: StaffColors.textMuted);
    final name = [a.firstName, a.middleName, a.lastName].whereType<String>().where((x) => x.isNotEmpty).join(' ');
    final about = [
      if (a.age != null) '${a.age} yrs',
      if (a.sex != null) a.sex == Sex.male ? 'Male' : 'Female',
      if (a.companySchool?.isNotEmpty ?? false) a.companySchool!,
    ].join(' · ');
    final contact = [a.contactNo, a.email].whereType<String>().where((x) => x.isNotEmpty).join(' · ');
    final ids = [if (a.seniorCardNo?.isNotEmpty ?? false) 'Senior ID ${a.seniorCardNo}', if (a.isPwd) 'PWD'].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 32),
            padding: const EdgeInsets.symmetric(horizontal: 5),
            decoration: BoxDecoration(
              color: StaffColors.surfaceAlt,
              border: Border.all(color: StaffColors.borderStrong),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              seat.label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, height: 20 / 12, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (seat.isBooker)
                        const TextSpan(
                          text: '  booker',
                          style: TextStyle(fontSize: 12, color: StaffColors.textMuted),
                        ),
                    ],
                  ),
                ),
                Text(about.isEmpty ? '—' : about, style: const TextStyle(fontSize: 13)),
                Text(contact.isEmpty ? 'No contact details' : contact, style: muted),
                if (ids.isNotEmpty) Text(ids, style: muted),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Label → value pairs, as the website's fact lists.
class _Facts extends StatelessWidget {
  const _Facts(this.facts, {this.mono = const {}});

  final Map<String, String> facts;
  final Set<String> mono;

  @override
  Widget build(BuildContext context) {
    return Panel(
      children: [
        for (final e in facts.entries)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 96,
                  child: Text(e.key, style: const TextStyle(fontSize: 13, color: StaffColors.textMuted)),
                ),
                Expanded(
                  child: SelectableText(
                    e.value,
                    style: mono.contains(e.key) ? staffMono.copyWith(fontSize: 12.5) : const TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
