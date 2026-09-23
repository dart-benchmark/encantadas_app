import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// Utilidad para capturar y descargar códigos QR como imágenes PNG
class QRDownloadHelper {
  
  /// Captura un widget y lo convierte en imagen PNG
  /// 
  /// [key] - GlobalKey del RepaintBoundary que contiene el widget
  /// [pixelRatio] - Relación de píxeles para la calidad de imagen (por defecto 3.0)
  /// 
  /// Retorna los bytes de la imagen PNG o null si hay error
  static Future<Uint8List?> captureWidgetAsImage(
    GlobalKey key, {
    double pixelRatio = 3.0,
  }) async {
    try {
      // Obtener el RenderRepaintBoundary del widget
      RenderRepaintBoundary? boundary = 
          key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      
      if (boundary == null) {
        print('Error: No se pudo encontrar el boundary para capturar');
        return null;
      }
      
      // Capturar la imagen
      ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
      
      // Convertir a bytes PNG
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      
      if (byteData == null) {
        print('Error: No se pudo convertir la imagen a bytes');
        return null;
      }
      
      return byteData.buffer.asUint8List();
    } catch (e) {
      print('Error capturando widget como imagen: $e');
      return null;
    }
  }
  
  /// Solicita permisos de almacenamiento necesarios
  /// 
  /// Retorna true si se otorgaron los permisos, false en caso contrario
  static Future<bool> requestStoragePermissions() async {
    try {
      if (Platform.isAndroid) {
        // Android 13+ usa permisos granulares
        var status = await Permission.photos.status;
        if (status.isDenied) {
          status = await Permission.photos.request();
        }
        
        // Fallback para versiones anteriores de Android
        if (status.isPermanentlyDenied || status.isDenied) {
          var storageStatus = await Permission.storage.status;
          if (storageStatus.isDenied) {
            storageStatus = await Permission.storage.request();
          }
          return storageStatus.isGranted;
        }
        
        return status.isGranted;
      } else if (Platform.isIOS) {
        var status = await Permission.photos.status;
        if (status.isDenied) {
          status = await Permission.photos.request();
        }
        return status.isGranted;
      } else {
        // Para Windows y otras plataformas, asumir que no necesita permisos
        return true;
      }
    } catch (e) {
      print('Error solicitando permisos de almacenamiento: $e');
      return false;
    }
  }
  
  /// Obtiene el directorio de descargas del dispositivo
  /// 
  /// Retorna el directorio de descargas o null si no se puede acceder
  static Future<Directory?> getDownloadsDirectory() async {
    try {
      if (Platform.isAndroid) {
        // En Android, usar el directorio de descargas público
        return Directory('/storage/emulated/0/Download');
      } else if (Platform.isIOS) {
        // En iOS, usar el directorio de documentos de la app
        return await getApplicationDocumentsDirectory();
      } else if (Platform.isWindows) {
        // En Windows, usar la carpeta de descargas del usuario
        final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
        if (home != null) {
          final downloadsDir = Directory('$home\\Downloads');
          if (await downloadsDir.exists()) {
            return downloadsDir;
          }
        }
        // Fallback al directorio de documentos de la aplicación
        return await getApplicationDocumentsDirectory();
      } else {
        // Para otras plataformas, usar directorio de documentos
        return await getApplicationDocumentsDirectory();
      }
    } catch (e) {
      print('Error obteniendo directorio de descargas: $e');
      return null;
    }
  }
  
  /// Guarda los bytes de imagen como archivo PNG
  /// 
  /// [imageBytes] - Bytes de la imagen PNG
  /// [fileName] - Nombre del archivo (sin extensión)
  /// [showInGallery] - Si mostrar en galería (solo Android)
  /// 
  /// Retorna el path del archivo guardado o null si hay error
  static Future<String?> saveImageToFile(
    Uint8List imageBytes,
    String fileName, {
    bool showInGallery = true,
  }) async {
    try {
      // Solicitar permisos
      bool hasPermission = await requestStoragePermissions();
      if (!hasPermission) {
        print('Error: No se otorgaron permisos de almacenamiento');
        return null;
      }
      
      // Obtener directorio de descargas
      Directory? downloadsDir = await getDownloadsDirectory();
      if (downloadsDir == null) {
        print('Error: No se pudo acceder al directorio de descargas');
        return null;
      }
      
      // Asegurar que el directorio existe
      if (!await downloadsDir.exists()) {
        try {
          await downloadsDir.create(recursive: true);
        } catch (e) {
          print('Error creando directorio de descargas: $e');
          return null;
        }
      }
      
      // Crear nombre de archivo seguro
      final safeFileName = _sanitizeFileName(fileName);
      final fullFileName = '${safeFileName}.png';
      
      // Crear path completo del archivo
      final filePath = '${downloadsDir.path}${Platform.pathSeparator}$fullFileName';
      
      // Verificar si el archivo ya existe y crear nombre único si es necesario
      String finalPath = filePath;
      int counter = 1;
      while (await File(finalPath).exists()) {
        final nameWithCounter = '${safeFileName}_$counter.png';
        finalPath = '${downloadsDir.path}${Platform.pathSeparator}$nameWithCounter';
        counter++;
      }
      
      // Guardar archivo
      final finalFile = File(finalPath);
      await finalFile.writeAsBytes(imageBytes);
      
      print('Imagen QR guardada en: $finalPath');
      return finalPath;
    } catch (e) {
      print('Error guardando imagen: $e');
      return null;
    }
  }
  
  /// Descarga completa del código QR (captura + guardado)
  /// 
  /// [key] - GlobalKey del RepaintBoundary
  /// [productCode] - Código del producto para el nombre del archivo
  /// [pixelRatio] - Calidad de imagen
  /// 
  /// Retorna QRDownloadResult con información del resultado
  static Future<QRDownloadResult> downloadQRCode(
    GlobalKey key,
    String productCode, {
    double pixelRatio = 3.0,
  }) async {
    try {
      // Capturar imagen
      final imageBytes = await captureWidgetAsImage(key, pixelRatio: pixelRatio);
      if (imageBytes == null) {
        return QRDownloadResult(
          success: false,
          error: 'No se pudo capturar la imagen del código QR',
          errorType: QRDownloadErrorType.captureError,
        );
      }
      
      // Guardar archivo
      final fileName = 'QR_$productCode';
      final filePath = await saveImageToFile(imageBytes, fileName);
      
      if (filePath == null) {
        return QRDownloadResult(
          success: false,
          error: 'No se pudo guardar la imagen en el dispositivo',
          errorType: QRDownloadErrorType.saveError,
        );
      }
      
      return QRDownloadResult(
        success: true,
        filePath: filePath,
        fileName: fileName,
        message: 'Código QR descargado correctamente',
      );
    } catch (e) {
      return QRDownloadResult(
        success: false,
        error: 'Error inesperado durante la descarga: $e',
        errorType: QRDownloadErrorType.unknown,
      );
    }
  }
  
  /// Sanitiza el nombre del archivo removiendo caracteres no válidos
  /// 
  /// [fileName] - Nombre original del archivo
  /// 
  /// Retorna nombre sanitizado
  static String _sanitizeFileName(String fileName) {
    // Remover caracteres no válidos para nombres de archivo
    String sanitized = fileName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    
    // Limitar longitud
    if (sanitized.length > 50) {
      sanitized = sanitized.substring(0, 50);
    }
    
    // Asegurar que no esté vacío
    if (sanitized.trim().isEmpty) {
      sanitized = 'QR_Code';
    }
    
    return sanitized.trim();
  }
  
  /// Abre la configuración de permisos de la aplicación
  static Future<void> openAppSettingsHelper() async {
    try {
      await openAppSettings();
    } catch (e) {
      print('Error abriendo configuración de la app: $e');
    }
  }
}

/// Resultado de la operación de descarga de QR
class QRDownloadResult {
  final bool success;
  final String? filePath;
  final String? fileName;
  final String? message;
  final String? error;
  final QRDownloadErrorType? errorType;
  
  const QRDownloadResult({
    required this.success,
    this.filePath,
    this.fileName,
    this.message,
    this.error,
    this.errorType,
  });
}

/// Tipos de error en descarga de QR
enum QRDownloadErrorType {
  captureError,
  permissionDenied,
  saveError,
  unknown,
}