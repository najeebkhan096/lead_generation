import 'package:flutter_test/flutter_test.dart';
import 'package:lead_generation_app/domain/entities/maps_session_status.dart';
import 'package:lead_generation_app/domain/entities/state_city_scan_snapshot.dart';
import 'package:lead_generation_app/presentation/widgets/google_session_card.dart';

void main() {
  test('only a certainly signed-out Google session blocks a scan', () {
    MapsSessionStatus s(String status) => MapsSessionStatus(status: status);
    expect(googleSessionBlocksScan(s('signed_out')), isTrue);
    expect(googleSessionBlocksScan(s('no_profile')), isTrue);
    for (final ok in ['signed_in', 'in_use', 'login_in_progress']) {
      expect(googleSessionBlocksScan(s(ok)), isFalse, reason: ok);
    }
    // Cannot tell: the backend decides when the scan starts.
    expect(googleSessionBlocksScan(s('unknown')), isFalse);
    expect(googleSessionBlocksScan(s('error')), isFalse);
    expect(googleSessionBlocksScan(null), isFalse);
  });

  test('the session status is read from the backend payload', () {
    final s = MapsSessionStatus.fromJson({'status': 'signed_in', 'ready': true, 'loginInProgress': false, 'inUseByScan': false, 'detail': ''});
    expect(s.signedIn, isTrue);
    expect(s.ready, isTrue);
    final login = MapsSessionStatus.fromJson({'status': 'login_in_progress', 'loginInProgress': true});
    expect(login.loginInProgress, isTrue);
    expect(login.ready, isFalse);
    expect(MapsSessionStatus.fromJson({}).status, 'unknown');
  });

  test('the scan snapshot reports why it stopped and what may have been missed', () {
    final snap = StateCityScanSnapshot.fromJson({
      'active': false,
      'status': 'done',
      'stoppedReason': 'google_session_expired',
      'categories': [
        {'category': 'Car Wash', 'status': 'cancelled', 'incompleteBusinesses': 4, 'skippedListings': 2},
        {'category': 'Cafe', 'status': 'done', 'incompleteBusinesses': 1},
      ],
    });
    expect(snap.stoppedForSignIn, isTrue);
    expect(snap.needsRecheck, 7);
    expect(StateCityScanSnapshot.fromJson({'status': 'done'}).stoppedForSignIn, isFalse);
    expect(StateCityScanSnapshot.fromJson({'status': 'done'}).needsRecheck, 0);
  });
}
