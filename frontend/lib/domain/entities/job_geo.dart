import 'package:equatable/equatable.dart';

import 'job_json.dart';

class JobCountry extends Equatable {
  const JobCountry({required this.code, required this.name, this.adminLabel, this.regionCount = 0, this.cityCount = 0, this.remoteOnly = false});

  factory JobCountry.fromJson(Map<String, dynamic> j) => JobCountry(
        code: jobString(j['code']) ?? '',
        name: jobString(j['name']) ?? '',
        adminLabel: jobString(j['adminLabel']),
        regionCount: jobInt(j['regionCount']) ?? 0,
        cityCount: jobInt(j['cityCount']) ?? 0,
        remoteOnly: j['remoteOnly'] == true,
      );

  final String code;
  final String name;

  /// "State", "Province", "Emirate" … — what this country calls its regions.
  final String? adminLabel;
  final int regionCount;
  final int cityCount;

  /// The Worldwide / Remote pseudo-country: no states or cities.
  final bool remoteOnly;

  String get regionNoun => adminLabel ?? 'Region';

  @override
  List<Object?> get props => [code, name, regionCount, cityCount, remoteOnly];
}

class JobRegion extends Equatable {
  const JobRegion({required this.code, required this.name, this.cityCount = 0});

  factory JobRegion.fromJson(Map<String, dynamic> j) =>
      JobRegion(code: jobString(j['code']) ?? '', name: jobString(j['name']) ?? '', cityCount: jobInt(j['cityCount']) ?? 0);

  final String code;
  final String name;
  final int cityCount;

  @override
  List<Object?> get props => [code, name, cityCount];
}

class JobCity extends Equatable {
  const JobCity({required this.name, this.population = 0});

  factory JobCity.fromJson(Map<String, dynamic> j) => JobCity(name: jobString(j['name']) ?? '', population: jobInt(j['population']) ?? 0);

  final String name;
  final int population;

  @override
  List<Object?> get props => [name, population];
}

/// The cities of one region (largest first), possibly only the first slice.
class JobCityList extends Equatable {
  const JobCityList({required this.cities, required this.total});

  final List<JobCity> cities;
  final int total;

  bool get complete => cities.length >= total;

  @override
  List<Object?> get props => [cities, total];
}
