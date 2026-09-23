import 'package:hive/hive.dart';

part 'cuenta_corriente.g.dart';

@HiveType(typeId: 7)
class CuentaCorriente extends HiveObject {
  @HiveField(0)
  late String clienteId; // Key del cliente en Hive
  
  @HiveField(1)
  late DateTime fechaApertura;
  
  @HiveField(2)
  double saldoActual;
  
  @HiveField(3)
  double limiteCredito;
  
  @HiveField(4)
  bool activa;
  
  @HiveField(5)
  String? notas;
  
  @HiveField(6)
  DateTime? fechaCierre;

  CuentaCorriente({
    required this.clienteId,
    required this.fechaApertura,
    this.saldoActual = 0.0,
    this.limiteCredito = 0.0,
    this.activa = true,
    this.notas,
    this.fechaCierre,
  });

  bool get tieneSaldoPendiente => saldoActual > 0;
  bool get esMorosa => diasSinPago > 30;
  
  int get diasSinPago {
    // Calcular días desde el último movimiento de deuda
    // Por ahora retornamos 0, se calculará con los movimientos
    return 0;
  }

  Map<String, dynamic> toJson() {
    return {
      'clienteId': clienteId,
      'fechaApertura': fechaApertura.toIso8601String(),
      'saldoActual': saldoActual,
      'limiteCredito': limiteCredito,
      'activa': activa,
      'notas': notas,
      'fechaCierre': fechaCierre?.toIso8601String(),
    };
  }

  static CuentaCorriente fromJson(Map<String, dynamic> json) {
    return CuentaCorriente(
      clienteId: json['clienteId'],
      fechaApertura: DateTime.parse(json['fechaApertura']),
      saldoActual: json['saldoActual']?.toDouble() ?? 0.0,
      limiteCredito: json['limiteCredito']?.toDouble() ?? 0.0,
      activa: json['activa'] ?? true,
      notas: json['notas'],
      fechaCierre: json['fechaCierre'] != null 
          ? DateTime.parse(json['fechaCierre']) 
          : null,
    );
  }
}