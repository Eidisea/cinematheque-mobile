import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/booking_api.dart';
import '../../core/formatting.dart';
import '../../data/models/booking_view.dart';
import '../../data/models/payment.dart';
import '../../data/models/reservation.dart';
import '../customer_services.dart';
import '../theme/customer_theme.dart';
import '../widgets/brand.dart';
import '../widgets/state_views.dart';

/// One booking, live: status, the ticket (an e-ticket once confirmed), and — while
/// pending — "Pay now" (paid screenings) and "Cancel booking". Opened with the access key
/// saved on this phone.
class BookingScreen extends StatefulWidget {
  const BookingScreen({super.key, required this.accessKey});

  final String accessKey;

  /// Opens PayMongo's payment page in an in-app browser tab. Tests replace it.
  @visibleForTesting
  static Future<bool> Function(Uri url) openUrl = (url) => launchUrl(url, mode: LaunchMode.inAppBrowserView);

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> with WidgetsBindingObserver {
  Stream<BookingView?>? _stream;
  BookingView? _latest;
  bool _cancelling = false;
  bool _paying = false;
  bool _checkedOnOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stream ??= CustomerServices.of(context).bookingViews.watch(widget.accessKey);
  }

  /// Back from the payment page (or the app reopened): ask the server to check PayMongo,
  /// in case its notification is late. The booking view then updates by itself.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshPayment();
  }

  bool _awaitsPayment(BookingView? b) =>
      b != null && !b.isFree && b.status == ReservationStatus.pending && b.paymentStatus != PaymentStatus.verified;

  Future<void> _refreshPayment() async {
    final api = CustomerServices.of(context).bookingApi;
    if (api == null || !_awaitsPayment(_latest)) return;
    try {
      await api.refreshPayment(widget.accessKey);
    } on ApiException {
      // Not fatal: the payment notification or the next check will catch up.
    }
  }

  Future<void> _pay() async {
    final api = CustomerServices.of(context).bookingApi;
    if (api == null) return _toast('Online payment is not available right now.');
    setState(() => _paying = true);
    try {
      final url = await api.startCheckout(widget.accessKey);
      if (url == null) return _toast('Payment received. Your booking is being confirmed.');
      if (!await BookingScreen.openUrl(url)) _toast('Could not open the payment page. Please try again.');
    } on ApiException catch (e) {
      _toast(switch (e.code) {
        'payment_expired' => 'The 15-minute payment window is over, so the seats are being released.',
        'not_payable' => 'This booking no longer needs payment.',
        'payments_unavailable' || 'payment_provider_error' => 'Online payment is not available right now. Please try again shortly.',
        'network' => 'No connection. Please try again.',
        _ => 'Could not open the payment page. Please try again.',
      });
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  Future<void> _cancel(BookingView booking) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this booking?'),
        content: Text(
          'Seats ${booking.seats.map((s) => s.label).join(', ')} will be released for other moviegoers. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(foregroundColor: CustomerColors.ink),
            child: const Text('Keep booking'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: CustomerColors.danger),
            child: const Text('Cancel booking'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final api = CustomerServices.of(context).bookingApi;
    if (api == null) return _toast('Cancelling is not available right now.');
    setState(() => _cancelling = true);
    try {
      await api.cancel(widget.accessKey);
      _toast('Booking cancelled. The seats were released.');
    } on ApiException catch (e) {
      _toast(switch (e.code) {
        'not_cancellable' => 'This booking can no longer be cancelled here. Please contact Cinematheque.',
        'network' => 'No connection. Please try again.',
        _ => 'Could not cancel. Please try again.',
      });
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final now = CustomerServices.of(context).clock.now();

    return Scaffold(
      appBar: AppBar(title: const Text('Booking')),
      body: StreamBuilder<BookingView?>(
        stream: _stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorView(
              onRetry: () => setState(() => _stream = CustomerServices.of(context).bookingViews.watch(widget.accessKey)),
            );
          }
          if (!snapshot.hasData && snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingView(label: 'Loading your booking…');
          }
          final booking = snapshot.data;
          if (booking == null) {
            return const MessageView(
              icon: Icons.search_off_rounded,
              title: 'Booking not found',
              message: 'This booking could not be opened. Use "Find a booking" with your booking reference and email.',
            );
          }
          _latest = booking;
          if (!_checkedOnOpen && _awaitsPayment(booking)) {
            _checkedOnOpen = true; // paid earlier but the notification never came? check once
            WidgetsBinding.instance.addPostFrameCallback((_) => _refreshPayment());
          }
          final expired = booking.expiresAt != null && !booking.expiresAt!.isAfter(now);
          final reduced = Motion.reduced(context);
          return ListView(
            padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, Space.xxxl),
            children: [
              ContentWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _StatusPanel(booking: booking, now: now),
                    const SizedBox(height: Space.xl),
                    // The ticket "prints" in when the booking's status changes (e.g. approved).
                    AnimatedSwitcher(
                      duration: reduced ? Duration.zero : Motion.slow,
                      switchInCurve: Motion.easeOut,
                      transitionBuilder: (child, a) => FadeTransition(
                        opacity: a,
                        child: SizeTransition(sizeFactor: a, alignment: Alignment.topCenter, child: child),
                      ),
                      child: _Ticket(key: ValueKey(booking.status), booking: booking),
                    ),
                    if (_awaitsPayment(booking) && !expired) ...[
                      const SizedBox(height: Space.xl),
                      GoldButton(label: 'Pay now', icon: Icons.lock_outline_rounded, busy: _paying, onPressed: _pay),
                      const SizedBox(height: Space.sm),
                      const Text(
                        'Secure payment by PayMongo · GCash, Maya or card',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12.5, color: CustomerColors.muted),
                      ),
                    ],
                    if (booking.status == ReservationStatus.pending) ...[
                      const SizedBox(height: Space.xl),
                      OutlinedButton.icon(
                        onPressed: _cancelling ? null : () => _cancel(booking),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: CustomerColors.danger,
                          side: const BorderSide(color: CustomerColors.danger),
                        ),
                        icon: _cancelling
                            ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.close_rounded),
                        label: const Text('Cancel booking'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({required this.booking, required this.now});

  final BookingView booking;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final expired = booking.expiresAt != null && !booking.expiresAt!.isAfter(now);
    final (IconData icon, Color color, Color tint, String title, String message) = switch (booking.status) {
      ReservationStatus.confirmed => (
          Icons.verified_rounded,
          CustomerColors.success,
          CustomerColors.successTint,
          'Booking confirmed',
          'Your e-ticket is below and was sent to your email. Show it at the entrance.',
        ),
      ReservationStatus.pending when booking.isFree => (
          Icons.hourglass_top_rounded,
          CustomerColors.goldText,
          CustomerColors.goldTint,
          'Reservation received',
          'Cinematheque staff will review it. Your e-ticket is emailed once it is approved.',
        ),
      ReservationStatus.pending when expired => (
          Icons.timer_off_outlined,
          CustomerColors.danger,
          CustomerColors.dangerTint,
          'Payment time is over',
          'The 15-minute payment window has ended, so these seats are being released.',
        ),
      ReservationStatus.pending => (
          Icons.payments_outlined,
          CustomerColors.goldText,
          CustomerColors.goldTint,
          'Payment needed',
          'Your seats are held until ${booking.expiresAt == null ? '—' : formatTime(booking.expiresAt!)}. '
              'Pay before then to confirm them.',
        ),
      ReservationStatus.cancelled => (
          Icons.cancel_outlined,
          CustomerColors.muted,
          CustomerColors.neutralTint,
          'Booking cancelled',
          switch (booking.cancellationReason) {
            CancellationReason.customerCancelled => 'You cancelled this booking. The seats were released.',
            CancellationReason.paymentExpired when booking.paymentStatus == PaymentStatus.verified =>
              'Your payment arrived after the 15-minute window, so the seats were released. '
                  'Cinematheque will refund it. Keep your booking reference.',
            CancellationReason.paymentExpired => 'Payment was not completed within 15 minutes, so the seats were released.',
            CancellationReason.staffCancelled =>
              'Cinematheque cancelled this booking. Refunds for paid bookings are handled directly by Cinematheque.',
            null => 'This booking was cancelled.',
          },
        ),
    };

    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(Space.lg),
        decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(Radii.lg)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(message, style: const TextStyle(height: 1.45, fontSize: 14)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The booking as a vertical ticket: details on top, a tear-off stub at the bottom.
/// Confirmed = the e-ticket (ADMIT n). Pending / cancelled use the same shape, labelled.
/// (The official FDCP paper ticket and its control number stay outside this system —
/// the booking reference is what staff use at the door.)
class _Ticket extends StatelessWidget {
  const _Ticket({super.key, required this.booking});

  final BookingView booking;

  static const _stubHeight = 104.0;

  @override
  Widget build(BuildContext context) {
    final s = booking.screening;
    final confirmed = booking.hasTicket;
    final cancelled = booking.status == ReservationStatus.cancelled;
    final ink = cancelled ? CustomerColors.faint : CustomerColors.ink;

    return LayoutBuilder(builder: (context, constraints) {
      return Material(
        color: CustomerColors.surface,
        elevation: cancelled ? 0 : 3,
        shadowColor: const Color(0x40141219),
        clipBehavior: Clip.antiAlias,
        shape: _EticketBorder(stubHeight: _stubHeight, side: cancelled ? const BorderSide(color: CustomerColors.border) : BorderSide.none),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.xl, Space.xl, Space.xl, Space.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const BrandMark(size: 22),
                      const SizedBox(width: 8),
                      Expanded(child: Eyebrow(confirmed ? 'E-ticket · Cinematheque Centre Davao' : 'Cinematheque Centre Davao', maxLines: 1)),
                    ],
                  ),
                  const SizedBox(height: Space.md),
                  Text(s.eventTitle.toUpperCase(), style: CcdType.display(26, color: ink, spacing: 0.6)),
                  const SizedBox(height: 6),
                  Text(formatDateLong(s.startAt), style: TextStyle(fontWeight: FontWeight.w600, color: ink)),
                  Text(formatTimeRange(s.startAt, s.endAt), style: CcdType.meta),
                  const SizedBox(height: Space.lg),
                  const Text('SEATS', style: TextStyle(fontSize: 10.5, letterSpacing: 1.4, fontWeight: FontWeight.w600, color: CustomerColors.faint)),
                  const SizedBox(height: 4),
                  for (final seat in booking.seats)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(children: [
                        SizedBox(width: 44, child: Text(seat.label, style: CcdType.display(16, color: ink, spacing: 0.4))),
                        Expanded(child: Text(seat.attendeeName, style: TextStyle(color: ink))),
                      ]),
                    ),
                  const SizedBox(height: Space.md),
                  Text.rich(
                    TextSpan(
                      style: const TextStyle(fontSize: 13.5, color: CustomerColors.muted),
                      children: booking.isFree
                          ? const [TextSpan(text: 'Free admission')]
                          : [
                              TextSpan(text: formatPeso(booking.totalCentavos), style: CcdType.money(15, color: ink)),
                              TextSpan(
                                  text: ' · ${booking.paymentStatus == PaymentStatus.verified ? (cancelled ? 'Refund due' : 'Paid') : 'Payment pending'}'),
                            ],
                    ),
                  ),
                ],
              ),
            ),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Perforation(horizontal: true, inset: 14)),
            Container(
              height: _stubHeight,
              color: cancelled ? CustomerColors.neutralTint : CustomerColors.stub,
              padding: const EdgeInsets.symmetric(horizontal: Space.xl),
              child: Row(
                children: [
                  // The stub has a fixed height (the side notches line up with it), so both
                  // halves shrink rather than overflow on narrow phones / large text sizes.
                  Flexible(
                    flex: 5,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            confirmed ? 'ADMIT ${booking.seats.length}' : (cancelled ? 'CANCELLED' : 'PENDING'),
                            style: CcdType.display(confirmed ? 30 : 22, color: confirmed ? CustomerColors.ink : CustomerColors.muted, spacing: 1),
                          ),
                          if (!confirmed)
                            Text(cancelled ? 'Not valid for entry' : 'Not yet valid for entry',
                                style: const TextStyle(fontSize: 12, color: CustomerColors.muted)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: Space.lg),
                  Container(width: 1, height: 52, color: CustomerColors.perforation),
                  const SizedBox(width: Space.lg),
                  Expanded(flex: 6, child: _Reference(reference: booking.bookingReference, color: ink)),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }
}

/// E-ticket outline: notches on both sides where the stub tears off.
class _EticketBorder extends TicketBorder {
  const _EticketBorder({required this.stubHeight, super.side}) : super(notchY: 0);

  final double stubHeight;

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      TicketBorder(notchY: rect.height - stubHeight - 0.75, notchRadius: 11).getOuterPath(rect);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => getOuterPath(rect.deflate(side.width));

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) return;
    canvas.drawPath(getOuterPath(rect.deflate(side.width / 2)), side.toPaint());
  }
}

class _Reference extends StatelessWidget {
  const _Reference({required this.reference, required this.color});

  final String reference;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('REFERENCE',
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: TextStyle(fontSize: 10, letterSpacing: 1.3, fontWeight: FontWeight.w600, color: CustomerColors.muted)),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: SelectableText(reference, style: CcdType.display(22, color: color, spacing: 1.2)),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Copy reference',
          icon: const Icon(Icons.copy_rounded, size: 20, color: CustomerColors.goldText),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: reference));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Booking reference copied')));
          },
        ),
      ],
    );
  }
}
