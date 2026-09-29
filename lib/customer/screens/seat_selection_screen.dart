import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/booking_rules.dart';
import '../../core/formatting.dart';
import '../../data/models/screening.dart';
import '../../data/models/seat_layout.dart';
import '../customer_services.dart';
import '../seat_map/seat_grid.dart';
import '../seat_map/seat_map_logic.dart';
import '../theme/customer_theme.dart';
import '../widgets/booking_steps.dart';
import '../widgets/brand.dart';
import '../widgets/state_views.dart';

/// Step 1 of booking: choose up to 10 seats on the live seat map.
///
/// Seats others reserve while you are choosing turn grey immediately; if one of YOUR
/// picks is taken, it is removed and you are told. Nothing is reserved until the
/// booking is submitted (next step) — the server re-checks every seat then.
class SeatSelectionScreen extends StatefulWidget {
  const SeatSelectionScreen({super.key, required this.screeningId});

  final String screeningId;

  @override
  State<SeatSelectionScreen> createState() => _SeatSelectionScreenState();
}

class _SeatSelectionScreenState extends State<SeatSelectionScreen> {
  StreamSubscription<Screening?>? _screeningSub;
  StreamSubscription<SeatLayout?>? _layoutSub;
  Timer? _tick;

  Screening? _screening;
  SeatLayout? _layout;
  bool _screeningLoaded = false;
  bool _layoutLoaded = false;
  Object? _error;
  SeatMapState? _map;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_screeningSub == null) _subscribe();
  }

  void _subscribe() {
    final catalog = CustomerServices.of(context).catalog;
    _error = null;
    _screeningSub = catalog.watchScreening(widget.screeningId).listen((s) {
      _screeningLoaded = true;
      _screening = s;
      _rebuildMap();
    }, onError: _onError);
    _layoutSub = catalog.watchSeatLayout().listen((l) {
      _layoutLoaded = true;
      _layout = l;
      _rebuildMap();
    }, onError: _onError);
    // Unpaid holds expire and screenings start as time passes — re-check regularly.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => _rebuildMap());
  }

  void _onError(Object e) {
    if (mounted) setState(() => _error = e);
  }

  void _retry() {
    _cancel();
    setState(_subscribe);
  }

  void _cancel() {
    _screeningSub?.cancel();
    _layoutSub?.cancel();
    _tick?.cancel();
    _screeningSub = null;
  }

  void _rebuildMap() {
    if (!mounted) return;
    final screening = _screening;
    final layout = _layout;
    final now = CustomerServices.of(context).clock.now();
    if (screening == null || layout == null) {
      setState(() => _map = null);
      return;
    }
    final current = _map;
    if (current == null) {
      setState(() => _map = SeatMapState(layout: layout, screening: screening, now: now));
      return;
    }
    final (next, lost) = current.refresh(screening: screening, layout: layout, now: now);
    setState(() => _map = next);
    // Only warn while the seat map is the screen in front. Once the customer has moved on
    // to the details form, a change here is usually their OWN booking claiming the seats;
    // real conflicts are reported by the server when they submit.
    if (lost.isNotEmpty && (ModalRoute.of(context)?.isCurrent ?? true)) {
      _toast(lost.length == 1
          ? 'Seat ${lost.first} was just taken by someone else, so it was removed from your selection.'
          : 'Seats ${lost.join(', ')} were just taken by someone else, so they were removed from your selection.');
    }
  }

  void _onSeatTap(String label) {
    final map = _map;
    if (map == null) return;
    final (next, result) = map.tap(label);
    setState(() => _map = next);
    if (result == SeatTapResult.limitReached) {
      _toast('You can choose up to ${BookingRules.maxSeatsPerReservation} seats per booking.');
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
  }

  @override
  void dispose() {
    _cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final map = _map;
    final Widget body;
    if (_error != null) {
      body = ErrorView(onRetry: _retry);
    } else if (!_screeningLoaded || !_layoutLoaded) {
      body = const LoadingView(label: 'Loading seats…');
    } else if (_screening == null) {
      body = const MessageView(
        icon: Icons.event_busy_outlined,
        title: 'Screening not found',
        message: 'It may have been removed or rescheduled.',
      );
    } else if (_layout == null || _layout!.activeSeats.isEmpty) {
      body = const MessageView(
        icon: Icons.event_seat_outlined,
        title: 'Seat map not available',
        message: 'Seats for this screening cannot be chosen right now. Please try again later.',
      );
    } else {
      body = _SeatMapBody(map: map!, onSeatTap: _onSeatTap);
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Choose seats'),
            if (_screening != null)
              Text(
                '${_screening!.eventTitle} · ${formatDateShort(_screening!.startAt)}, ${formatTime(_screening!.startAt)}',
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: CustomerColors.muted),
              ),
          ],
        ),
      ),
      body: body,
      bottomNavigationBar: map == null ? null : _SelectionBar(map: map),
    );
  }
}

class _SeatMapBody extends StatelessWidget {
  const _SeatMapBody({required this.map, required this.onSeatTap});

  final SeatMapState map;
  final void Function(String) onSeatTap;

  @override
  Widget build(BuildContext context) {
    final available = map.availableCount;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.md, Space.xl),
      children: [
        ContentWidth(
          maxWidth: 560,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.sm),
                child: BookingSteps(current: 0, paid: map.screening.isPaid),
              ),
              const SizedBox(height: Space.xl),
              if (map.isClosed)
                const _Notice(icon: Icons.lock_clock_outlined, text: 'This screening has started. Booking is closed.')
              else if (available == 0 && map.selected.isEmpty)
                const _Notice(icon: Icons.event_busy_outlined, text: 'All seats have been reserved.')
              else
                Text(
                  '$available of ${map.layout.activeCount} seats available · up to ${BookingRules.maxSeatsPerReservation} per booking',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: CustomerColors.muted, fontSize: 13),
                ),
              const SizedBox(height: Space.xl),
              SeatGrid(state: map, onTap: onSeatTap),
              const SizedBox(height: Space.xl),
              const SeatLegend(),
            ],
          ),
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(color: CustomerColors.dangerTint, borderRadius: BorderRadius.circular(Radii.md)),
      child: Row(
        children: [
          Icon(icon, color: CustomerColors.danger),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(color: CustomerColors.danger))),
        ],
      ),
    );
  }
}

/// Sticky summary: which seats, how many, total, and Continue.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({required this.map});

  final SeatMapState map;

  @override
  Widget build(BuildContext context) {
    final seats = map.selectedInOrder;
    final count = seats.length;

    return BottomActionBar(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      count == 0 ? 'No seats selected' : '$count ${count == 1 ? 'seat' : 'seats'} selected',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    if (count == 0)
                      const Text('Tap a seat to select it.', style: TextStyle(color: CustomerColors.muted, fontSize: 13))
                    else
                      Semantics(
                        label: seats.join(', '),
                        excludeSemantics: true,
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            for (final s in seats)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(color: CustomerColors.goldTint, borderRadius: BorderRadius.circular(6)),
                                child: Text(s, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: Space.md),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('TOTAL', style: TextStyle(color: CustomerColors.faint, fontSize: 10.5, letterSpacing: 1.4, fontWeight: FontWeight.w600)),
                  AnimatedSwitcher(
                    duration: Motion.fast,
                    transitionBuilder: (child, a) => FadeTransition(opacity: a, child: SizeTransition(sizeFactor: a, axis: Axis.horizontal, child: child)),
                    child: Text(
                      map.screening.isPaid ? formatPeso(map.totalCentavos) : 'Free',
                      key: ValueKey(map.totalCentavos),
                      style: CcdType.money(24),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          GoldButton(
            label: 'Continue',
            icon: Icons.arrow_forward_rounded,
            onPressed: map.canContinue
                ? () => context.push('/screenings/${map.screening.id}/details', extra: map.selectedInOrder)
                : null,
          ),
        ],
      ),
    );
  }
}
