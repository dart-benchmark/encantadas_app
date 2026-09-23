import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/product.dart';
import '../models/transaction.dart';
import '../models/app_settings.dart';

class QRProcessingDialog extends StatefulWidget {
  final String qrCode;

  const QRProcessingDialog({
    super.key,
    required this.qrCode,
  });

  @override
  State<QRProcessingDialog> createState() => _QRProcessingDialogState();
}

class _QRProcessingDialogState extends State<QRProcessingDialog> {
  bool _isProcessing = true;
  Product? _foundProduct;
  String? _error;

  @override
  void initState() {
    super.initState();
    _searchProduct();
  }

  void _searchProduct() async {
    await Future.delayed(const Duration(milliseconds: 1000)); // Simulate processing

    final productsBox = Hive.box<Product>('products');
    final allProducts = productsBox.values.toList().cast<Product>();
    final normalizedScan = widget.qrCode.trim();

    // Match SOLO por código exacto. Búsqueda por substring de nombre se
    // eliminó porque generaba ventas del producto equivocado.
    Product? foundProduct;
    for (final product in allProducts) {
      if (product.code == normalizedScan) {
        foundProduct = product;
        break;
      }
    }

    setState(() {
      _isProcessing = false;
      if (foundProduct != null) {
        if (foundProduct.quantity > 0) {
          _foundProduct = foundProduct;
        } else {
          _error = 'Producto sin stock disponible';
        }
      } else {
        _error = 'Producto no encontrado';
      }
    });

    // If product found and auto mode is enabled, process automatically
    if (_foundProduct != null) {
      final settings = AppSettings.instance;
      if (settings.autoQRMode) {
        await Future.delayed(const Duration(milliseconds: 500));
        _processAutomaticSale();
      }
    }
  }

  Future<void> _processAutomaticSale() async {
    if (_foundProduct == null) return;

    final product = _foundProduct!;
    final quantity = 1;
    final unitPrice = product.hasSalePriceInfo
        ? product.calculatedSalePrice
        : (product.cost ?? 0.0);

    final originalQuantity = product.quantity;
    bool stockDecremented = false;

    try {
      // Update product stock
      product.quantity -= quantity;
      await product.save();
      stockDecremented = true;

      // Create transaction
      final transactionsBox = Hive.box<Transaction>('transactions');
      final total = quantity * unitPrice;
      final transaction = Transaction(
        amount: total,
        date: DateTime.now(),
        source: 'venta',
        clientName: '',
        serviceName: '',
        productName: product.name,
        productCode: product.code,
        quantity: quantity,
        unitPrice: unitPrice,
      );

      await transactionsBox.add(transaction);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.qr_code_scanner, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'QR externo procesado: ${product.name} - \$${total.toStringAsFixed(0)}',
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.blue,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      // Rollback de stock si la transacción falló después del decremento.
      if (stockDecremented) {
        try {
          product.quantity = originalQuantity;
          await product.save();
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _error = 'Error al procesar venta: $e';
        });
      }
    }
  }

  Future<void> _processManualSale() async {
    if (_foundProduct == null) return;

    Navigator.of(context).pop();
    
    // Navigate to add sale form with pre-selected product
    // This would require modifying AddSaleForm to accept initial product
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Producto encontrado: ${_foundProduct!.name}. Abre "Nueva Venta" para continuar.'),
            ),
          ],
        ),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Abrir',
          textColor: Colors.white,
          onPressed: () {
            // This would trigger opening the add sale form
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.qr_code_scanner, color: Colors.blue),
          const SizedBox(width: 8),
          const Text('Procesando QR'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isProcessing) ...[
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Buscando producto: ${widget.qrCode}'),
          ] else if (_error != null) ...[
            Icon(
              Icons.error_outline,
              color: Colors.red,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Código: ${widget.qrCode}',
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ] else if (_foundProduct != null) ...[
            Icon(
              Icons.check_circle,
              color: Colors.green,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              '¡Producto encontrado!',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _foundProduct!.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text('Stock: ${_foundProduct!.quantity} unidades'),
                  if (_foundProduct!.hasSalePriceInfo)
                    Text('Precio: \$${_foundProduct!.calculatedSalePrice.toStringAsFixed(0)}')
                  else if (_foundProduct!.cost != null)
                    Text('Costo: \$${_foundProduct!.cost!.toStringAsFixed(0)}'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (AppSettings.instance.autoQRMode) ...[
              const Row(
                children: [
                  Icon(Icons.flash_auto, color: Colors.blue, size: 20),
                  SizedBox(width: 8),
                  Text('Procesando venta automáticamente...'),
                ],
              ),
            ] else ...[
              const Row(
                children: [
                  Icon(Icons.touch_app, color: Colors.orange, size: 20),
                  SizedBox(width: 8),
                  Text('¿Procesar esta venta?'),
                ],
              ),
            ],
          ],
        ],
      ),
      actions: [
        if (_error != null) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ] else if (_foundProduct != null && !AppSettings.instance.autoQRMode) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: _processManualSale,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Procesar Venta'),
          ),
        ] else if (_isProcessing) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
        ],
      ],
    );
  }
}