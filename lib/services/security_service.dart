import 'package:local_auth/local_auth.dart';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';

class SecurityService {
  final LocalAuthentication auth = LocalAuthentication();
  static const String _encryptionKeyKey = 'encryptionKey';
  static const String _vaultBoxName = 'vaultBox';

  Future<bool> authenticate() async {
    bool canCheckBiometrics = await auth.canCheckBiometrics;
    if (!canCheckBiometrics) return false;

    try {
      return await auth.authenticate(
        localizedReason: 'Bitte verifizieren, um FindUX zu entsperren',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false, // Erlaubt PIN-Fallback für iPhone 6
        ),
      );
    } catch (e) {
      return false;
    }
  }

  Future<void> initSecureBox() async {
    const secureStorage = FlutterSecureStorage();

    // Schlüssel prüfen oder neu erstellen
    var containsEncryptionKey = await secureStorage.containsKey(key: _encryptionKeyKey);
    if (!containsEncryptionKey) {
      var key = Hive.generateSecureKey();
      await secureStorage.write(key: _encryptionKeyKey, value: base64UrlEncode(key));
    }

    // Schlüssel auslesen und Box verschlüsselt öffnen
    var keyString = await secureStorage.read(key: _encryptionKeyKey);
    var key = base64Url.decode(keyString!);
    await Hive.openBox(_vaultBoxName, encryptionCipher: HiveAesCipher(key));
  }

  Box get vaultBox => Hive.box(_vaultBoxName);

  Future<void> closeBox() async {
    if (Hive.isBoxOpen(_vaultBoxName)) {
      await Hive.box(_vaultBoxName).close();
    }
  }
}
