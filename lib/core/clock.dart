/// The current time, injectable so tests can pretend it is any moment.
class Clock {
  const Clock();

  DateTime now() => DateTime.now();
}

class FixedClock extends Clock {
  const FixedClock(this.time);

  final DateTime time;

  @override
  DateTime now() => time;
}
