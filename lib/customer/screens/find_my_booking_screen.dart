import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/booking_api.dart';
import '../../core/formatting.dart';
import '../customer_services.dart';
import '../storage/saved_bookings.dart';
import '../theme/customer_theme.dart';
import '../widgets/brand.dart';
import '../widgets/motion.dart';
import '../widgets/page_header.dart';
import '../widgets/state_views.dart';

/// "Find my booking" tab. Customers have no accounts, so a booking is opened with its
/// reference AND the booker's email. Bookings made or found on this phone are listed
/// underneath so they can be reopened without typing anything, followed by how booking
/// works (people come here exactly when they wonder what happens next).
class FindMyBookingScreen extends StatefulWidget {
  const FindMyBookingScreen({super.key});

  @override
  State<FindMyBookingScreen> createState() => _FindMyBookingScreenState();
}

class _FindMyBookingScreenState extends State<FindMyBookingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _reference = TextEditingController();
  final _email = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reference.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _find() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final services = CustomerServices.of(context);
    final api = services.bookingApi;
    if (api == null) {
      setState(() => _error = 'Finding bookings is not available right now. Please try again later.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final router = GoRouter.of(context);
    try {
      final key = await api.lookup(bookingReference: _reference.text, email: _email.text);
      final view = await services.bookingViews.get(key);
      if (view != null) {
        await services.savedBookings.save(
          SavedBooking(
            bookingReference: view.bookingReference,
            accessKey: key,
            eventTitle: view.screening.eventTitle,
            startAt: view.screening.startAt,
            savedAt: services.clock.now(),
          ),
        );
      }
      if (!mounted) return;
      _reference.clear();
      _email.clear();
      router.push('/booking/$key');
    } on ApiException catch (e) {
      setState(
        () => _error = switch (e.code) {
          'not_found' => 'No booking matches that reference and email. Check both and try again.',
          'network' => 'No connection. Check your internet and try again.',
          _ => 'Something went wrong. Please try again.',
        },
      );
    } catch (_) {
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = CustomerServices.of(context);
    final store = services.savedBookings;
    final now = services.clock.now();

    return Scaffold(
      body: Stack(
        children: [
          ListView(
            padding: EdgeInsets.zero,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              const ContentWidth(
                child: PageHeader(
                  eyebrow: 'No account needed',
                  title: 'Find my booking',
                  lead:
                      'Enter the booking reference from your email (it looks like CCD-7KQ2M9XA) '
                      'and the email address used for the booking.',
                ),
              ),
              ContentWidth(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_error != null) ...[
                          Container(
                            padding: const EdgeInsets.all(Space.md),
                            decoration: BoxDecoration(
                              color: CustomerColors.dangerTint,
                              borderRadius: BorderRadius.circular(Radii.md),
                            ),
                            child: Text(_error!, style: const TextStyle(color: CustomerColors.danger)),
                          ),
                          const SizedBox(height: 16),
                        ],
                        // The lookup is a ticket: reference on the stub, email below the tear —
                        // "open your ticket", not "sign in".
                        _TicketLookup(
                          top: TextFormField(
                            controller: _reference,
                            enabled: !_busy,
                            style: CcdType.display(TypeScale.s, spacing: 1.2),
                            decoration: _ticketField('Booking reference', hint: 'CCD-XXXXXXXX'),
                            textCapitalization: TextCapitalization.characters,
                            textInputAction: TextInputAction.next,
                            validator: (v) => (v ?? '').trim().length < 8 ? 'Enter your booking reference' : null,
                          ),
                          bottom: TextFormField(
                            controller: _email,
                            enabled: !_busy,
                            decoration: _ticketField('Email used for the booking'),
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _find(),
                            validator: (v) => (v ?? '').contains('@') ? null : 'Enter your email address',
                          ),
                        ),
                        const SizedBox(height: 24),
                        GoldButton(label: 'Find booking', busy: _busy, onPressed: _find),
                      ],
                    ),
                  ),
                ),
              ),
              ListenableBuilder(
                listenable: store,
                builder: (context, _) => _SavedBookings(store: store, now: now),
              ),
              const ContentWidth(child: _HowBookingWorks()),
            ],
          ),
          const StatusBarScrim(),
        ],
      ),
    );
  }
}

/// A field set directly on the ticket: no box of its own — the ticket is the frame.
InputDecoration _ticketField(String label, {String? hint}) => InputDecoration(
      labelText: label,
      hintText: hint,
      filled: false,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      focusedErrorBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
      contentPadding: const EdgeInsets.symmetric(vertical: Space.sm),
    );

/// Two fields on one white ticket, split by a tear line with a notch bitten out of
/// each edge (the same ticket language as the screenings and the e-ticket).
class _TicketLookup extends StatelessWidget {
  const _TicketLookup({required this.top, required this.bottom});

  final Widget top;
  final Widget bottom;

  static const _notch = 9.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: CustomerColors.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: CustomerColors.border),
        boxShadow: const [BoxShadow(color: Color(0x14141219), blurRadius: 18, offset: Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.sm), child: top),
          SizedBox(
            height: _notch * 2,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const Positioned.fill(child: Center(child: Perforation(horizontal: true, inset: 18))),
                for (final left in const [true, false])
                  Positioned(
                    left: left ? -_notch : null,
                    right: left ? null : -_notch,
                    top: 0,
                    child: Container(
                      width: _notch * 2,
                      height: _notch * 2,
                      decoration: BoxDecoration(
                        color: CustomerColors.background,
                        shape: BoxShape.circle,
                        border: Border.all(color: CustomerColors.border),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.md), child: bottom),
        ],
      ),
    );
  }
}

/// Bookings made or found on THIS phone (stored locally; nothing is sent anywhere).
class _SavedBookings extends StatelessWidget {
  const _SavedBookings({required this.store, required this.now});

  final SavedBookingsStore store;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final bookings = store.bookings;
    final upcoming = bookings.where((b) => b.startAt.isAfter(now)).toList()..sort((a, b) => a.startAt.compareTo(b.startAt));
    final past = bookings.where((b) => !b.startAt.isAfter(now)).toList();

    return ContentWidth(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xxl, Space.gutter, Space.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeading('On this phone', size: 20),
            const SizedBox(height: Space.md),
            if (bookings.isEmpty)
              const Text(
                'Bookings you make or find on this phone appear here, so you can open them again without typing.',
                style: TextStyle(color: CustomerColors.muted, height: 1.5),
              )
            else ...[
              if (upcoming.isNotEmpty) ...[
                const _GroupTitle('Upcoming'),
                for (final (i, b) in upcoming.indexed)
                  Entrance(
                    index: i,
                    child: _BookingTile(booking: b, store: store),
                  ),
              ],
              if (past.isNotEmpty) ...[
                const _GroupTitle('Past'),
                for (final b in past) _BookingTile(booking: b, store: store, past: true),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, Space.md, 2, Space.md),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(fontSize: 11.5, letterSpacing: 1.6, fontWeight: FontWeight.w700, color: CustomerColors.faint),
    ),
  );
}

class _BookingTile extends StatelessWidget {
  const _BookingTile({required this.booking, required this.store, this.past = false});

  final SavedBooking booking;
  final SavedBookingsStore store;
  final bool past;

  static const _stub = 66.0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Material(
        color: CustomerColors.surface,
        elevation: past ? 0 : 2,
        shadowColor: const Color(0x40141219),
        clipBehavior: Clip.antiAlias,
        shape: TicketBorder(
          notchX: _stub,
          notchRadius: 8,
          side: past ? const BorderSide(color: CustomerColors.border) : BorderSide.none,
        ),
        child: InkWell(
          onTap: () => context.push('/booking/${booking.accessKey}'),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: _stub,
                  color: past ? CustomerColors.neutralTint : CustomerColors.stub,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: Space.md),
                  child: DateStub(date: booking.startAt, dayStyleSize: 26, muted: past),
                ),
                const Perforation(inset: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, 0, Space.md),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          booking.eventTitle.toUpperCase(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: CcdType.display(17, color: past ? CustomerColors.muted : CustomerColors.ink, spacing: 0.3),
                        ),
                        const SizedBox(height: 2),
                        Text(formatTime(booking.startAt), style: CcdType.meta),
                        Text(
                          booking.bookingReference,
                          style: const TextStyle(
                            fontSize: 12,
                            letterSpacing: 0.8,
                            fontWeight: FontWeight.w600,
                            color: CustomerColors.goldText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Booking options',
                  icon: const Icon(Icons.more_vert_rounded, color: CustomerColors.muted),
                  onSelected: (_) async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Remove from this phone?'),
                        content: const Text(
                          'This only removes it from this list. The booking itself is not cancelled — '
                          'you can find it again with its reference and your email.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            style: TextButton.styleFrom(foregroundColor: CustomerColors.ink),
                            child: const Text('Keep'),
                          ),
                          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
                        ],
                      ),
                    );
                    if (ok == true) await store.remove(booking.bookingReference);
                  },
                  itemBuilder: (context) => const [PopupMenuItem(value: 'remove', child: Text('Remove from this phone'))],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// How booking and admission work — following the system's actual rules.
class _HowBookingWorks extends StatelessWidget {
  const _HowBookingWorks();

  static const _steps = [
    ('Choose your seats', 'Pick a screening and up to 10 seats. You will enter the name of the person using each seat.'),
    ('No account needed', 'You only need an email address. Your booking reference and e-ticket are sent there.'),
    (
      'Paid screenings',
      'Pay online through PayMongo within 15 minutes, or the seats are released. Your e-ticket is sent once the payment is confirmed.',
    ),
    ('Free screenings', 'Your reservation is reviewed by Cinematheque staff. Your e-ticket is sent once it is approved.'),
    ('At the cinema', 'Show your booking reference or e-ticket at the entrance. Staff confirm your admission there.'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.xxxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeading('How booking works', size: 20),
          const SizedBox(height: Space.lg),
          for (final (i, step) in _steps.indexed)
            _Step(number: i + 1, title: step.$1, body: step.$2, last: i == _steps.length - 1),
        ],
      ),
    );
  }
}

/// A numbered step with a thin gold line joining it to the next one.
class _Step extends StatelessWidget {
  const _Step({required this.number, required this.title, required this.body, required this.last});

  final int number;
  final String title;
  final String body;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 40,
            child: Column(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: CustomerColors.stub,
                    shape: BoxShape.circle,
                    border: Border.all(color: CustomerColors.perforation),
                  ),
                  child: Text('$number', style: CcdType.display(17, color: CustomerColors.goldText, spacing: 0)),
                ),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 1.5,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: CustomerColors.perforation,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 6, bottom: last ? 0 : Space.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
                  const SizedBox(height: 4),
                  Text(body, style: const TextStyle(color: CustomerColors.muted, height: 1.5, fontSize: 14)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
