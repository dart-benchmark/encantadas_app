import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/product.dart';
import '../models/transaction.dart';
import '../models/app_settings.dart';
import 'qr_scanner_overlay.dart';

class AddSaleForm extends StatefulWidget {
  const AddSaleForm({super.key});

  @override
  State<AddSaleForm> createState() => _AddSaleFormState();
}

class _AddSaleFormState extends State<AddSaleForm> {
  final _formKey = GlobalKey<FormState>();
  final _searchController = TextEditingController();
  final _quantityController = TextEditingController();
  final _unitPriceController = TextEditingController();
  
  Product? _selectedProduct;
  List<Product> _filteredProducts = [];
  bool _isLoading = false;
  double _total = 0.0;

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _searchController.addListener(_filterProducts);
    _quantityController.addListener(_calculateTotal);
    _unitPriceController.addListener(_calculateTotal);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _quantityController.dispose();
    _unitPriceController.dispose();
    super.dispose();
  }

  void _loadProducts() {
    final productsBox = Hive.box<Product>('products');
    final allProducts = productsBox.values.toList().cast<Product>();
    // Only show products with stock > 0
    _filteredProducts = allProducts.where((p) => p.quantity > 0).toList();
    _filteredProducts.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    setState(() {});
  }

  void _filterProducts() {
    final query = _searchController.text.toLowerCase();
    final productsBox = Hive.box<Product>('products');
    final allProducts = productsBox.values.toList().cast<Product>();
    
    if (query.isEmpty) {
      _filteredProducts = allProducts.where((p) => p.quantity > 0).toList();
    } else {
      _filteredProducts = allProducts
          .where((p) => p.quantity > 0 && p.name.toLowerCase().contains(query))
          .toList();
    }
    _filteredProducts.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    setState(() {});
  }

  void _selectProduct(Product product) {
    setState(() {
      _selectedProduct = product;
      _searchController.text = product.name;
      
      // Set default unit price - prioritize sale price over cost
      if (product.hasSalePriceInfo) {
        // Use configured sale price (either fixed price or calculated from percentage)
        _unitPriceController.text = product.calculatedSalePrice.toStringAsFixed(0);
      } else if (product.cost != null && product.cost! > 0) {
        // Fallback to cost if no sale price is configured
        _unitPriceController.text = product.cost!.toStringAsFixed(0);
      }
      
      _filteredProducts.clear();
    });
    _calculateTotal();
  }

  Future<void> _openQRScanner() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => QRScannerOverlay(
        onCodeScanned: (code) {
          Navigator.of(context).pop();
          _onQRCodeScanned(code);
        },
        onCancel: () {
          Navigator.of(context).pop();
        },
      ),
    );
  }

  void _onQRCodeScanned(String scannedCode) {
    // Buscar producto SOLO por código exacto. La heurística previa de
    // "nombre contiene código" generaba falsos positivos (vender un
    // producto por escanear el QR de otro).
    final productsBox = Hive.box<Product>('products');
    final allProducts = productsBox.values.toList().cast<Product>();
    final normalizedScan = scannedCode.trim();

    Product? foundProduct;
    for (final product in allProducts) {
      if (product.code == normalizedScan) {
        foundProduct = product;
        break;
      }
    }

    if (foundProduct != null) {
      // Verificar que tenga stock
      if (foundProduct.quantity > 0) {
        _selectProduct(foundProduct);
        
        // Verificar si el modo automático está activado
        final settings = AppSettings.instance;
        if (settings.autoQRMode) {
          // Procesar venta automáticamente
          _processAutomaticSale(foundProduct);
        } else {
          // Mostrar mensaje de éxito (modo manual)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Producto encontrado: ${foundProduct.name}'),
                  ),
                ],
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        // Producto sin stock
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.warning, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Producto "${foundProduct.name}" sin stock disponible'),
                ),
              ],
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } else {
      // Producto no encontrado
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('No se encontró un producto con el código: $scannedCode'),
              ),
            ],
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _processAutomaticSale(Product product) async {
    // Configurar valores por defecto para venta automática
    final quantity = 1; // Cantidad por defecto
    final unitPrice = product.hasSalePriceInfo 
        ? product.calculatedSalePrice 
        : (product.cost ?? 0.0);
    
    // Verificar stock suficiente
    if (quantity > product.quantity) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.warning, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Stock insuficiente para venta automática'),
              ),
            ],
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final originalQuantity = product.quantity;
    bool stockDecremented = false;

    try {
      // Actualizar stock del producto
      product.quantity -= quantity;
      await product.save();
      stockDecremented = true;

      // Crear transacción
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
        // Cerrar el formulario y mostrar confirmación
        Navigator.of(context).pop();
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.flash_auto, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Venta automática procesada: ${product.name} - \$${total.toStringAsFixed(0)}',
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.blue,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Ver detalles',
              textColor: Colors.white,
              onPressed: () {
                // Mostrar detalles de la venta
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Row(
                      children: [
                        const Icon(Icons.receipt, color: Colors.blue),
                        const SizedBox(width: 8),
                        const Text('Venta Automática'),
                      ],
                    ),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Producto: ${product.name}'),
                        Text('Cantidad: $quantity unidad${quantity > 1 ? 'es' : ''}'),
                        Text('Precio unitario: \$${unitPrice.toStringAsFixed(0)}'),
                        const Divider(),
                        Text(
                          'Total: \$${total.toStringAsFixed(0)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cerrar'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      }
    } catch (e) {
      // Rollback de stock si la creación de la transacción falló.
      if (stockDecremented) {
        try {
          product.quantity = originalQuantity;
          await product.save();
        } catch (_) {}
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Error en venta automática: $e'),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _calculateTotal() {
    final quantity = int.tryParse(_quantityController.text) ?? 0;
    final unitPrice = double.tryParse(_unitPriceController.text) ?? 0.0;
    setState(() {
      _total = quantity * unitPrice;
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedProduct = null;
      _searchController.clear();
      _quantityController.clear();
      _unitPriceController.clear();
      _total = 0.0;
    });
    _loadProducts();
  }

  Future<void> _registerSale() async {
    if (!_formKey.currentState!.validate() || _selectedProduct == null) {
      return;
    }

    final quantity = int.parse(_quantityController.text);
    final unitPrice = double.parse(_unitPriceController.text);

    // Validate stock
    if (quantity > _selectedProduct!.quantity) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Stock insuficiente. Disponible: ${_selectedProduct!.quantity} unidades',
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final originalQuantity = _selectedProduct!.quantity;
    bool stockDecremented = false;

    try {
      // Update product stock
      _selectedProduct!.quantity -= quantity;
      await _selectedProduct!.save();
      stockDecremented = true;

      // Create transaction
      final transactionsBox = Hive.box<Transaction>('transactions');
      final transaction = Transaction(
        amount: _total,
        date: DateTime.now(),
        source: 'venta',
        clientName: '', // Not used for product sales
        serviceName: '', // Not used for product sales
        productName: _selectedProduct!.name,
        productCode: _selectedProduct!.code,
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
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Venta registrada: ${_selectedProduct!.name} - \$${_total.toStringAsFixed(0)}',
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      // Rollback: si decrementamos stock pero falló crear la transacción,
      // restauramos el stock original para no dejar inconsistencia.
      if (stockDecremented) {
        try {
          _selectedProduct!.quantity = originalQuantity;
          await _selectedProduct!.save();
        } catch (_) {
          // Si el rollback también falla no hay mucho más que hacer,
          // pero al menos avisamos en el mensaje al usuario.
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al registrar venta: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    const Icon(
                      Icons.shopping_cart,
                      color: Colors.green,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Registrar Venta',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Product search
                TextFormField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    labelText: 'Buscar producto',
                    hintText: 'Escribe el nombre del producto...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _selectedProduct != null
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: _clearSelection,
                            tooltip: 'Limpiar selección',
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.qr_code_scanner),
                                onPressed: _openQRScanner,
                                tooltip: 'Escanear QR',
                              ),
                            ],
                          ),
                    border: const OutlineInputBorder(),
                  ),
                  readOnly: _selectedProduct != null,
                  validator: (value) {
                    if (_selectedProduct == null) {
                      return 'Selecciona un producto';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),

                // Product search results
                if (_filteredProducts.isNotEmpty && _selectedProduct == null)
                  Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _filteredProducts.length,
                      itemBuilder: (context, index) {
                        final product = _filteredProducts[index];
                        return ListTile(
                          title: Text(product.name),
                          subtitle: Text(
                            '${product.categoryDisplayName} • Stock: ${product.quantity}',
                          ),
                          trailing: product.cost != null
                              ? Text(
                                  product.formattedCost,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                    color: Colors.green,
                                  ),
                                )
                              : null,
                          onTap: () => _selectProduct(product),
                        );
                      },
                    ),
                  ),

                if (_selectedProduct != null) ...[
                  const SizedBox(height: 16),

                  // Selected product info
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
                        Row(
                          children: [
                            Icon(
                              Icons.inventory_2,
                              color: Colors.green,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _selectedProduct!.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Stock disponible: ${_selectedProduct!.quantity} unidades',
                          style: TextStyle(
                            color: Colors.green.shade700,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Quantity field
                  TextFormField(
                    controller: _quantityController,
                    decoration: const InputDecoration(
                      labelText: 'Cantidad a vender',
                      prefixIcon: Icon(Icons.shopping_basket),
                      border: OutlineInputBorder(),
                      suffixText: 'unidades',
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'La cantidad es obligatoria';
                      }
                      final quantity = int.tryParse(value.trim());
                      if (quantity == null || quantity <= 0) {
                        return 'Ingrese una cantidad válida (mayor a 0)';
                      }
                      if (_selectedProduct != null && quantity > _selectedProduct!.quantity) {
                        return 'Stock insuficiente (máx: ${_selectedProduct!.quantity})';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Unit price field
                  TextFormField(
                    controller: _unitPriceController,
                    decoration: const InputDecoration(
                      labelText: 'Precio unitario',
                      prefixIcon: Icon(Icons.attach_money),
                      border: OutlineInputBorder(),
                      prefixText: '\$',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                    ],
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'El precio es obligatorio';
                      }
                      final price = double.tryParse(value.trim());
                      if (price == null || price <= 0) {
                        return 'Ingrese un precio válido (mayor a 0)';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Total display
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'Total de la venta',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '\$${_total.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isLoading ? null : () {
                            Navigator.of(context).pop();
                          },
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _registerSale,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : const Text('Registrar venta'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}