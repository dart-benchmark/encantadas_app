import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/cliente.dart';
import '../models/cuenta_corriente.dart';
import '../models/movimiento_cuenta.dart';
import '../services/cuenta_corriente_service.dart';

class EstadisticasCuentaCorrienteSheet extends StatelessWidget {
  final CuentaCorrienteService service;

  const EstadisticasCuentaCorrienteSheet({
    super.key,
    required this.service,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).primaryColor,
                  Theme.of(context).primaryColor.withValues(alpha: 0.8),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                const Icon(Icons.analytics, color: Colors.white, size: 28),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Estadísticas Detalladas',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ],
            ),
          ),
          
          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ValueListenableBuilder(
                valueListenable: Hive.box<Cliente>('clientes_cuenta').listenable(),
                builder: (context, clientesBox, _) {
                  return ValueListenableBuilder(
                    valueListenable: Hive.box<CuentaCorriente>('cuentas_corrientes').listenable(),
                    builder: (context, cuentasBox, _) {
                      return ValueListenableBuilder(
                        valueListenable: Hive.box<MovimientoCuenta>('movimientos_cuenta').listenable(),
                        builder: (context, movimientosBox, _) {
                          final stats = _calcularEstadisticas();
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Resumen General
                              _buildSeccionTitulo('📊 Resumen General'),
                              const SizedBox(height: 16),
                              _buildTarjetasResumen(stats),
                              
                              const SizedBox(height: 32),
                              
                              // Distribución por Estado
                              _buildSeccionTitulo('📈 Distribución por Estado'),
                              const SizedBox(height: 16),
                              _buildDistribucionEstado(stats),
                              
                              const SizedBox(height: 32),
                              
                              // Clientes Morosos
                              if (stats['clientesMorosos'].isNotEmpty) ...[
                                _buildSeccionTitulo('⚠️ Clientes Morosos'),
                                const SizedBox(height: 16),
                                _buildListaMorosos(stats['clientesMorosos']),
                                const SizedBox(height: 32),
                              ],
                              
                              // Mayores Deudores
                              if (stats['mayoresDeudores'].isNotEmpty) ...[
                                _buildSeccionTitulo('💰 Mayores Deudores'),
                                const SizedBox(height: 16),
                                _buildMayoresDeudores(stats['mayoresDeudores']),
                                const SizedBox(height: 32),
                              ],
                              
                              // Actividad Reciente
                              _buildSeccionTitulo('🕒 Actividad Reciente'),
                              const SizedBox(height: 16),
                              _buildActividadReciente(stats),
                            ],
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Map<String, dynamic> _calcularEstadisticas() {
    final clientes = service.obtenerClientes();
    final cuentas = service.obtenerCuentas();
    final movimientosBox = Hive.box<MovimientoCuenta>('movimientos_cuenta');
    
    double totalDeuda = 0;
    int clientesConSaldo = 0;
    int clientesMorosos = 0;
    List<Map<String, dynamic>> clientesMorososList = [];
    List<Map<String, dynamic>> mayoresDeudores = [];
    
    // Estadísticas de movimientos
    final ahora = DateTime.now();
    final hace30Dias = ahora.subtract(const Duration(days: 30));
    int movimientosUltimos30Dias = 0;
    double montoMovimientosUltimos30Dias = 0;
    
    for (final cuenta in cuentas) {
      if (cuenta.saldoActual > 0) {
        totalDeuda += cuenta.saldoActual;
        clientesConSaldo++;
        
        final cliente = _obtenerClientePorId(cuenta.clienteId);
        if (cliente != null) {
          mayoresDeudores.add({
            'cliente': cliente,
            'saldo': cuenta.saldoActual,
            'esMoroso': cuenta.esMorosa,
          });
          
          if (cuenta.esMorosa) {
            clientesMorosos++;
            clientesMorososList.add({
              'cliente': cliente,
              'saldo': cuenta.saldoActual,
              'diasMoroso': cuenta.diasSinPago,
            });
          }
        }
      }
    }
    
    // Contar movimientos recientes
    final movimientos = movimientosBox.values.where((mov) => 
      mov.fecha.isAfter(hace30Dias)
    ).toList();
    
    movimientosUltimos30Dias = movimientos.length;
    montoMovimientosUltimos30Dias = movimientos.fold(0.0, (sum, mov) => sum + mov.monto);
    
    // Ordenar mayores deudores
    mayoresDeudores.sort((a, b) => (b['saldo'] as double).compareTo(a['saldo'] as double));
    mayoresDeudores = mayoresDeudores.take(5).toList();
    
    // Ordenar morosos por días
    clientesMorososList.sort((a, b) => (b['diasMoroso'] as int).compareTo(a['diasMoroso'] as int));
    
    return {
      'totalClientes': clientes.length,
      'totalCuentas': cuentas.length,
      'clientesConSaldo': clientesConSaldo,
      'clientesSinSaldo': cuentas.length - clientesConSaldo,
      'clientesMorosos': clientesMorososList,
      'totalDeuda': totalDeuda,
      'promedioDeuda': clientesConSaldo > 0 ? totalDeuda / clientesConSaldo : 0.0,
      'mayoresDeudores': mayoresDeudores,
      'movimientosUltimos30Dias': movimientosUltimos30Dias,
      'montoMovimientosUltimos30Dias': montoMovimientosUltimos30Dias,
      'porcentajeMorosos': clientes.isNotEmpty ? (clientesMorosos / clientes.length) * 100 : 0.0,
    };
  }

  Cliente? _obtenerClientePorId(String clienteId) {
    try {
      final key = int.parse(clienteId);
      return Hive.box<Cliente>('clientes_cuenta').get(key);
    } catch (e) {
      return null;
    }
  }

  Widget _buildSeccionTitulo(String titulo) {
    return Text(
      titulo,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Color(0xFF2E2E2E),
      ),
    );
  }

  Widget _buildTarjetasResumen(Map<String, dynamic> stats) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildTarjetaEstadistica(
                'Total Clientes',
                '${stats['totalClientes']}',
                Icons.people,
                Colors.blue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildTarjetaEstadistica(
                'Con Saldo',
                '${stats['clientesConSaldo']}',
                Icons.account_balance_wallet,
                Colors.orange,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildTarjetaEstadistica(
                'Total Deuda',
                '\$${stats['totalDeuda'].toStringAsFixed(0)}',
                Icons.monetization_on,
                Colors.green,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildTarjetaEstadistica(
                'Morosos',
                '${stats['clientesMorosos'].length}',
                Icons.warning,
                Colors.red,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildTarjetaEstadistica(
                'Promedio Deuda',
                '\$${stats['promedioDeuda'].toStringAsFixed(0)}',
                Icons.trending_up,
                Colors.purple,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildTarjetaEstadistica(
                '% Morosos',
                '${stats['porcentajeMorosos'].toStringAsFixed(1)}%',
                Icons.percent,
                Colors.red,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTarjetaEstadistica(String titulo, String valor, IconData icono, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icono, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            valor,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: color,
            ),
          ),
          Text(
            titulo,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildDistribucionEstado(Map<String, dynamic> stats) {
    final total = stats['totalCuentas'] as int;
    final conSaldo = stats['clientesConSaldo'] as int;
    final sinSaldo = stats['clientesSinSaldo'] as int;
    final morosos = stats['clientesMorosos'].length as int;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        children: [
          _buildBarraProgreso('Al día', sinSaldo, total, Colors.green),
          const SizedBox(height: 8),
          _buildBarraProgreso('Con saldo', conSaldo - morosos, total, Colors.orange),
          const SizedBox(height: 8),
          _buildBarraProgreso('Morosos', morosos, total, Colors.red),
        ],
      ),
    );
  }

  Widget _buildBarraProgreso(String label, int cantidad, int total, Color color) {
    final porcentaje = total > 0 ? (cantidad / total) * 100 : 0.0;
    
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[700],
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 20,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(10),
            ),
            child: FractionallySizedBox(
              widthFactor: porcentaje / 100,
              alignment: Alignment.centerLeft,
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 60,
          child: Text(
            '$cantidad (${porcentaje.toStringAsFixed(1)}%)',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }

  Widget _buildListaMorosos(List<Map<String, dynamic>> morosos) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red[200]!),
      ),
      child: Column(
        children: morosos.take(5).map((item) {
          final cliente = item['cliente'] as Cliente;
          final saldo = item['saldo'] as double;
          final dias = item['diasMoroso'] as int;
          
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.red[100],
              child: const Icon(Icons.warning, color: Colors.red, size: 20),
            ),
            title: Text(
              cliente.nombreCompleto,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text('$dias días de atraso'),
            trailing: Text(
              '\$${saldo.toStringAsFixed(2)}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMayoresDeudores(List<Map<String, dynamic>> deudores) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.orange[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange[200]!),
      ),
      child: Column(
        children: deudores.map((item) {
          final cliente = item['cliente'] as Cliente;
          final saldo = item['saldo'] as double;
          final esMoroso = item['esMoroso'] as bool;
          
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: esMoroso ? Colors.red[100] : Colors.orange[100],
              child: Icon(
                esMoroso ? Icons.warning : Icons.account_balance_wallet,
                color: esMoroso ? Colors.red : Colors.orange,
                size: 20,
              ),
            ),
            title: Text(
              cliente.nombreCompleto,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(esMoroso ? 'Moroso' : 'Al día'),
            trailing: Text(
              '\$${saldo.toStringAsFixed(2)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: esMoroso ? Colors.red : Colors.orange,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildActividadReciente(Map<String, dynamic> stats) {
    final movimientos = stats['movimientosUltimos30Dias'] as int;
    final monto = stats['montoMovimientosUltimos30Dias'] as double;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.timeline, color: Colors.blue, size: 24),
              const SizedBox(width: 8),
              const Text(
                'Últimos 30 días',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildInfoCard(
                  'Movimientos',
                  movimientos.toString(),
                  Icons.swap_vert,
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildInfoCard(
                  'Monto Total',
                  '\$${monto.toStringAsFixed(0)}',
                  Icons.attach_money,
                  Colors.green,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String titulo, String valor, IconData icono, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icono, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            valor,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: color,
            ),
          ),
          Text(
            titulo,
            style: const TextStyle(
              fontSize: 11,
              color: Colors.grey,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}