// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'movimiento_cuenta.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class MovimientoCuentaAdapter extends TypeAdapter<MovimientoCuenta> {
  @override
  final int typeId = 9;

  @override
  MovimientoCuenta read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return MovimientoCuenta(
      cuentaId: fields[0] as String,
      tipo: fields[1] as TipoMovimiento,
      monto: fields[2] as double,
      fecha: fields[3] as DateTime,
      descripcion: fields[4] as String,
      referencia: fields[5] as String?,
      notas: fields[6] as String?,
      saldoAnterior: fields[7] as double,
      saldoPosterior: fields[8] as double,
    );
  }

  @override
  void write(BinaryWriter writer, MovimientoCuenta obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.cuentaId)
      ..writeByte(1)
      ..write(obj.tipo)
      ..writeByte(2)
      ..write(obj.monto)
      ..writeByte(3)
      ..write(obj.fecha)
      ..writeByte(4)
      ..write(obj.descripcion)
      ..writeByte(5)
      ..write(obj.referencia)
      ..writeByte(6)
      ..write(obj.notas)
      ..writeByte(7)
      ..write(obj.saldoAnterior)
      ..writeByte(8)
      ..write(obj.saldoPosterior);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MovimientoCuentaAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class TipoMovimientoAdapter extends TypeAdapter<TipoMovimiento> {
  @override
  final int typeId = 8;

  @override
  TipoMovimiento read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return TipoMovimiento.cargo;
      case 1:
        return TipoMovimiento.pago;
      case 2:
        return TipoMovimiento.ajuste;
      default:
        return TipoMovimiento.cargo;
    }
  }

  @override
  void write(BinaryWriter writer, TipoMovimiento obj) {
    switch (obj) {
      case TipoMovimiento.cargo:
        writer.writeByte(0);
        break;
      case TipoMovimiento.pago:
        writer.writeByte(1);
        break;
      case TipoMovimiento.ajuste:
        writer.writeByte(2);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TipoMovimientoAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
