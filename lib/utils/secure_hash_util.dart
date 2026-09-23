import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Utilidades de hashing seguro para reemplazar, de a poco, los usos de
/// MD5/SHA-1/SHA-256-sin-salt en verificaciones de seguridad (PIN de
/// administrador, checksums de backup, códigos de verificación de
/// identidad, códigos de autorización gerencial, etc.) por construcciones
/// correctas.
///
/// El proyecto no depende de `bcrypt`/`argon2`/`scrypt`, así que el KDF de
/// contraseñas/PINs se implementa a mano sobre HMAC-SHA256 (PBKDF2, RFC
/// 8018) en vez de agregar una dependencia nueva solo para esto -- un
/// approach documentado y aceptado cuando ningún paquete de KDF está
/// disponible (ver `dart-cwe-328-inbrowser-planting-research.md`, §5).
class SecureHashUtil {
  SecureHashUtil._();

  static final Random _random = Random.secure();

  /// Genera `length` bytes aleatorios criptográficamente seguros, en hex
  /// (o sea, `length * 2` caracteres).
  static String randomHex(int length) {
    final bytes = List<int>.generate(length, (_) => _random.nextInt(256));
    return _hexEncode(bytes);
  }

  static List<int> _hexDecode(String hex) {
    final bytes = <int>[];
    for (var i = 0; i + 1 < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return bytes;
  }

  static String _hexEncode(List<int> bytes) {
    final buffer = StringBuffer();
    for (final b in bytes) {
      buffer.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  /// PBKDF2-HMAC-SHA256 (RFC 8018), devuelto en hex. `saltHex` debe ser
  /// distinto por instalación/registro (nunca reutilizado), e
  /// `iterations` debe ser alto -- eso es lo que hace este KDF resistente a
  /// fuerza bruta/diccionario, a diferencia de un MD5/SHA-1/SHA-256 de una
  /// sola pasada sin salt.
  static String pbkdf2HmacSha256(
    String secreto,
    String saltHex, {
    int iterations = 100000,
    int keyLengthBytes = 32,
  }) {
    final salt = _hexDecode(saltHex);
    final hmac = Hmac(sha256, utf8.encode(secreto));
    final blockCount = (keyLengthBytes / 32).ceil();
    final derived = <int>[];

    for (var blockIndex = 1; blockIndex <= blockCount; blockIndex++) {
      final blockNum = Uint8List(4);
      blockNum.buffer.asByteData().setUint32(0, blockIndex, Endian.big);

      var u = hmac.convert([...salt, ...blockNum]).bytes;
      final t = List<int>.from(u);
      for (var iter = 1; iter < iterations; iter++) {
        u = hmac.convert(u).bytes;
        for (var i = 0; i < t.length; i++) {
          t[i] ^= u[i];
        }
      }
      derived.addAll(t);
    }

    return _hexEncode(derived.sublist(0, keyLengthBytes));
  }

  /// HMAC-SHA256 con clave (`keyHex`), en hex. Para verificación de
  /// integridad/autenticidad de un payload -- a diferencia de un hash sin
  /// clave (MD5/SHA-1/SHA-256 solo), que cualquiera con acceso al payload
  /// puede recalcular sin necesitar ningún secreto.
  static String hmacSha256Hex(String payload, String keyHex) {
    final key = _hexDecode(keyHex);
    return _hexEncode(Hmac(sha256, key).convert(utf8.encode(payload)).bytes);
  }
}
