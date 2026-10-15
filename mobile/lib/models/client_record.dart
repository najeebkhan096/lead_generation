import 'package:equatable/equatable.dart';

/// A client business: its name and the link to its Google Maps listing.
/// Orders (sales) refer to it by id.
class ClientRecord extends Equatable {
  const ClientRecord({required this.id, required this.name, this.mapsUrl});

  final String id;
  final String name;

  /// Google Maps link; null for a client created before links were required
  /// and not filled in yet.
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
