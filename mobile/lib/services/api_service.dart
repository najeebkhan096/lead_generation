import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  // Use 10.0.2.2 for Android Emulator to reach the host machine's localhost
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3001',
  );

  Future<Map<String, dynamic>> startWhatsAppAutoValidation() async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/whatsapp-web/validate-auto'),
    );
    return jsonDecode(response.body);
  }

  Future<Map<String, dynamic>> getWhatsAppValidationStatus() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/whatsapp-web/validate/status'),
    );
    return jsonDecode(response.body);
  }

  Future<Map<String, dynamic>> getWhatsAppStatus() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/whatsapp-web/status'),
    );
    return jsonDecode(response.body);
  }
}
