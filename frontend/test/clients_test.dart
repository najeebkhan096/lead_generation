import 'package:flutter_test/flutter_test.dart';
import 'package:lead_generation_app/domain/entities/sale.dart';
import 'package:lead_generation_app/presentation/pages/sales_page.dart';

void main() {
  test('uniqueClients merges repeats, keeps a link, sorts by name', () {
    final clients = uniqueClients(const [
      Sale(id: '1', businessName: 'Zed Cafe'),
      Sale(id: '2', businessName: "Joe's  Garage", reviewLink: 'https://maps.app.goo.gl/a'),
      Sale(id: '3', businessName: 'joes garage'),
      Sale(id: '4', businessName: '  '),
    ]);
    expect(clients.map((c) => c.name), ["Joe's  Garage", 'Zed Cafe']);
    expect(clients.first.dealCount, 2);
    expect(clients.first.uri.toString(), 'https://maps.app.goo.gl/a');
    expect(clients.last.uri.host, 'www.google.com'); // no link -> Maps search
  });
}
