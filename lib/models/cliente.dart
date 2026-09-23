import 'package:hive/hive.dart';

part 'cliente.g.dart';

@HiveType(typeId: 10)
class Cliente extends HiveObject {
  @HiveField(0)
  late String nombre;
  
  @HiveField(1)
  late String apellido;
  
  @HiveField(2)
  String? telefono;
  
  @HiveField(3)
  String? direccion;
  
  @HiveField(4)
  String? email;
  
  @HiveField(5)
  String? documento;
  
  @HiveField(6)
  late DateTime fechaRegistro;
  
  @HiveField(7)
  String? notas;
  
  @HiveField(8)
  bool activo;

  Cliente({
    required this.nombre,
    required this.apellido,
    this.telefono,
    this.direccion,
    this.email,
    this.documento,
    required this.fechaRegistro,
    this.notas,
    this.activo = true,
  });

  String get nombreCompleto => '$nombre $apellido';

  Map<String, dynamic> toJson() {
    return {
      'nombre': nombre,
      'apellido': apellido,
      'telefono': telefono,
      'direccion': direccion,
      'email': email,
      'documento': documento,
      'fechaRegistro': fechaRegistro.toIso8601String(),
      'notas': notas,
      'activo': activo,
    };
  }

  static Cliente fromJson(Map<String, dynamic> json) {
    return Cliente(
      nombre: json['nombre'],
      apellido: json['apellido'],
      telefono: json['telefono'],
      direccion: json['direccion'],
      email: json['email'],
      documento: json['documento'],
      fechaRegistro: DateTime.parse(json['fechaRegistro']),
      notas: json['notas'],
      activo: json['activo'] ?? true,
    );
  }
}