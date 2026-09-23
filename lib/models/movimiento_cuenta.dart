import 'package:hive/hive.dart';

part 'movimiento_cuenta.g.dart';

@HiveType(typeId: 8)
enum TipoMovimiento {
  @HiveField(0)
  cargo, // Cuando compra algo (aumenta deuda)
  
  @HiveField(1) 
  pago, // Cuando paga algo (reduce deuda)
  
  @HiveField(2)
  ajuste, // Ajustes manuales
}

@HiveType(typeId: 9)
class MovimientoCuenta extends HiveObject {
  @HiveField(0)
  late String cuentaId; // Key de la cuenta corriente
  
  @HiveField(1)
  late TipoMovimiento tipo;
  
  @HiveField(2)
  late double monto;
  
  @HiveField(3)
  late DateTime fecha;
  
  @HiveField(4)
  late String descripcion;
  
  @HiveField(5)
  String? referencia; // Puede ser ID de venta, recibo, etc.
  
  @HiveField(6)
  String? notas;
  
  @HiveField(7)
  double saldoAnterior;
  
  @HiveField(8)
  double saldoPosterior;

  MovimientoCuenta({
    required this.cuentaId,
    required this.tipo,
    required this.monto,
    required this.fecha,
    required this.descripcion,
    this.referencia,
    this.notas,
    required this.saldoAnterior,
    required this.saldoPosterior,
  });

  bool get esCargo => tipo == TipoMovimiento.cargo;
  bool get esPago => tipo == TipoMovimiento.pago;
  
  String get tipoString {
    switch (tipo) {
      case TipoMovimiento.cargo:
        return 'Cargo';
      case TipoMovimiento.pago:
        return 'Pago';
      case TipoMovimiento.ajuste:
        return 'Ajuste';
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'cuentaId': cuentaId,
      'tipo': tipo.index,
      'monto': monto,
      'fecha': fecha.toIso8601String(),
      'descripcion': descripcion,
      'referencia': referencia,
      'notas': notas,
      'saldoAnterior': saldoAnterior,
      'saldoPosterior': saldoPosterior,
    };
  }

  static MovimientoCuenta fromJson(Map<String, dynamic> json) {
    return MovimientoCuenta(
      cuentaId: json['cuentaId'],
      tipo: TipoMovimiento.values[json['tipo']],
      monto: json['monto']?.toDouble() ?? 0.0,
      fecha: DateTime.parse(json['fecha']),
      descripcion: json['descripcion'],
      referencia: json['referencia'],
      notas: json['notas'],
      saldoAnterior: json['saldoAnterior']?.toDouble() ?? 0.0,
      saldoPosterior: json['saldoPosterior']?.toDouble() ?? 0.0,
    );
  }
}