import 'package:hive/hive.dart';

part 'transaction.g.dart';

@HiveType(typeId: 1)
class Transaction extends HiveObject {
  @HiveField(0)
  double amount;

  @HiveField(1)
  DateTime date;

  @HiveField(2)
  String source;

  @HiveField(3)
  String clientName;

  @HiveField(4)
  String serviceName;

  // New fields for product sales
  @HiveField(5)
  String? productName;

  @HiveField(6)
  int? quantity;

  @HiveField(7)
  double? unitPrice;

  // Stable product reference. Older records (pre-2026-04-25) may have
  // this null — callers must fall back to productName when so.
  @HiveField(8)
  String? productCode;

  Transaction({
    required this.amount,
    required this.date,
    required this.source,
    required this.clientName,
    required this.serviceName,
    this.productName,
    this.quantity,
    this.unitPrice,
    this.productCode,
  });

  // Helper method to format date
  String get formattedDate {
    final date = '${this.date.day.toString().padLeft(2, '0')}/'
        '${this.date.month.toString().padLeft(2, '0')}/'
        '${this.date.year}';
    return date;
  }

  // Helper method to format amount
  String get formattedAmount {
    return '\$${amount.toStringAsFixed(0)}';
  }

  // Helper method to get formatted source with emoji
  String get formattedSource {
    switch (source.toLowerCase()) {
      case 'turno':
        return '💅 Turno';
      case 'venta':
        return '🛍️ Venta';
      case 'otro':
        return '💰 Otro';
      default:
        return source;
    }
  }

  // Helper method to check if it's a product sale
  bool get isProductSale {
    return source.toLowerCase() == 'venta' && productName != null;
  }

  // Helper method to get formatted quantity
  String get formattedQuantity {
    if (quantity == null) return '';
    return '${quantity} ${quantity == 1 ? 'unidad' : 'unidades'}';
  }

  // Helper method to get formatted unit price
  String get formattedUnitPrice {
    if (unitPrice == null) return '';
    return '\$${unitPrice!.toStringAsFixed(0)}';
  }

  // Helper method to get sale summary
  String get saleSummary {
    if (!isProductSale) return serviceName;
    return '${productName} (${formattedQuantity})';
  }

  /// Convert transaction to JSON for backup
  Map<String, dynamic> toJson() {
    return {
      'amount': amount,
      'date': date.toIso8601String(),
      'source': source,
      'clientName': clientName,
      'serviceName': serviceName,
      'productName': productName,
      'quantity': quantity,
      'unitPrice': unitPrice,
      'productCode': productCode,
    };
  }

  /// Create transaction from JSON for restore
  static Transaction fromJson(Map<String, dynamic> json) {
    return Transaction(
      amount: (json['amount'] as num).toDouble(),
      date: DateTime.parse(json['date'] as String),
      source: json['source'] as String,
      clientName: json['clientName'] as String,
      serviceName: json['serviceName'] as String,
      productName: json['productName'] as String?,
      quantity: json['quantity'] as int?,
      unitPrice: json['unitPrice'] != null ? (json['unitPrice'] as num).toDouble() : null,
      productCode: json['productCode'] as String?,
    );
  }
}