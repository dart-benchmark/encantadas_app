import 'package:flutter/material.dart';
import '../models/product.dart';
import '../utils/validate_product_code.dart';

/// Utilidades para el manejo de escaneo de códigos QR
/// 
/// TODO: Implementar en próxima fase cuando se agregue funcionalidad de escáner
class QRScannerHelper {
  
  /// Procesa un código QR escaneado y retorna el resultado de validación
  /// 
  /// [scannedCode] - El código obtenido del escáner QR
  /// 
  /// Retorna un [ProductScanResult] con información detallada del resultado
  static ProductScanResult processScannedCode(String scannedCode) {
    return ProductCodeValidator.validateScannedCode(scannedCode);
  }
  
  /// Procesa una venta usando un código QR escaneado
  /// 
  /// [scannedCode] - El código obtenido del escáner
  /// [quantity] - Cantidad a vender (por defecto 1)
  /// [unitPrice] - Precio unitario (opcional, usa precio base del producto)
  /// 
  /// Retorna [SaleProcessResult] con información del resultado de la venta
  static Future<SaleProcessResult> processScannerSale({
    required String scannedCode,
    int quantity = 1,
    double? unitPrice,
  }) async {
    try {
      // Validar código escaneado
      final scanResult = processScannedCode(scannedCode);
      
      if (!scanResult.isValid) {
        return SaleProcessResult(
          isSuccess: false,
          errorType: scanResult.errorType ?? ScanErrorType.unknown,
          message: scanResult.message,
        );
      }
      
      final product = scanResult.product!;
      
      // Validar cantidad solicitada
      if (quantity <= 0) {
        return SaleProcessResult(
          isSuccess: false,
          errorType: ScanErrorType.invalidFormat,
          message: 'La cantidad debe ser mayor a 0',
        );
      }
      
      if (quantity > product.quantity) {
        return SaleProcessResult(
          isSuccess: false,
          errorType: ScanErrorType.noStock,
          message: 'Stock insuficiente. Disponible: ${product.quantity}, Solicitado: $quantity',
          product: product,
        );
      }
      
      // TODO: Implementar lógica de venta real cuando se conecte con el sistema de transacciones
      // Por ahora, solo validamos sin procesar la venta
      
      return SaleProcessResult(
        isSuccess: true,
        message: 'Producto encontrado y validado correctamente',
        product: product,
        quantityToSell: quantity,
        suggestedPrice: unitPrice ?? (product.cost ?? 0.0),
      );
      
    } catch (e) {
      return SaleProcessResult(
        isSuccess: false,
        errorType: ScanErrorType.unknown,
        message: 'Error procesando código QR: $e',
      );
    }
  }
  
  /// Muestra un diálogo con el resultado del escaneo
  /// 
  /// [context] - BuildContext actual
  /// [scanResult] - Resultado del escaneo
  static void showScanResultDialog(
    BuildContext context, 
    ProductScanResult scanResult,
  ) {
    final theme = Theme.of(context);
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(
                scanResult.isValid ? Icons.check_circle : Icons.error_outline,
                color: scanResult.isValid 
                    ? theme.colorScheme.primary 
                    : theme.colorScheme.error,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  scanResult.isValid ? 'Producto encontrado' : 'Error de escaneo',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: scanResult.isValid 
                        ? theme.colorScheme.primary 
                        : theme.colorScheme.error,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (scanResult.product != null) ...[
                Text(
                  scanResult.product!.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Código: ${scanResult.product!.formattedCode}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Stock: ${scanResult.product!.quantity} unidades',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scanResult.product!.quantityStatusColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Categoría: ${scanResult.product!.categoryDisplayName}',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
              ],
              Text(
                scanResult.message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scanResult.isValid 
                      ? theme.colorScheme.onSurface 
                      : theme.colorScheme.error,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cerrar'),
            ),
            if (scanResult.isValid && scanResult.product != null) ...[
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  // TODO: Navegar a pantalla de venta con producto pre-seleccionado
                  _showNotImplementedSnackBar(context);
                },
                child: const Text('Vender'),
              ),
            ],
          ],
        );
      },
    );
  }
  
  /// Muestra un SnackBar indicando que la funcionalidad no está implementada
  static void _showNotImplementedSnackBar(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Funcionalidad de venta por QR pendiente de implementación'),
            ),
          ],
        ),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 3),
      ),
    );
  }
  
  /// Valida que no se descuente stock negativo
  /// 
  /// [product] - Producto a validar
  /// [quantityToDeduct] - Cantidad que se quiere descontar
  /// 
  /// Retorna true si la operación es válida, false si resultaría en stock negativo
  static bool canDeductQuantity(Product product, int quantityToDeduct) {
    if (quantityToDeduct <= 0) {
      return false; // No se puede descontar cantidad negativa o cero
    }
    
    return (product.quantity - quantityToDeduct) >= 0;
  }
  
  /// Descuenta stock de manera segura
  /// 
  /// [product] - Producto a actualizar
  /// [quantityToDeduct] - Cantidad a descontar
  /// 
  /// Retorna true si la operación fue exitosa, false si no se pudo realizar
  static Future<bool> safeDeductStock(Product product, int quantityToDeduct) async {
    try {
      if (!canDeductQuantity(product, quantityToDeduct)) {
        return false;
      }
      
      product.quantity -= quantityToDeduct;
      await product.save();
      return true;
    } catch (e) {
      print('Error deducting stock: $e');
      return false;
    }
  }
}

/// Resultado del procesamiento de una venta por escaneo
class SaleProcessResult {
  final bool isSuccess;
  final Product? product;
  final String message;
  final ScanErrorType? errorType;
  final int? quantityToSell;
  final double? suggestedPrice;
  
  const SaleProcessResult({
    required this.isSuccess,
    this.product,
    required this.message,
    this.errorType,
    this.quantityToSell,
    this.suggestedPrice,
  });
}