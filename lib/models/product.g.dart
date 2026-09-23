// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'product.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ProductAdapter extends TypeAdapter<Product> {
  @override
  final int typeId = 3;

  @override
  Product read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Product(
      name: fields[0] as String,
      category: fields[1] as ProductCategory,
      quantity: fields[2] as int,
      createdAt: fields[3] as DateTime,
      code: fields[6] as String,
      cost: fields[4] as double?,
      providerId: fields[5] as String?,
      salePrice: fields[7] as double?,
      profitPercentage: fields[8] as double?,
      usePercentage: fields[9] as bool,
      tags: (fields[10] as List?)?.cast<String>(),
      imageId: fields[11] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, Product obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.name)
      ..writeByte(1)
      ..write(obj.category)
      ..writeByte(2)
      ..write(obj.quantity)
      ..writeByte(3)
      ..write(obj.createdAt)
      ..writeByte(4)
      ..write(obj.cost)
      ..writeByte(5)
      ..write(obj.providerId)
      ..writeByte(6)
      ..write(obj.code)
      ..writeByte(7)
      ..write(obj.salePrice)
      ..writeByte(8)
      ..write(obj.profitPercentage)
      ..writeByte(9)
      ..write(obj.usePercentage)
      ..writeByte(10)
      ..write(obj.tags)
      ..writeByte(11)
      ..write(obj.imageId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProductAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class ProductCategoryAdapter extends TypeAdapter<ProductCategory> {
  @override
  final int typeId = 2;

  @override
  ProductCategory read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return ProductCategory.ropa;
      case 1:
        return ProductCategory.unas;
      case 2:
        return ProductCategory.bijouterie;
      default:
        return ProductCategory.ropa;
    }
  }

  @override
  void write(BinaryWriter writer, ProductCategory obj) {
    switch (obj) {
      case ProductCategory.ropa:
        writer.writeByte(0);
        break;
      case ProductCategory.unas:
        writer.writeByte(1);
        break;
      case ProductCategory.bijouterie:
        writer.writeByte(2);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProductCategoryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
