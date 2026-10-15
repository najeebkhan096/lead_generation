import 'package:equatable/equatable.dart';

/// A client business: its name and the link to its Google Maps listing.
/// Sales refer to it by id. Mirrors backend/src/modules/clients.
class ClientRecord extends Equatable {
  const ClientRecord({required this.id, required this.name, this.mapsUrl});

  final String id;
  final String name;

  /// Null for a client created before links were required and not yet filled in.
  final String? mapsUrl;

  bool get hasMapsUrl => mapsUrl != null && mapsUrl!.isNotEmpty;

  factory ClientRecord.fromJson(Map<String, dynamic> json) => ClientRecord(
        id: (json['id'] as String?) ?? '',
        name: (json['businessName'] as String?) ?? '',
        mapsUrl: json['mapsUrl'] as String?,
      );

  @override
  List<Object?> get props => [id, name, mapsUrl];
}
