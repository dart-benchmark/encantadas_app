import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/product.dart';
import '../models/provider.dart';
import '../utils/validate_product_code.dart';
import 'tags_input.dart';
import 'product_image_picker.dart';

class EditProductForm extends StatefulWidget {
  final Product product;

  const EditProductForm({
    super.key,
    required this.product,
  });

  @override
  State<EditProductForm> createState() => _EditProductFormState();
}

class _EditProductFormState extends State<EditProductForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _quantityController = TextEditingController();
  final _codeController = TextEditingController();
  final _costController = TextEditingController();
  final _salePriceController = TextEditingController();
  final _profitPercentageController = TextEditingController();
  
  ProductCategory _selectedCategory = ProductCategory.ropa;
  String? _selectedProviderId;
  bool _usePercentage = false;
  bool _isLoading = false;
  List<String> _tags = [];
  String? _imageId;
  String? _originalImageId;  // Para detectar si cambio (cleanup en cancel)

  @override
  void initState() {
    super.initState();
    _initializeFields();
  }

  void _initializeFields() {
    _nameController.text = widget.product.name;
    _quantityController.text = widget.product.quantity.toString();
    _codeController.text = widget.product.code;
    _selectedCategory = widget.product.category;
    _selectedProviderId = widget.product.providerId;
    _usePercentage = widget.product.usePercentage;
    _tags = List<String>.from(widget.product.tags ?? const []);
    _imageId = widget.product.imageId;
    _originalImageId = widget.product.imageId;
    
    if (widget.product.cost != null) {
      _costController.text = widget.product.cost!.toStringAsFixed(0);
    }
    
    if (widget.product.usePercentage && widget.product.profitPercentage != null) {
      _profitPercentageController.text = widget.product.profitPercentage!.toStringAsFixed(0);
    } else if (widget.product.salePrice != null) {
      _salePriceController.text = widget.product.salePrice!.toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    _codeController.dispose();
    _costController.dispose();
    _salePriceController.dispose();
    _profitPercentageController.dispose();
    super.dispose();
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Update product fields
      widget.product.name = _nameController.text.trim();
      widget.product.quantity = int.parse(_quantityController.text);
      widget.product.code = _codeController.text.trim().toUpperCase();
      widget.product.category = _selectedCategory;
      widget.product.providerId = _selectedProviderId;
      widget.product.usePercentage = _usePercentage;
      widget.product.tags = _tags.isEmpty ? null : List<String>.from(_tags);
      widget.product.imageId = _imageId;
      // Si cambio la imagen y la vieja sigue en server, limpiarla.
      // (El widget ya borro la anterior al subir una nueva, pero esta
      // doble verificacion cubre el caso de eliminacion via X.)
      if (_originalImageId != null && _originalImageId != _imageId) {
        // El widget ya hizo deleteFile en el upload. No hacer nada.
      }
      
      // Update cost
      if (_costController.text.isNotEmpty) {
        widget.product.cost = double.parse(_costController.text);
      } else {
        widget.product.cost = null;
      }

      // Update sale price or percentage
      if (_usePercentage) {
        widget.product.salePrice = null;
        if (_profitPercentageController.text.isNotEmpty) {
          widget.product.profitPercentage = double.parse(_profitPercentageController.text);
        } else {
          widget.product.profitPercentage = null;
        }
      } else {
        widget.product.profitPercentage = null;
        if (_salePriceController.text.isNotEmpty) {
          widget.product.salePrice = double.parse(_salePriceController.text);
        } else {
          widget.product.salePrice = null;
        }
      }

      // Validate and save
      final validation = widget.product.validateProduct();
      if (!validation.isValid) {
        throw Exception(validation.errorMessage);
      }

      await widget.product.save();

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Producto actualizado exitosamente'),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al actualizar producto: ${e.toString()}'),
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
    
    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.primaryColor.withValues(alpha: 0.1),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.edit,
                    color: theme.primaryColor,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Editar Producto',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.primaryColor,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    iconSize: 20,
                  ),
                ],
              ),
            ),
            
            // Form content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Foto del producto
                      Center(
                        child: ProductImagePicker(
                          initialImageId: _imageId,
                          productCode: widget.product.code,
                          onImageChanged: (id) => _imageId = id,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Product Name
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Nombre del producto *',
                          prefixIcon: Icon(Icons.inventory),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'El nombre es requerido';
                          }
                          if (value.trim().length > 100) {
                            return 'Máximo 100 caracteres';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      
                      // Product Code
                      TextFormField(
                        controller: _codeController,
                        decoration: const InputDecoration(
                          labelText: 'Código del producto *',
                          prefixIcon: Icon(Icons.qr_code),
                          border: OutlineInputBorder(),
                          helperText: 'Código único para identificar el producto',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'El código es requerido';
                          }
                          
                          final code = value.trim().toUpperCase();
                          if (!ProductCodeValidator.isCodeValid(code)) {
                            return 'Código inválido (3-50 caracteres, sin símbolos)';
                          }
                          
                          if (!ProductCodeValidator.isCodeUnique(code, excludeKey: widget.product.key)) {
                            return 'Este código ya existe';
                          }
                          
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      
                      // Category
                      DropdownButtonFormField<ProductCategory>(
                        value: _selectedCategory,
                        decoration: const InputDecoration(
                          labelText: 'Categoría *',
                          prefixIcon: Icon(Icons.category),
                          border: OutlineInputBorder(),
                        ),
                        items: ProductCategory.values.map((category) {
                          return DropdownMenuItem(
                            value: category,
                            child: Text(category.displayName),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _selectedCategory = value;
                            });
                          }
                        },
                        validator: (value) {
                          if (value == null) {
                            return 'Seleccione una categoría';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      
                      // Quantity
                      TextFormField(
                        controller: _quantityController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Cantidad en stock *',
                          prefixIcon: Icon(Icons.numbers),
                          border: OutlineInputBorder(),
                          suffixText: 'unidades',
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'La cantidad es requerida';
                          }
                          final quantity = int.tryParse(value);
                          if (quantity == null) {
                            return 'Ingrese un número válido';
                          }
                          if (quantity < 0) {
                            return 'La cantidad no puede ser negativa';
                          }
                          if (quantity > 999999) {
                            return 'Cantidad máxima: 999,999';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      
                      // Provider
                      ValueListenableBuilder<Box<Provider>>(
                        valueListenable: Hive.box<Provider>('providers').listenable(),
                        builder: (context, box, _) {
                          final providers = box.values.toList().cast<Provider>();
                          
                          return DropdownButtonFormField<String?>(
                            value: _selectedProviderId,
                            decoration: const InputDecoration(
                              labelText: 'Proveedor (opcional)',
                              prefixIcon: Icon(Icons.business),
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('Sin proveedor'),
                              ),
                              ...providers.map((provider) {
                                return DropdownMenuItem<String?>(
                                  value: provider.key.toString(),
                                  child: Text(provider.name),
                                );
                              }),
                            ],
                            onChanged: (value) {
                              setState(() {
                                _selectedProviderId = value;
                              });
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 16),

                      // Tags personalizados
                      ValueListenableBuilder<Box<Product>>(
                        valueListenable: Hive.box<Product>('products').listenable(),
                        builder: (context, box, _) {
                          final allTags = collectAllTags(box.values);
                          return TagsInput(
                            initialTags: _tags,
                            onChanged: (newTags) => _tags = newTags,
                            suggestions: allTags,
                            label: 'Tags (opcional)',
                            hint: 'Ej: verano, oferta, regalo...',
                          );
                        },
                      ),
                      const SizedBox(height: 16),

                      // Cost
                      TextFormField(
                        controller: _costController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Costo (opcional)',
                          prefixIcon: Icon(Icons.attach_money),
                          border: OutlineInputBorder(),
                          prefixText: '\$ ',
                        ),
                        validator: (value) {
                          if (value != null && value.isNotEmpty) {
                            final cost = double.tryParse(value);
                            if (cost == null) {
                              return 'Ingrese un número válido';
                            }
                            if (cost < 0) {
                              return 'El costo no puede ser negativo';
                            }
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      
                      // Pricing method selection
                      Text(
                        'Método de precio de venta:',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      
                      Row(
                        children: [
                          Expanded(
                            child: RadioListTile<bool>(
                              title: const Text('Precio fijo'),
                              value: false,
                              groupValue: _usePercentage,
                              onChanged: (value) {
                                setState(() {
                                  _usePercentage = value ?? false;
                                });
                              },
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          Expanded(
                            child: RadioListTile<bool>(
                              title: const Text('Por porcentaje'),
                              value: true,
                              groupValue: _usePercentage,
                              onChanged: (value) {
                                setState(() {
                                  _usePercentage = value ?? false;
                                });
                              },
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      
                      // Price/Percentage field
                      if (_usePercentage)
                        TextFormField(
                          controller: _profitPercentageController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Porcentaje de ganancia',
                            prefixIcon: Icon(Icons.percent),
                            border: OutlineInputBorder(),
                            suffixText: '%',
                            helperText: 'Ej: 50 (para 50% de ganancia)',
                          ),
                          validator: (value) {
                            if (value != null && value.isNotEmpty) {
                              final percentage = double.tryParse(value);
                              if (percentage == null) {
                                return 'Ingrese un número válido';
                              }
                              if (percentage < 0) {
                                return 'El porcentaje no puede ser negativo';
                              }
                              if (percentage > 1000) {
                                return 'Porcentaje máximo: 1000%';
                              }
                            }
                            return null;
                          },
                        )
                      else
                        TextFormField(
                          controller: _salePriceController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Precio de venta',
                            prefixIcon: Icon(Icons.sell),
                            border: OutlineInputBorder(),
                            prefixText: '\$ ',
                          ),
                          validator: (value) {
                            if (value != null && value.isNotEmpty) {
                              final price = double.tryParse(value);
                              if (price == null) {
                                return 'Ingrese un número válido';
                              }
                              if (price < 0) {
                                return 'El precio no puede ser negativo';
                              }
                            }
                            return null;
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ),
            
            // Action buttons
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _saveProduct,
                    child: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Guardar Cambios'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}