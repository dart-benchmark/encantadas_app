import 'package:hive_flutter/hive_flutter.dart';
import '../models/product.dart';

/// Utilidades para validación de códigos de producto
class ProductCodeValidator {
  
  /// Verifica si un código de producto es único en la base de datos
  /// 
  /// [code] - El código a validar
  /// [excludeKey] - Clave del producto a excluir de la validación (útil para edición)
  /// 
  /// Retorna `true` si el código es único, `false` si ya existe
  static bool isCodeUnique(String code, {dynamic excludeKey}) {
    try {
      final box = Hive.box<Product>('products');
      
      for (var product in box.values) {
        // Si estamos editando un producto, excluirlo de la validación
        if (excludeKey != null && product.key == excludeKey) {
          continue;
        }
        
        if (product.code == code) {
          return false; // Código ya existe
        }
      }
      
      return true; // Código único
    } catch (e) {
      // En caso de error, asumir que no es único por seguridad
      // Error validating code uniqueness
      return false;
    }
  }
  
  /// Verifica si un código de producto es válido
  /// 
  /// [code] - El código a validar
  /// 
  /// Retorna `true` si el código es válido, `false` si no cumple criterios
  static bool isCodeValid(String code) {
    if (code.isEmpty) {
      return false;
    }
    
    // Verificar que no contenga caracteres no permitidos para QR
    if (code.contains('\n') || code.contains('\r') || code.contains('\t')) {
      return false;
    }
    
    // Verificar longitud mínima y máxima razonable
    if (code.length < 3 || code.length > 50) {
      return false;
    }
    
    return true;
  }
  
  /// Busca un producto por su código
  /// 
  /// [code] - El código del producto a buscar
  /// 
  /// Retorna el producto encontrado o `null` si no existe
  static Product? findProductByCode(String code) {
    try {
      final box = Hive.box<Product>('products');
      
      for (var product in box.values) {
        if (product.code == code) {
          return product;
        }
      }
      
      return null; // Producto no encontrado
    } catch (e) {
      // Error finding product by code
      return null;
    }
  }
  
  /// Valida un código para escaneo de QR
  /// 
  /// [scannedCode] - El código escaneado
  /// 
  /// Retorna un resultado de validación con información detallada
  static ProductScanResult validateScannedCode(String scannedCode) {
    // Validar formato del código
    if (!isCodeValid(scannedCode)) {
      return ProductScanResult(
        isValid: false,
        errorType: ScanErrorType.invalidFormat,
        message: 'Código QR inválido o corrupto',
      );
    }
    
    // Buscar producto
    final product = findProductByCode(scannedCode);
    if (product == null) {
      return ProductScanResult(
        isValid: false,
        errorType: ScanErrorType.productNotFound,
        message: 'Producto no encontrado',
      );
    }
    
    // Verificar stock
    if (product.quantity <= 0) {
      return ProductScanResult(
        isValid: false,
        errorType: ScanErrorType.noStock,
        message: 'Sin stock disponible',
        product: product,
      );
    }
    
    // Todo válido
    return ProductScanResult(
      isValid: true,
      product: product,
      message: 'Producto encontrado correctamente',
    );
  }
  
  /// Genera un código único basado en un prefijo
  /// 
  /// [prefix] - Prefijo para el código (ej: "P-")
  /// [attempts] - Número máximo de intentos para generar código único
  /// 
  /// Retorna un código único o lanza excepción si no se puede generar
  static String generateUniqueCode({String prefix = 'P-', int attempts = 100}) {
    
    // Buscar el siguiente número disponible
    for (int i = 1; i <= attempts; i++) {
      final code = '$prefix${i.toString().padLeft(3, '0')}';
      if (isCodeUnique(code)) {
        return code;
      }
    }
    
    // Si no se encontró un código secuencial, usar timestamp + random
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final randomSuffix = (timestamp % 10000).toString().padLeft(4, '0');
    final fallbackCode = '$prefix$randomSuffix';
    
    if (isCodeUnique(fallbackCode)) {
      return fallbackCode;
    }
    
    // Último recurso: UUID corto
    final uuid = DateTime.now().microsecondsSinceEpoch.toRadixString(36).toUpperCase();
    final shortUuid = uuid.substring(uuid.length - 8);
    return '$prefix$shortUuid';
  }
}

/// Resultado de validación de escaneo de código
class ProductScanResult {
  final bool isValid;
  final Product? product;
  final String message;
  final ScanErrorType? errorType;
  
  const ProductScanResult({
    required this.isValid,
    this.product,
    required this.message,
    this.errorType,
  });
}

/// Tipos de error en escaneo de códigos
enum ScanErrorType {
  invalidFormat,
  productNotFound,
  noStock,
  networkError,
  unknown,
}