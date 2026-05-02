import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';

class SecurityService {
  final LocalAuthentication auth = LocalAuthentication();
  static const String _encryptionKeyKey = 'encryptionKey';
  static const String _vaultBoxName = 'vaultBox';

  List<int>? _cachedKey;

  Future<bool> authenticate() async {
    final canCheckBiometrics = await auth.canCheckBiometrics;
    final isDeviceSupported = await auth.isDeviceSupported();
    if (!canCheckBiometrics && !isDeviceSupported) {
      return false;
    }

    try {
      return await auth.authenticate(
        localizedReason: 'Bitte verifizieren, um FindUX zu entsperren',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
    } catch (e) {
      debugPrint('SecurityService.authenticate error: $e');
      return false;
    }
  }

  Future<List<int>> getEncryptionKey() async {
    if (_cachedKey != null) return _cachedKey!;
    const secureStorage = FlutterSecureStorage();

    var containsKey = await secureStorage.containsKey(key: _encryptionKeyKey);
    if (!containsKey) {
      final key = Hive.generateSecureKey();
      await secureStorage.write(
        key: _encryptionKeyKey,
        value: base64UrlEncode(key),
      );
    }

    final keyString = await secureStorage.read(key: _encryptionKeyKey);
    if (keyString == null) {
      throw StateError('Encryption key not found in secure storage');
    }
    _cachedKey = base64Url.decode(keyString);
    return _cachedKey!;
  }

  Future<void> initSecureBox() async {
    if (Hive.isBoxOpen(_vaultBoxName)) return;
    final key = await getEncryptionKey();
    await Hive.openBox<dynamic>(
      _vaultBoxName,
      encryptionCipher: HiveAesCipher(key),
    );
  }

  Box<dynamic> get vaultBox => Hive.box<dynamic>(_vaultBoxName);

  Future<void> closeBox() async {
    if (Hive.isBoxOpen(_vaultBoxName)) {
      await Hive.box<dynamic>(_vaultBoxName).close();
    }
  }
}
