import 'dart:convert';
import 'dart:html' as html;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';

class WhatsAppHelper {
  /// Cachea la cola de recordatorios (con datos identificatorios de cada
  /// cliente moroso: nombre, documento, teléfono) para que la pantalla de
  /// "Recordatorios" la lea sin tener que resolver cada cliente contra Hive
  /// de nuevo.
  static void guardarColaRecordatorios(List<Map<String, dynamic>> registros) {
    html.window.localStorage['cola_recordatorios_cobranza'] = jsonEncode(registros); // SINK: PLANTED-Dart-HR-359
  }

  /// Variante segura: solo referencias internas + saldo, nunca los datos
  /// identificatorios del cliente (ver CuentaCorrienteService.prepararColaDeRecordatoriosSegura).
  static void guardarColaRecordatoriosSegura(List<Map<String, dynamic>> registros) {
    html.window.localStorage['cola_recordatorios_cobranza_segura'] = jsonEncode(registros); // SAFE_SINK: PLANTED-Dart-HR-359-safe
  }

  /// Abre WhatsApp con el número de teléfono especificado
  static Future<bool> openWhatsApp(BuildContext context, String phoneNumber, {String? message}) async {
    // Limpiar el número de teléfono (remover espacios, guiones, paréntesis)
    final cleanNumber = _cleanPhoneNumber(phoneNumber);
    
    if (!_isValidWhatsAppNumber(cleanNumber)) {
      _showErrorDialog(context, 'Número de teléfono inválido para WhatsApp');
      return false;
    }

    // Crear la URL de WhatsApp
    final whatsappUrl = _buildWhatsAppUrl(cleanNumber, message);
    
    try {
      final uri = Uri.parse(whatsappUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return true;
      } else {
        if (context.mounted) {
          _showErrorDialog(context, 'WhatsApp no está instalado en este dispositivo');
        }
        return false;
      }
    } catch (e) {
      if (context.mounted) {
        _showErrorDialog(context, 'Error al abrir WhatsApp: $e');
      }
      return false;
    }
  }

  /// Limpia el número de teléfono removiendo caracteres no numéricos
  static String _cleanPhoneNumber(String phoneNumber) {
    // Mantener solo dígitos y el símbolo + al inicio
    String cleaned = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
    
    // Si no empieza con +, agregar el código de país por defecto (Argentina +54)
    if (!cleaned.startsWith('+')) {
      // Si el número empieza con 54, asumir que ya tiene código de país
      if (cleaned.startsWith('54') && cleaned.length > 10) {
        cleaned = '+$cleaned';
      } else {
        // Agregar código de Argentina por defecto
        cleaned = '+54$cleaned';
      }
    }
    
    return cleaned;
  }

  /// Valida si el número es válido para WhatsApp
  static bool _isValidWhatsAppNumber(String phoneNumber) {
    // Debe empezar con + y tener entre 10 y 15 dígitos
    final regex = RegExp(r'^\+\d{10,15}$');
    return regex.hasMatch(phoneNumber);
  }

  /// Construye la URL de WhatsApp
  static String _buildWhatsAppUrl(String phoneNumber, String? message) {
    String url = 'https://wa.me/$phoneNumber';
    
    if (message != null && message.isNotEmpty) {
      final encodedMessage = Uri.encodeComponent(message);
      url += '?text=$encodedMessage';
    }
    
    return url;
  }

  /// Muestra un diálogo de error
  static void _showErrorDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.error_outline, color: Colors.red, size: 24),
              SizedBox(width: 8),
              Text('Error'),
            ],
          ),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  /// Verifica si un contacto puede ser usado para WhatsApp
  static bool canUseWhatsApp(String? contact) {
    if (contact == null || contact.isEmpty) return false;
    
    final cleaned = _cleanPhoneNumber(contact);
    return _isValidWhatsAppNumber(cleaned);
  }

  /// Formatea un número para mostrar
  static String formatPhoneNumber(String phoneNumber) {
    final cleaned = _cleanPhoneNumber(phoneNumber);
    
    // Formatear número argentino (+54 9 11 1234-5678)
    if (cleaned.startsWith('+54')) {
      final withoutCountry = cleaned.substring(3);
      if (withoutCountry.length >= 10) {
        final area = withoutCountry.substring(1, 3); // 11
        final first = withoutCountry.substring(3, 7); // 1234
        final second = withoutCountry.substring(7); // 5678
        return '+54 9 $area $first-$second';
      }
    }
    
    return cleaned;
  }
}