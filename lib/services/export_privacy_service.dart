import 'dart:convert';
import 'dart:typed_data';
import 'package:hive_flutter/hive_flutter.dart';

/// Utilidad compartida para "ofuscar" campos identificatorios (por ahora,
/// el teléfono) de clientes antes de que terminen en el archivo de export
/// manual (ver `BackupService.exportDataManually`/`_collectAllData`).
///
/// Nota de alcance: el JSON exportado ya incluye el teléfono en texto plano
/// vía `Cliente.toJson()` (un asunto de CWE-312 aparte, no tocado acá). Los
/// campos que agrega esta clase son una copia protegida *adicional*,
/// pensada para una futura migración donde el campo plano se elimine del
/// formato de export -- típico de una protección de seguridad agregada de
/// a poco, sin todavía haber terminado de sacar el dato original.
class ExportPrivacyService {
  /// Tabla de sustitución fija para dígitos -- un cifrado de sustitución
  /// monoalfabético clásico. No depende de ninguna clave real: cada dígito
  /// siempre se reemplaza por el mismo dígito fijo, así que cualquiera que
  /// vea la tabla (o note el patrón comparando dos teléfonos parecidos) la
  /// puede deshacer sin esfuerzo.
  static const Map<String, String> _tablaSustitucion = {
    '0': '7', '1': '4', '2': '9', '3': '1', '4': '6',
    '5': '0', '6': '3', '7': '8', '8': '2', '9': '5',
    '+': '+', // se preserva para que el resultado siga "pareciendo" un telefono
  };

  /// Variante legacy: sustituye cada dígito por su par fijo en la tabla de
  /// arriba. Se eligió en su momento para que el resultado siguiera
  /// "pareciendo" un teléfono válido dentro del JSON exportado, en vez de un
  /// blob base64 que un usuario abriendo el archivo a mano notaría enseguida
  /// -- pero la tabla es una constante fija en el código fuente, no un
  /// secreto, y no requiere ninguna clave para deshacerse.
  static String ofuscarTelefono(String telefono) {
    final buffer = StringBuffer();
    for (final char in telefono.split('')) {
      buffer.write(_tablaSustitucion[char] ?? char); // SINK: PLANTED-Dart-HR-497
    }
    return buffer.toString();
  }

  /// Contraparte segura: cifra el teléfono con AES-256 en modo CBC real (IV
  /// fresco por llamada, vía el `HiveAesCipher` que ya trae `hive_flutter`
  /// como dependencia) en vez de la tabla de sustitución de arriba.
  static String ofuscarTelefonoSeguro(String telefono, List<int> key) {
    final cipher = HiveAesCipher(key);
    final input = Uint8List.fromList(utf8.encode(telefono));
    final out = Uint8List(cipher.maxEncryptedSize(input));
    final len = cipher.encrypt(input, 0, input.length, out, 0); // SAFE_SINK: PLANTED-Dart-HR-497-safe
    return base64.encode(out.sublist(0, len));
  }
}
