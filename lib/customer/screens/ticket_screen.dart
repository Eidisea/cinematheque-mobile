import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/booking_view.dart';
import '../../data/models/payment.dart';
import '../../data/models/reservation.dart';
import '../customer_services.dart';
import '../theme/customer_theme.dart';
import '../widgets/brand.dart';
import '../widgets/state_views.dart';
import 'booking_screen.dart';

/// What "Find my booking" opens: the ticket on its own, with a back button — not the end
/// of the booking flow (as on the website's ticket page). A booking still waiting for
/// payment offers "Complete payment"; a pending one can be cancelled.
class TicketScreen extends StatefulWidget {
  const TicketScreen({super.key, required this.accessKey});

  final String accessKey;

  @override
  State<TicketScreen> createState() => _TicketScreenState();
}

class _TicketScreenState extends State<TicketScreen> {
  Stream<BookingView?>? _stream;
  bool _cancelling = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stream ??= CustomerServices.of(context).bookingViews.watch(widget.accessKey);
  }

  @override
  Widget build(BuildContext context) {
    final now = CustomerServices.of(context).clock.now();
    return Scaffold(
      appBar: AppBar(title: const Text('Your ticket')),
      body: StreamBuilder<BookingView?>(
        stream: _stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorView(onRetry: () => setState(() => _stream = CustomerServices.of(context).bookingViews.watch(widget.accessKey)));
          }
          if (!snapshot.hasData && snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingView(label: 'Loading your ticket…');
          }
          final booking = snapshot.data;
          if (booking == null) {
            return const MessageView(
              icon: Icons.search_off_rounded,
              title: 'Ticket not found',
              message: 'This booking could not be opened. Find it again with its booking reference.',
            );
          }
          final pending = booking.status == ReservationStatus.pending;
          final canPay = pending &&
              !booking.isFree &&
              booking.paymentStatus != PaymentStatus.verified &&
              (booking.expiresAt?.isAfter(now) ?? false);

          return ListView(
            padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, Space.xxxl),
            children: [
              ContentWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    BookingTicket(booking: booking),
                    if (canPay) ...[
                      const SizedBox(height: Space.xl),
                      GoldButton(
                        label: 'Complete payment',
                        icon: Icons.lock_outline_rounded,
                        onPressed: () => context.push('/booking/${widget.accessKey}'),
                      ),
                    ],
                    if (pending) ...[
                      const SizedBox(height: Space.md),
                      Center(
                        child: TextButton(
                          style: TextButton.styleFrom(foregroundColor: CustomerColors.danger),
                          onPressed: _cancelling
                              ? null
                              : () => confirmAndCancelBooking(context, booking, widget.accessKey, onBusy: (busy) {
                                    if (mounted) setState(() => _cancelling = busy);
                                  }),
                          child: const Text('Cancel booking'),
                        ),
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
