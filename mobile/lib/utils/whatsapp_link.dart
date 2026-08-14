/// Resolves the WhatsApp deep link for an extracted business row —
/// prefers the "WhatsApp Link" column already computed by the backend
/// (see LEAD_COLUMNS in backend/src/services/exportService.js), falling
/// back to building one from the phone number's digits when that column
/// is missing or empty. Returns null when there's no phone to link at all.
String? whatsAppUrlFor(Map<String, dynamic> row, String phone) {
  final link = (row['WhatsApp Link'] ?? '').toString().trim();
  if (link.isNotEmpty) return link;
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return null;
  return 'https://wa.me/$digits';
}
