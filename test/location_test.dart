import 'package:flutter_test/flutter_test.dart';
import 'package:ransom_calendar/location/location_service.dart';

void main() {
  test('getCurrentAddress returns null off Android (no crash)', () async {
    // Tests run on the host platform, not Android — the service must
    // return null gracefully instead of throwing or hanging.
    final address = await LocationService.getCurrentAddress();
    expect(address, isNull);
  });
}
