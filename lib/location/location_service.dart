import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Current-position lookup via the native platform channel.
/// Android: android.location.LocationManager + Geocoder (see
/// MainActivity.kt). iOS: not implemented — returns null and the
/// sheet keeps manual entry.
class LocationService {
  static const _channel =
      MethodChannel('com.case10.ransomcalendar/location');

  /// Human-readable address ("123 Main St, Toronto") or null if
  /// unavailable (no permission, no fix, no Geocoder, or iOS).
  /// Never throws — callers treat null as "keep manual entry".
  static Future<String?> getCurrentAddress() async {
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      final address = await _channel.invokeMethod<String>('getCurrentAddress');
      if (address == null || address.isEmpty) return null;
      return address;
    } on PlatformException catch (e) {
      debugPrint('Location lookup failed: ${e.code} ${e.message}');
      return null;
    } catch (e) {
      debugPrint('Location lookup failed: $e');
      return null;
    }
  }
}
