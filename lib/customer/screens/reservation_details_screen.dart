import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/booking_api.dart';
import '../../core/formatting.dart';
import '../../data/models/screening.dart';
import '../customer_services.dart';
import '../storage/saved_bookings.dart';
import '../theme/customer_theme.dart';
import '../widgets/booking_steps.dart';
import '../widgets/brand.dart';
import '../widgets/state_views.dart';

/// Step 2 of booking: who is booking, and who sits in each seat. Submitting creates the
/// reservation on the server (which re-checks the seats and every field).
class ReservationDetailsScreen extends StatefulWidget {
  const ReservationDetailsScreen({super.key, required this.screeningId, required this.seats});

  final String screeningId;
  final List<String> seats;

  @override
  State<ReservationDetailsScreen> createState() => _ReservationDetailsScreenState();
}

class _PersonFields {
  final first = TextEditingController();
  final middle = TextEditingController();
  final last = TextEditingController();
  final contact = TextEditingController();
  final email = TextEditingController();
  final age = TextEditingController();
  final company = TextEditingController();
  final senior = TextEditingController();
  String? sex; // 'M' | 'F'
  bool isPwd = false;

  void dispose() {
    for (final c in [first, middle, last, contact, email, age, company, senior]) {
      c.dispose();
    }
  }
}

final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');
final _phonePattern = RegExp(r'^[0-9+()\-\s]{7,20}$');

String? _required(String? v) => (v ?? '').trim().isEmpty ? 'Required' : null;
String? _name(String? v) => _required(v) ?? ((v!.trim().length > 50) ? 'Use at most 50 characters' : null);
String? _optionalName(String? v) => (v ?? '').trim().length > 50 ? 'Use at most 50 characters' : null;
String? _phone(String? v, {bool required = false}) {
  final t = (v ?? '').trim();
  if (t.isEmpty) return required ? 'Required' : null;
  return _phonePattern.hasMatch(t) ? null : 'Enter a valid contact number';
}

String? _email(String? v, {bool required = false}) {
  final t = (v ?? '').trim();
  if (t.isEmpty) return required ? 'Required' : null;
  return _emailPattern.hasMatch(t) && t.length <= 100 ? null : 'Enter a valid email address';
}

class _ReservationDetailsScreenState extends State<ReservationDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _booker = _PersonFields();
  late final Map<String, _PersonFields> _attendees = {for (final s in widget.seats) s: _PersonFields()};
  String? _bookerSeat;
  bool _busy = false;
  List<String> _serverErrors = const [];
  Stream<Screening?>? _screening;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _screening ??= CustomerServices.of(context).catalog.watchScreening(widget.screeningId);
  }

  @override
  void dispose() {
    _booker.dispose();
    for (final a in _attendees.values) {
      a.dispose();
    }
    super.dispose();
  }

  /// "This seat is mine" copies the booker's name into that seat.
  void _setBookerSeat(String? seat) {
    setState(() => _bookerSeat = seat);
    if (seat == null) return;
    final a = _attendees[seat]!;
    a.first.text = _booker.first.text;
    a.middle.text = _booker.middle.text;
    a.last.text = _booker.last.text;
    a.contact.text = _booker.contact.text;
    a.email.text = _booker.email.text;
  }

  String? _clean(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  ReservationRequest _request() => ReservationRequest(
        screeningId: widget.screeningId,
        seats: widget.seats,
        bookerSeat: _bookerSeat,
        booker: {
          'firstName': _clean(_booker.first),
          'middleName': _clean(_booker.middle),
          'lastName': _clean(_booker.last),
          'contactNo': _clean(_booker.contact),
          'email': _clean(_booker.email),
        },
        attendees: {
          for (final e in _attendees.entries)
            e.key: {
              'firstName': _clean(e.value.first),
              'middleName': _clean(e.value.middle),
              'lastName': _clean(e.value.last),
              'age': int.tryParse(e.value.age.text.trim()),
              'sex': e.value.sex,
              'companySchool': _clean(e.value.company),
              'contactNo': _clean(e.value.contact),
              'email': _clean(e.value.email),
              'seniorCardNo': _clean(e.value.senior),
              'isPwd': e.value.isPwd,
            },
        },
      );

  Future<void> _submit(Screening screening) async {
    if (_busy) return;
    setState(() => _serverErrors = const []);
    if (!_formKey.currentState!.validate()) {
      _toast('Please check the highlighted fields.');
      return;
    }
    final services = CustomerServices.of(context);
    final api = services.bookingApi;
    if (api == null) {
      _toast('Online booking is not available right now. Please try again later.');
      return;
    }

    setState(() => _busy = true);
    final router = GoRouter.of(context);
    try {
      final created = await api.createReservation(_request());
      await services.savedBookings.save(SavedBooking(
        bookingReference: created.bookingReference,
        accessKey: created.accessKey,
        eventTitle: screening.eventTitle,
        startAt: screening.startAt,
        savedAt: services.clock.now(),
      ));
      if (!mounted) return;
      // Leave the booking flow: "Find my booking" (with the saved list) underneath, the new booking on top.
      router.go('/find');
      router.push('/booking/${created.accessKey}');
    } on ApiException catch (e) {
      if (!mounted) return;
      await _handleError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handleError(ApiException e) async {
    setState(() => _busy = false); // the answer is in — stop the spinner before explaining
    switch (e.code) {
      case 'seats_taken':
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Seats no longer available'),
            content: Text(
              '${e.seats.isEmpty ? 'Some of your seats were' : 'Seat ${e.seats.join(', ')} ${e.seats.length == 1 ? 'was' : 'were'}'} '
              'just reserved by someone else. Please choose again.',
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Choose seats'))],
          ),
        );
        if (mounted) context.pop(); // back to the live seat map
      case 'screening_started':
        _toast('This screening has already started, so booking is closed.');
      case 'screening_not_found':
        _toast('This screening is no longer available.');
      case 'validation':
        setState(() => _serverErrors = [for (final f in e.fields.entries) '${_fieldLabel(f.key)}: ${f.value}']);
      case 'network':
        // After a timeout the server may still have saved it — say so honestly.
        _toast("Couldn't reach Cinematheque. Check your connection and try again. "
            'If a booking email arrives, your seats were reserved.');
      default:
        _toast('Something went wrong. Please try again.');
    }
  }

  /// "booker.email" → "Your email", "attendees.A2.firstName" → "Seat A2 — first name".
  static String _fieldLabel(String key) {
    const names = {
      'firstName': 'first name',
      'middleName': 'middle name',
      'lastName': 'last name',
      'contactNo': 'contact number',
      'email': 'email',
      'age': 'age',
      'sex': 'sex',
      'companySchool': 'school or company',
      'seniorCardNo': 'senior citizen card no.',
      'isPwd': 'PWD',
    };
    final parts = key.split('.');
    if (parts.first == 'booker' && parts.length == 2) return 'Your ${names[parts[1]] ?? parts[1]}';
    if (parts.first == 'attendees' && parts.length == 3) return 'Seat ${parts[1]} — ${names[parts[2]] ?? parts[2]}';
    if (parts.first == 'attendees' && parts.length == 2) return 'Seat ${parts[1]}';
    return switch (key) { 'seats' => 'Seats', 'bookerSeat' => 'Your seat', _ => 'Booking' };
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Screening?>(
      stream: _screening,
      builder: (context, snapshot) {
        final screening = snapshot.data;
        final Widget body;
        if (snapshot.hasError) {
          body = ErrorView(onRetry: () => setState(() => _screening = CustomerServices.of(context).catalog.watchScreening(widget.screeningId)));
        } else if (screening == null) {
          body = snapshot.connectionState == ConnectionState.waiting
              ? const LoadingView()
              : const MessageView(icon: Icons.event_busy_outlined, title: 'Screening not found', message: 'It may have been removed.');
        } else {
          body = _form(screening);
        }
        return Scaffold(
          appBar: AppBar(title: const Text('Your details')),
          body: body,
          bottomNavigationBar: screening == null ? null : _submitBar(screening),
        );
      },
    );
  }

  Widget _form(Screening screening) {
    final seats = widget.seats;
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, Space.xxl),
        children: [
          ContentWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BookingSteps(current: 1, paid: screening.isPaid),
                const SizedBox(height: Space.xl),
                _Summary(screening: screening, seats: seats),
                if (_serverErrors.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _ErrorBox(messages: _serverErrors),
                ],
                const SizedBox(height: Space.xxl),
                const _SectionHeader(
                  title: 'Your details',
                  subtitle: 'Your booking reference and e-ticket are sent to this email.',
                ),
                ..._plain([
                  _field(_booker.first, 'First name', validator: _name, capitalize: true, autofill: AutofillHints.givenName),
                  _field(_booker.middle, 'Middle name (optional)', validator: _optionalName, capitalize: true, autofill: AutofillHints.middleName),
                  _field(_booker.last, 'Last name', validator: _name, capitalize: true, autofill: AutofillHints.familyName),
                  _field(_booker.contact, 'Contact number',
                      validator: (v) => _phone(v, required: true), keyboard: TextInputType.phone, autofill: AutofillHints.telephoneNumber),
                  _field(_booker.email, 'Email',
                      validator: (v) => _email(v, required: true), keyboard: TextInputType.emailAddress, autofill: AutofillHints.email),
                ]),
                const SizedBox(height: 16),
                DropdownButtonFormField<String?>(
                  isExpanded: true, // long options are shortened with … instead of overflowing
                  dropdownColor: CustomerColors.surface,
                  borderRadius: BorderRadius.circular(Radii.md),
                  initialValue: _bookerSeat,
                  decoration: const InputDecoration(labelText: 'Which seat is yours?'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text("I'm not attending / booking for others")),
                    for (final s in seats) DropdownMenuItem<String?>(value: s, child: Text('Seat $s is mine')),
                  ],
                  onChanged: _busy ? null : _setBookerSeat,
                ),
                const SizedBox(height: Space.xxl),
                _SectionHeader(
                  title: seats.length == 1 ? 'Who is using the seat?' : 'Who is using each seat?',
                  subtitle: 'One person per seat, as on the Cinematheque logsheet.',
                ),
                for (final seat in seats) ...[_attendeeCard(seat), const SizedBox(height: 12)],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _attendeeCard(String seat) {
    final a = _attendees[seat]!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: CustomerColors.stub,
                    border: Border.all(color: CustomerColors.perforation),
                    borderRadius: BorderRadius.circular(Radii.sm),
                  ),
                  child: Text('Seat $seat', style: CcdType.display(15, spacing: 0.6)),
                ),
                if (_bookerSeat == seat) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: CustomerColors.ink, borderRadius: BorderRadius.circular(Radii.pill)),
                    child: const Text('You', style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            _field(a.first, 'First name', validator: _name, capitalize: true),
            _field(a.middle, 'Middle name (optional)', validator: _optionalName, capitalize: true),
            _field(a.last, 'Last name', validator: _name, capitalize: true),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                title: const Text('More details (optional)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: const Text('Age, sex, school or company, contact, senior / PWD', style: TextStyle(fontSize: 12)),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _field(a.age, 'Age', keyboard: TextInputType.number, validator: (v) {
                          final t = (v ?? '').trim();
                          if (t.isEmpty) return null;
                          final n = int.tryParse(t);
                          return n == null || n < 0 || n > 120 ? '0–120' : null;
                        }),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: DropdownButtonFormField<String?>(
                            isExpanded: true,
                            dropdownColor: CustomerColors.surface,
                            borderRadius: BorderRadius.circular(Radii.md),
                            initialValue: a.sex,
                            decoration: const InputDecoration(labelText: 'Sex'),
                            items: const [
                              DropdownMenuItem(value: null, child: Text('—')),
                              DropdownMenuItem(value: 'M', child: Text('Male')),
                              DropdownMenuItem(value: 'F', child: Text('Female')),
                            ],
                            onChanged: (v) => setState(() => a.sex = v),
                          ),
                        ),
                      ),
                    ],
                  ),
                  _field(a.company, 'School or company', validator: (v) => (v ?? '').trim().length > 150 ? 'Too long' : null),
                  _field(a.contact, 'Contact number', validator: _phone, keyboard: TextInputType.phone),
                  _field(a.email, 'Email', validator: _email, keyboard: TextInputType.emailAddress),
                  _field(a.senior, 'Senior citizen card no.', validator: (v) => (v ?? '').trim().length > 30 ? 'Too long' : null),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Person with disability (PWD)'),
                    value: a.isPwd,
                    onChanged: (v) => setState(() => a.isPwd = v),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Booker fields sit directly on the page (a card around outlined fields looks doubled).
  List<Widget> _plain(List<Widget> children) => children;

  Widget _field(
    TextEditingController controller,
    String label, {
    String? Function(String?)? validator,
    TextInputType? keyboard,
    bool capitalize = false,
    String? autofill,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: TextFormField(
        controller: controller,
        enabled: !_busy,
        decoration: InputDecoration(labelText: label),
        validator: validator,
        keyboardType: keyboard,
        textCapitalization: capitalize ? TextCapitalization.words : TextCapitalization.none,
        autofillHints: autofill == null ? null : [autofill],
        textInputAction: TextInputAction.next,
        autovalidateMode: AutovalidateMode.onUserInteraction,
      ),
    );
  }

  Widget _submitBar(Screening screening) {
    final total = screening.isPaid ? (screening.priceCentavos ?? 0) * widget.seats.length : 0;
    return BottomActionBar(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${widget.seats.length} ${widget.seats.length == 1 ? 'seat' : 'seats'} · ${widget.seats.join(', ')}',
                  style: const TextStyle(color: CustomerColors.muted, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(screening.isPaid ? formatPeso(total) : 'Free', style: CcdType.money(22)),
            ],
          ),
          const SizedBox(height: Space.md),
          GoldButton(label: 'Reserve seats', busy: _busy, onPressed: () => _submit(screening)),
          if (screening.isPaid) ...[
            const SizedBox(height: 6),
            const Text(
              'After reserving, you have 15 minutes to pay online or the seats are released.',
              textAlign: TextAlign.center,
              style: TextStyle(color: CustomerColors.muted, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

/// The booking so far, as a small ticket: date stub, event, time, seats.
class _Summary extends StatelessWidget {
  const _Summary({required this.screening, required this.seats});

  final Screening screening;
  final List<String> seats;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: CustomerColors.surface,
      elevation: 2,
      shadowColor: const Color(0x40141219),
      clipBehavior: Clip.antiAlias,
      shape: const TicketBorder(notchX: 70),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 70,
              color: CustomerColors.stub,
              alignment: Alignment.center,
              child: DateStub(date: screening.startAt, dayStyleSize: 28),
            ),
            const Perforation(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(Space.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(screening.eventTitle.toUpperCase(), style: CcdType.display(18)),
                    const SizedBox(height: 4),
                    Text(formatTimeRange(screening.startAt, screening.endAt), style: CcdType.meta),
                    const SizedBox(height: Space.sm),
                    Wrap(
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
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(header: true, child: Text(title.toUpperCase(), style: CcdType.display(19, spacing: 1))),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: CustomerColors.muted, fontSize: 13, height: 1.4)),
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.messages});

  final List<String> messages;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(color: CustomerColors.dangerTint, borderRadius: BorderRadius.circular(Radii.md)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Please fix the following:', style: TextStyle(color: CustomerColors.danger, fontWeight: FontWeight.w600)),
          for (final m in messages) Text('• $m', style: const TextStyle(color: CustomerColors.danger)),
        ],
      ),
    );
  }
}
