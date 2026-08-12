class SearchCountry {
  const SearchCountry(this.code, this.name, this.shortName, this.coverageLabel);

  final String code;
  final String name;

  /// Short form used in compact UI (e.g. the "{shortName} PROGRESS" stat
  /// label on the active-search page) — matches the backend's
  /// `countries.js` `shortName` so labels agree end to end.
  final String shortName;

  /// Shown in the "Coverage" banner on the New Search page.
  final String coverageLabel;
}

class SearchCountries {
  static const list = <SearchCountry>[
    SearchCountry('US', 'United States', 'USA', 'All 50 U.S. states + D.C. (automatic)'),
    SearchCountry('UK', 'United Kingdom', 'UK', 'All UK regions (automatic)'),
    SearchCountry('DE', 'Germany', 'Germany', 'All 16 German states (automatic)'),
    SearchCountry('CA', 'Canada', 'Canada', 'All Canadian provinces & territories (automatic)'),
    SearchCountry('IT', 'Italy', 'Italy', 'All 20 Italian regions (automatic)'),
    SearchCountry('FR', 'France', 'France', 'All 13 French regions (automatic)'),
    SearchCountry('AU', 'Australia', 'Australia', 'All Australian states & territories (automatic)'),
    SearchCountry('AT', 'Austria', 'Austria', 'All 9 Austrian states (automatic)'),
    SearchCountry('DK', 'Denmark', 'Denmark', 'All 5 Danish regions (automatic)'),
    SearchCountry('ES', 'Spain', 'Spain', 'All 17 Spanish autonomous communities (automatic)'),
    SearchCountry('NL', 'Netherlands', 'Netherlands', 'All 12 Dutch provinces (automatic)'),
    SearchCountry('BE', 'Belgium', 'Belgium', 'All Belgian provinces + Brussels (automatic)'),
    SearchCountry('CH', 'Switzerland', 'Switzerland', 'All 26 Swiss cantons (automatic)'),
    SearchCountry('SE', 'Sweden', 'Sweden', 'All 21 Swedish counties (automatic)'),
  ];

  static SearchCountry byCode(String code) {
    return list.firstWhere(
      (c) => c.code == code,
      orElse: () => list.first,
    );
  }
}
