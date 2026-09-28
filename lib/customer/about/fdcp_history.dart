/// FDCP's institutional history, from the "Our Story" timeline on the official
/// FDCP website (https://fdcp.ph/about, read September 2026).
///
/// Dates, order numbers and institution names are kept exactly as FDCP gives them;
/// the explanations are paraphrased and shortened for reading on a phone. Nothing
/// here is invented — if FDCP's page changes, update this file from it.
library;

/// A dated event: the founding of an institution or a later milestone.
class HistoryEvent {
  const HistoryEvent({required this.date, required this.title, this.basis, required this.text});

  /// As FDCP dates it — some entries only have a month.
  final String date;
  final String title;

  /// The legal instrument behind it, e.g. "Executive Order No. 640-A".
  final String? basis;
  final String text;
}

/// One of the four institutions, in order.
class HistoryEra {
  const HistoryEra({
    required this.years,
    required this.name,
    required this.short,
    required this.context,
    required this.founding,
    this.milestones = const [],
  });

  final String years; // "1982–1985"
  final String name;
  final String short; // FDCP's own abbreviation, e.g. "ECP"
  final String context; // where it sat, as FDCP describes it
  final HistoryEvent founding;
  final List<HistoryEvent> milestones;
}

/// Where Philippine cinema itself begins (named in FDCP's 2018 entry).
const historyPrologue = HistoryEvent(
  date: '12 September 1919',
  title: 'Dalagang Bukid',
  text: 'Jose Nepomuceno\'s Dalagang Bukid premieres — the first feature film directed and produced by a Filipino. '
      'Its premiere date is marked as the birth of Philippine cinema.',
);

const historyEras = [
  HistoryEra(
    years: '1981',
    name: 'Filipino Motion Picture Development Board',
    short: 'FMPDB',
    context: 'An arm of the Cultural Center of the Philippines',
    founding: HistoryEvent(
      date: '5 January 1981',
      title: 'Filipino Motion Picture Development Board',
      basis: 'Executive Order No. 640-A',
      text: 'Set up to operate the Film Academy of the Philippines and to honour those who advanced the motion '
          'picture arts and sciences. The same order created a Film Fund to support productions, a Board of '
          'Standards for film rating and classification, and a Film Archive for films of historical, cultural or '
          'aesthetic value. The Board later became defunct.',
    ),
  ),
  HistoryEra(
    years: '1982–1985',
    name: 'Experimental Cinema of the Philippines',
    short: 'ECP',
    context: 'Affiliated with the Ministry of Tourism',
    founding: HistoryEvent(
      date: '29 January 1982',
      title: 'Experimental Cinema of the Philippines',
      basis: 'Executive Order No. 770',
      text: 'Created to promote the growth of the local film industry. Known mainly as a production company, it '
          'was also tasked to lead the Manila International Film Festival, manage the Manila Film Center, run film '
          'rating and classification, establish the National Film Archive and support selected films through a '
          'film fund.',
    ),
    milestones: [
      HistoryEvent(
        date: '12 June 1982',
        title: 'Film Ratings Board',
        basis: 'Executive Order No. 811',
        text: 'Created to raise the quality of Filipino films through a national rating and classification system.',
      ),
    ],
  ),
  HistoryEra(
    years: '1985–2002',
    name: 'Film Development Foundation of the Philippines, Inc.',
    short: 'FDFPI',
    context: 'A non-stock, non-profit corporation',
    founding: HistoryEvent(
      date: '8 August 1985',
      title: 'Film Development Foundation of the Philippines, Inc.',
      basis: 'Executive Order No. 1051',
      text: 'Established to continue the work of the defunct Experimental Cinema of the Philippines: developing '
          'the local film industry, administering film rating and classification, managing the National Film '
          'Archive and supporting selected films through a film fund.',
    ),
    milestones: [
      HistoryEvent(
        date: '2 October 1985',
        title: 'The Foundation begins its work',
        text: 'It became functional after registering with the Securities and Exchange Commission.',
      ),
    ],
  ),
  HistoryEra(
    years: '2002–present',
    name: 'Film Development Council of the Philippines',
    short: 'FDCP',
    context: 'Under the Office of the President',
    founding: HistoryEvent(
      date: '7 June 2002',
      title: 'Film Development Council of the Philippines',
      basis: 'Republic Act No. 9167',
      text: 'Created to replace the Film Development Foundation. The Cinema Evaluation Board replaced the Film '
          'Ratings Board, grading films submitted to FDCP under the Cinema Evaluation System.',
    ),
    milestones: [
      HistoryEvent(
        date: '10 March 2006',
        title: 'Oversight delegated to Education',
        basis: 'Executive Order No. 513',
        text: 'The President\'s oversight of the Film Academy of the Philippines and FDCP is delegated to the '
            'Secretary of Education.',
      ),
      HistoryEvent(
        date: '30 October 2007',
        title: 'Philippine Film Export Services Office',
        basis: 'Executive Order No. 674',
        text: 'Set up under FDCP\'s supervision to promote the country as a location for international film and '
            'television productions.',
      ),
      HistoryEvent(
        date: '15 June 2009',
        title: 'Foreign Affairs joins the export office',
        basis: 'Executive Order No. 674-A',
        text: 'The Department of Foreign Affairs becomes a member of the Philippine Film Export Services Office.',
      ),
      HistoryEvent(
        date: '20 October 2009',
        title: 'Under the Department of Education',
        basis: 'Executive Order No. 837',
        text: 'FDCP is placed under the oversight of the Department of Education.',
      ),
      HistoryEvent(
        date: 'January 2011',
        title: 'Philippine Film Archive',
        text: 'FDCP establishes the Philippine Film Archive, formerly the National Film Archive of the Philippines, '
            'to preserve, restore and safeguard Filipino films. It launched on 27 October 2011, the World Day for '
            'Audiovisual Heritage.',
      ),
      HistoryEvent(
        date: '17 April 2012',
        title: 'Films deposited with the archive',
        basis: 'Administrative Order No. 26',
        text: 'Government offices are directed to turn over their films and other audio-visual materials to the '
            'national film archive for care and preservation.',
      ),
      HistoryEvent(
        date: '8 November 2018',
        title: 'Centennial of Philippine Cinema',
        basis: 'Proclamation No. 622',
        text: '12 September 2019 to 11 September 2020 is declared the Centennial Year of Philippine Cinema, with FDCP '
            'as the lead agency.',
      ),
      HistoryEvent(
        date: '3 February 2021',
        title: 'Philippine Film Industry Month',
        basis: 'Proclamation No. 1085',
        text: 'September is declared Philippine Film Industry Month, with FDCP leading its observance.',
      ),
      HistoryEvent(
        date: '7 January 2022',
        title: 'Under Trade and Industry',
        basis: 'Executive Order No. 161',
        text: 'Oversight of FDCP moves from the Department of Education to the Department of Trade and Industry.',
      ),
    ],
  ),
];
