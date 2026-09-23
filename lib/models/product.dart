import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../utils/validate_product_code.dart';

part 'product.g.dart';

@HiveType(typeId: 2)
enum ProductCategory {
  @HiveField(0)
  ropa,
  @HiveField(1)
  unas,
  @HiveField(2)
  bijouterie,
}

@HiveType(typeId: 3)
class Product extends HiveObject {
  @HiveField(0)
  String name;

  @HiveField(1)
  ProductCategory category;

  @HiveField(2)
  int quantity;

  @HiveField(3)
  DateTime createdAt;

  @HiveField(4)
  double? cost;

  @HiveField(5)
  String? providerId;

  @HiveField(6)
  String code;

  @HiveField(7)
  double? salePrice;

  @HiveField(8)
  double? profitPercentage;

  @HiveField(9)
  bool usePercentage;

  // Tags personalizados del usuario (chips para filtrar en Stock/Ventas).
  // Adicional a `category`. Cada tag se almacena en lowercase y trimmed.
  // Backward-compat: productos viejos quedan con null.
  @HiveField(10)
  List<String>? tags;

  // ID del archivo subido al backend (collection encantadas_files).
  // Null = producto sin foto. La URL se construye dinamicamente desde
  // PocketBaseSyncService.getFileUrl(imageId).
  // Las fotos NO se incluyen en el JSON de backup (solo el ID), por
  // performance. La foto vive solo en el server.
  @HiveField(11)
  String? imageId;

  Product({
    required this.name,
    required this.category,
    required this.quantity,
    required this.createdAt,
    required this.code,
    this.cost,
    this.providerId,
    this.salePrice,
    this.profitPercentage,
    this.usePercentage = false,
    this.tags,
    this.imageId,
  });

  /// Convenience: producto tiene foto cargada.
  bool get hasImage => imageId != null && imageId!.isNotEmpty;

  /// Tags normalizados y sin nulls. Lista vacía si no hay tags.
  List<String> get tagsNormalized {
    if (tags == null) return const [];
    return tags!
        .map((t) => t.trim().toLowerCase())
        .where((t) => t.isNotEmpty)
        .toList();
  }

  // Helper method to get category display name with emoji
  String get categoryDisplayName {
    switch (category) {
      case ProductCategory.ropa:
        return '👕 Ropa';
      case ProductCategory.unas:
        return '💅 Uñas';
      case ProductCategory.bijouterie:
        return '💍 Bijouterie';
    }
  }

  // Helper method to get category color
  Color get categoryColor {
    switch (category) {
      case ProductCategory.ropa:
        return const Color(0xFF2196F3); // Blue
      case ProductCategory.unas:
        return const Color(0xFFE91E63); // Pink
      case ProductCategory.bijouterie:
        return const Color(0xFFFF9800); // Orange
    }
  }

  // Helper method to format creation date
  String get formattedCreatedAt {
    final date = '${createdAt.day.toString().padLeft(2, '0')}/'
        '${createdAt.month.toString().padLeft(2, '0')}/'
        '${createdAt.year}';
    return date;
  }

  // Helper method to get quantity status
  String get quantityStatus {
    if (quantity == 0) {
      return 'Sin stock';
    } else if (quantity <= 5) {
      return 'Stock bajo';
    } else {
      return 'En stock';
    }
  }

  // Helper method to get quantity status color
  Color get quantityStatusColor {
    if (quantity == 0) {
      return const Color(0xFFF44336); // Red
    } else if (quantity <= 5) {
      return const Color(0xFFFF9800); // Orange
    } else {
      return const Color(0xFF4CAF50); // Green
    }
  }

  // Helper method to format cost
  String get formattedCost {
    if (cost == null) {
      return 'Sin costo';
    }
    return '\$${cost!.toStringAsFixed(0)}';
  }

  // Helper method to format sale price
  String get formattedSalePrice {
    if (salePrice == null) {
      return 'Sin precio';
    }
    return '\$${salePrice!.toStringAsFixed(0)}';
  }

  // Helper method to get calculated sale price
  double get calculatedSalePrice {
    if (usePercentage && cost != null && profitPercentage != null) {
      return cost! + (cost! * profitPercentage! / 100);
    }
    return salePrice ?? 0.0;
  }

  // Helper method to get formatted calculated sale price
  String get formattedCalculatedSalePrice {
    final price = calculatedSalePrice;
    if (price <= 0) {
      return 'Sin precio';
    }
    return '\$${price.toStringAsFixed(0)}';
  }

  // Helper method to calculate profit amount
  double get profitAmount {
    if (cost == null) return 0.0;
    return calculatedSalePrice - cost!;
  }

  // Helper method to get formatted profit
  String get formattedProfit {
    final profit = profitAmount;
    if (profit <= 0) {
      return 'Sin ganancia';
    }
    return '\$${profit.toStringAsFixed(0)}';
  }

  // Helper method to calculate actual profit percentage
  double get actualProfitPercentage {
    if (cost == null || cost! == 0) return 0.0;
    return (profitAmount / cost!) * 100;
  }

  // Helper method to check if has cost info
  bool get hasCostInfo {
    return cost != null && cost! > 0;
  }

  // Helper method to check if has sale price info
  bool get hasSalePriceInfo {
    return calculatedSalePrice > 0;
  }

  // Helper method to check if has provider
  bool get hasProvider {
    return providerId != null && providerId!.isNotEmpty;
  }

  // Helper method to format product code
  String get formattedCode {
    return code.toUpperCase();
  }

  // Validation methods
  
  /// Validates if the product code is valid and unique
  /// 
  /// Returns a ProductValidationResult with validation details
  ProductValidationResult validateCode() {
    // Check if code is valid format
    if (!ProductCodeValidator.isCodeValid(code)) {
      return ProductValidationResult(
        isValid: false,
        errorMessage: 'Código de producto inválido. Debe tener entre 3-50 caracteres y no contener caracteres especiales.',
      );
    }
    
    // Check if code is unique (exclude current product if editing)
    if (!ProductCodeValidator.isCodeUnique(code, excludeKey: key)) {
      return ProductValidationResult(
        isValid: false,
        errorMessage: 'Este código ya existe. Por favor, use un código único.',
      );
    }
    
    return ProductValidationResult(isValid: true);
  }
  
  /// Validates the entire product before saving
  /// 
  /// Returns a ProductValidationResult with validation details
  ProductValidationResult validateProduct() {
    // Validate product name
    if (name.trim().isEmpty) {
      return ProductValidationResult(
        isValid: false,
        errorMessage: 'El nombre del producto es requerido.',
      );
    }
    
    if (name.trim().length > 100) {
      return ProductValidationResult(
        isValid: false,
        errorMessage: 'El nombre del producto no puede exceder 100 caracteres.',
      );
    }
    
    // Validate quantity
    if (quantity < 0) {
      return ProductValidationResult(
        isValid: false,
        errorMessage: 'La cantidad no puede ser negativa.',
      );
    }
    
    if (quantity > 999999) {
      return ProductValidationResult(
        isValid: false,
        errorMessage: 'La cantidad no puede exceder 999,999 unidades.',
      );
    }
    
    // Validate cost if provided
    if (cost != null && cost! < 0) {
      return ProductValidationResult(
        isValid: false,
        errorMessage: 'El costo no puede ser negativo.',
      );
    }
    
    // Validate code
    final codeValidation = validateCode();
    if (!codeValidation.isValid) {
      return codeValidation;
    }
    
    return ProductValidationResult(isValid: true);
  }
  
  /// Safely saves the product with validation
  /// 
  /// Returns true if saved successfully, false otherwise
  /// Throws ProductValidationException if validation fails
  Future<bool> saveWithValidation() async {
    try {
      final validation = validateProduct();
      if (!validation.isValid) {
        throw ProductValidationException(validation.errorMessage ?? 'Error de validación desconocido');
      }
      
      await save();
      return true;
    } catch (e) {
      // Error saving product
      rethrow;
    }
  }
  
  /// Checks if the product has a valid QR code
  bool get hasValidQRCode {
    return ProductCodeValidator.isCodeValid(code);
  }

  /// Convert product to JSON for backup
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'category': category.name,
      'quantity': quantity,
      'createdAt': createdAt.toIso8601String(),
      'cost': cost,
      'providerId': providerId,
      'code': code,
      'salePrice': salePrice,
      'profitPercentage': profitPercentage,
      'usePercentage': usePercentage,
      'tags': tags,
      'imageId': imageId,
    };
  }

  /// Create product from JSON for restore
  static Product fromJson(Map<String, dynamic> json) {
    return Product(
      name: json['name'] as String,
      category: ProductCategory.values.firstWhere(
        (e) => e.name == json['category'],
        orElse: () => ProductCategory.ropa,
      ),
      quantity: json['quantity'] as int,
      createdAt: DateTime.parse(json['createdAt'] as String),
      code: json['code'] as String,
      cost: json['cost'] as double?,
      providerId: json['providerId'] as String?,
      salePrice: json['salePrice'] as double?,
      profitPercentage: json['profitPercentage'] as double?,
      usePercentage: json['usePercentage'] as bool? ?? false,
      tags: (json['tags'] as List?)?.map((e) => e as String).toList(),
      imageId: json['imageId'] as String?,
    );
  }
}

extension ProductCategoryExtension on ProductCategory {
  String get displayName {
    switch (this) {
      case ProductCategory.ropa:
        return '👕 Ropa';
      case ProductCategory.unas:
        return '💅 Uñas';
      case ProductCategory.bijouterie:
        return '💍 Bijouterie';
    }
  }
}

/// Resultado de validación de producto
class ProductValidationResult {
  final bool isValid;
  final String? errorMessage;
  
  const ProductValidationResult({
    required this.isValid,
    this.errorMessage,
  });
}

/// Excepción para errores de validación de producto
class ProductValidationException implements Exception {
  final String message;
  
  const ProductValidationException(this.message);
  
  @override
  String toString() => 'ProductValidationException: $message';
}