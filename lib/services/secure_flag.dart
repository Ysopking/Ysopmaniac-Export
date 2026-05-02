import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Stage 14: Runtime-Toggle fuer Android FLAG_SECURE.
///
/// Der native Counterpart liegt in
/// `android/app/src/main/kotlin/com/example/findux/MainActivity.kt`.
/// Beim App-Start setzt MainActivity den Flag schon nativ aus den
/// persistierten SharedPreferences (Default ON). Der hier definierte
/// MethodChannel wird nur fuer Laufzeit-Aenderungen ueber den Settings-
/// Toggle verwendet.
///
/// Auf iOS / Web / Tests existiert der Channel nicht — wir fangen die
/// MissingPluginException ab und tun nichts. FLAG_SECURE ist sowieso
/// ein Android-only Konzept.
class SecureFlag {
  static const MethodChannel _channel = MethodChannel('com.findux/security');

  static Future<void> setSecure(bool enable) async {
    try {
      await _channel.invokeMethod<bool>('setSecure', {'enable': enable});
    } on MissingPluginException {
      // Plattform unterstuetzt den Channel nicht — bewusst leise.
    } on PlatformException catch (e) {
      debugPrint('SecureFlag.setSecure failed: ${e.message}');
    } catch (e) {
      debugPrint('SecureFlag.setSecure unexpected error: $e');
    }
  }

  static Future<bool> isSecure() async {
    try {
      final result =
          await _channel.invokeMethod<bool>('isSecure');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }
}
