// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cliente.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ClienteAdapter extends TypeAdapter<Cliente> {
  @override
  final int typeId = 10;

  @override
  Cliente read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Cliente(
      nombre: fields[0] as String,
      apellido: fields[1] as String,
      telefono: fields[2] as String?,
      direccion: fields[3] as String?,
      email: fields[4] as String?,
      documento: fields[5] as String?,
      fechaRegistro: fields[6] as DateTime,
      notas: fields[7] as String?,
      activo: fields[8] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, Cliente obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.nombre)
      ..writeByte(1)
      ..write(obj.apellido)
      ..writeByte(2)
      ..write(obj.telefono)
      ..writeByte(3)
      ..write(obj.direccion)
      ..writeByte(4)
      ..write(obj.email)
      ..writeByte(5)
      ..write(obj.documento)
      ..writeByte(6)
      ..write(obj.fechaRegistro)
      ..writeByte(7)
      ..write(obj.notas)
      ..writeByte(8)
      ..write(obj.activo);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClienteAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
