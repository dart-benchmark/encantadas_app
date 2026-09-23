// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cuenta_corriente.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class CuentaCorrienteAdapter extends TypeAdapter<CuentaCorriente> {
  @override
  final int typeId = 7;

  @override
  CuentaCorriente read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return CuentaCorriente(
      clienteId: fields[0] as String,
      fechaApertura: fields[1] as DateTime,
      saldoActual: fields[2] as double,
      limiteCredito: fields[3] as double,
      activa: fields[4] as bool,
      notas: fields[5] as String?,
      fechaCierre: fields[6] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, CuentaCorriente obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.clienteId)
      ..writeByte(1)
      ..write(obj.fechaApertura)
      ..writeByte(2)
      ..write(obj.saldoActual)
      ..writeByte(3)
      ..write(obj.limiteCredito)
      ..writeByte(4)
      ..write(obj.activa)
      ..writeByte(5)
      ..write(obj.notas)
      ..writeByte(6)
      ..write(obj.fechaCierre);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CuentaCorrienteAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
