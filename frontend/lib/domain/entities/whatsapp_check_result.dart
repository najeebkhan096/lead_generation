import 'package:equatable/equatable.dart';

/// Result of validating a phone number's format for WhatsApp.
///
/// WhatsApp does not expose registration status through any public,
/// unauthenticated endpoint, so this only confirms the number is a
/// plausible phone number and builds a wa.me deep link — opening [waLink]
/// is the only way to get a real answer from WhatsApp itself.
class WhatsAppCheckResult extends Equatable {
  const WhatsAppCheckResult({
    required this.validFormat,
    this.e164,
    this.waLink,
  });

  factory WhatsAppCheckResult.fromJson(Map<String, dynamic> json) {
    return WhatsAppCheckResult(
      validFormat: json['validFormat'] == true,
      e164: json['e164'] as String?,
      waLink: json['waLink'] as String?,
    );
  }

  final bool validFormat;
  final String? e164;
  final String? waLink;

  @override
  List<Object?> get props => [validFormat, e164, waLink];
}
