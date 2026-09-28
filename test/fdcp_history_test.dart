import 'package:ccd_mobile/customer/about/fdcp_history.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the About timeline against accidental edits: these facts are taken from
/// FDCP's "Our Story" (fdcp.ph/about) and must match it.
void main() {
  test('the four institutions, in order, with their founding dates and legal basis', () {
    expect(historyEras.map((e) => (e.years, e.name, e.founding.date, e.founding.basis)), [
      ('1981', 'Filipino Motion Picture Development Board', '5 January 1981', 'Executive Order No. 640-A'),
      ('1982–1985', 'Experimental Cinema of the Philippines', '29 January 1982', 'Executive Order No. 770'),
      ('1985–2002', 'Film Development Foundation of the Philippines, Inc.', '8 August 1985', 'Executive Order No. 1051'),
      ('2002–present', 'Film Development Council of the Philippines', '7 June 2002', 'Republic Act No. 9167'),
    ]);
  });

  test("the pinned strip's short names are FDCP's own abbreviations", () {
    expect(historyEras.map((e) => e.short), ['FMPDB', 'ECP', 'FDFPI', 'FDCP']);
  });

  test('milestones are dated and in chronological order', () {
    const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    DateTime parse(String d) {
      final p = d.split(' ');
      final year = int.parse(p.last);
      final month = months.indexOf(p[p.length - 2]) + 1;
      final day = p.length == 3 ? int.parse(p.first) : 1;
      expect(month, greaterThan(0), reason: d);
      return DateTime(year, month, day);
    }

    final all = [
      historyPrologue,
      for (final e in historyEras) ...[e.founding, ...e.milestones],
    ].map((e) => parse(e.date)).toList();
    for (var i = 1; i < all.length; i++) {
      expect(all[i].isAfter(all[i - 1]), isTrue, reason: 'entry $i is out of order');
    }
    expect(historyPrologue.date, '12 September 1919');
    expect(historyEras.last.milestones.map((m) => m.date).last, '7 January 2022');
  });
}
