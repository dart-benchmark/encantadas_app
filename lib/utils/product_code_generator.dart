import 'dart:math';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/product.dart';
import 'validate_product_code.dart';

class ProductCodeGenerator {
  static const String _codePrefix = 'P-';
  static const int _codeLength = 6; // Total length including prefix (P-001)
  static final Random _random = Random();

  /// Generates a unique product code
  /// Format: P-001, P-002, etc. (incremental)
  /// If incremental fails, falls back to random alphanumeric
  /// Uses ProductCodeValidator for enhanced validation
  static String generateUniqueCode() {
    try {
      // Use the enhanced generator from validator
      return ProductCodeValidator.generateUniqueCode(prefix: _codePrefix);
    } catch (e) {
      // Fallback to original logic if validator fails
      // Warning: Using fallback code generation due to error
      return _generateFallbackCode();
    }
  }
  
  /// Fallback code generation method
  static String _generateFallbackCode() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final randomSuffix = (timestamp % 10000).toString().padLeft(4, '0');
    final code = '$_codePrefix$randomSuffix';
    
    // Final validation
    if (ProductCodeValidator.isCodeValid(code) && ProductCodeValidator.isCodeUnique(code)) {
      return code;
    }
    
    // Ultimate fallback: UUID-style
    final uuid = DateTime.now().microsecondsSinceEpoch.toRadixString(36).toUpperCase();
    return '$_codePrefix${uuid.substring(uuid.length - 6)}';
  }

  /// Generates incremental code based on existing products
  static String _generateIncrementalCode(Box<Product> box) {
    final products = box.values.toList();
    
    if (products.isEmpty) {
      return '${_codePrefix}001';
    }
    
    // Find the highest number in existing codes
    int maxNumber = 0;
    for (final product in products) {
      if (product.code.startsWith(_codePrefix)) {
        final numberPart = product.code.substring(_codePrefix.length);
        final number = int.tryParse(numberPart) ?? 0;
        if (number > maxNumber) {
          maxNumber = number;
        }
      }
    }
    
    // Generate next incremental code
    final nextNumber = maxNumber + 1;
    return '$_codePrefix${nextNumber.toString().padLeft(3, '0')}';
  }

  /// Generates random alphanumeric code
  static String _generateRandomCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final codeLength = _codeLength - _codePrefix.length;
    
    String code = _codePrefix;
    for (int i = 0; i < codeLength; i++) {
      code += chars[_random.nextInt(chars.length)];
    }
    
    return code;
  }

  /// Generates timestamp-based code (fallback)
  static String _generateTimestampCode() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final shortTimestamp = timestamp.toString().substring(timestamp.toString().length - 5);
    return '$_codePrefix$shortTimestamp';
  }

  /// Checks if a code already exists in the database
  /// DEPRECATED: Use ProductCodeValidator.isCodeUnique instead
  @deprecated
  static bool _codeExists(Box<Product> box, String code) {
    return !ProductCodeValidator.isCodeUnique(code);
  }

  /// Validates if a code follows the expected format
  /// Uses enhanced validation from ProductCodeValidator
  static bool isValidCode(String code) {
    // Use the enhanced validator first
    if (!ProductCodeValidator.isCodeValid(code)) {
      return false;
    }
    
    // Additional legacy format checks for backwards compatibility
    if (code.isEmpty) return false;
    
    // Must start with prefix
    if (!code.toUpperCase().startsWith(_codePrefix.toUpperCase())) {
      return false;
    }
    
    // Must have reasonable length (flexible for future expansion)
    if (code.length < 4 || code.length > 20) {
      return false;
    }
    
    return true;
  }

  /// Gets the next available incremental code (for display purposes)
  static String getNextCode() {
    final box = Hive.box<Product>('products');
    return _generateIncrementalCode(box);
  }
}