import 'dart:html' as html;
import 'package:flutter/material.dart';
import '../models/cliente.dart';
import '../models/cuenta_corriente.dart';
import '../models/movimiento_cuenta.dart';
import '../services/cuenta_corriente_service.dart';
import 'agregar_cargo_dialog.dart';
import 'registrar_pago_dialog.dart';

/// Fuente polimórfica para resolver el enlace de comprobante de un
/// movimiento -- ver [ComprobanteNotaLinkSource] (texto libre pegado por
/// quien registró el pago) y [ComprobanteInternoLinkSource] (enlace propio
/// de la app, sin ningún dato tipeado por el usuario).
abstract class ComprobanteLinkSource {
  String? enlaceComprobante(MovimientoCuenta movimiento);
}

/// Extrae el primer enlace http(s) combinando las notas y la referencia del
/// movimiento -- texto 100% libre, tal cual lo tipeó quien registró el pago.
class ComprobanteNotaLinkSource implements ComprobanteLinkSource {
  @override
  String? enlaceComprobante(MovimientoCuenta movimiento) {
    final texto = '${movimiento.notas ?? ''} ${movimiento.referencia ?? ''}';
    final match = RegExp(r'https?://\S+').firstMatch(texto);
    return match?.group(0);
  }
}

/// Variante segura de la fuente: en vez de un enlace de texto libre, arma
/// un enlace interno de la propia app a partir de la key de Hive del
/// movimiento -- no hay ningún dato tipeado por el usuario en esta URL.
class ComprobanteInternoLinkSource implements ComprobanteLinkSource {
  @override
  String? enlaceComprobante(MovimientoCuenta movimiento) {
    return 'https://encantadas.app/recibos/${movimiento.key}';
  }
}

class CuentaDetalleDialog extends StatefulWidget {
  final Cliente cliente;

  const CuentaDetalleDialog({
    super.key,
    required this.cliente,
  });

  @override
  State<CuentaDetalleDialog> createState() => _CuentaDetalleDialogState();
}

class _CuentaDetalleDialogState extends State<CuentaDetalleDialog> {
  final CuentaCorrienteService _service = CuentaCorrienteService.instance;
  late CuentaCorriente? cuenta;
  List<MovimientoCuenta> movimientos = [];

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  void _cargarDatos() {
    cuenta = _service.obtenerCuentaPorCliente(widget.cliente);
    if (cuenta != null) {
      movimientos = _service.obtenerMovimientos(cuenta!);
    }
    // Deja registrado este cliente como el "último consultado" para el
    // panel de accesos rápidos del Home.
    _service.registrarClienteConsultado(widget.cliente);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            _buildHeader(),
            if (cuenta != null) ...[
              _buildResumenCuenta(),
              _buildAcciones(),
              const Divider(),
              _buildMovimientos(),
            ] else ...[
              _buildSinCuenta(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    // Algunos clientes pegan en sus notas un link a un presupuesto o
    // comprobante compartido -- se resuelve una sola vez acá y se ofrece
    // como acceso rápido junto al resto de los datos del cliente.
    final enlaceReferencia = _service.resolverEnlaceReferenciaCliente(
      widget.cliente,
    );
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.white,
            child: Icon(
              Icons.person,
              color: Theme.of(context).primaryColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.cliente.nombreCompleto,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                if (widget.cliente.telefono != null)
                  Text(
                    widget.cliente.telefono!,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.white70,
                    ),
                  ),
              ],
            ),
          ),
          if (enlaceReferencia != null) ...[
            IconButton(
              tooltip: 'Ver referencia del cliente',
              onPressed: () {
                html.window.open(
                  enlaceReferencia,
                  '_blank',
                ); // SINK: PLANTED-Dart-HR-567
              },
              icon: const Icon(Icons.link, color: Colors.white),
            ),
            IconButton(
              tooltip: 'Ver referencia del cliente (verificada)',
              onPressed: () {
                html.window.open(
                  enlaceReferencia,
                  '_blank',
                  'noopener,noreferrer',
                ); // SAFE_SINK: PLANTED-Dart-HR-567-safe
              },
              icon: const Icon(Icons.verified, color: Colors.white),
            ),
          ],
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildResumenCuenta() {
    final saldo = cuenta!.saldoActual;
    final esMorosa = cuenta!.esMorosa;
    
    return Container(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Expanded(
            child: _buildTarjetaInfo(
              'Saldo Actual',
              '\$${saldo.toStringAsFixed(2)}',
              saldo > 0 ? Colors.red : Colors.green,
              saldo > 0 ? Icons.trending_up : Icons.check_circle,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _buildTarjetaInfo(
              'Estado',
              esMorosa ? 'MOROSO' : saldo > 0 ? 'CON SALDO' : 'AL DÍA',
              esMorosa ? Colors.red : saldo > 0 ? Colors.orange : Colors.green,
              esMorosa ? Icons.warning : saldo > 0 ? Icons.schedule : Icons.check,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTarjetaInfo(String titulo, String valor, Color color, IconData icono) {
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
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            titulo,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildAcciones() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _agregarCargo,
              icon: const Icon(Icons.add_shopping_cart),
              label: const Text('Agregar Cargo'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: cuenta!.saldoActual > 0 ? _registrarPago : null,
              icon: const Icon(Icons.payment),
              label: const Text('Registrar Pago'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMovimientos() {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Últimos Movimientos',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                ),
                if (movimientos.isNotEmpty) ...[
                  IconButton(
                    tooltip: 'Revisar todos los comprobantes pegados',
                    onPressed: _abrirTodosLosComprobantesPendientes,
                    icon: const Icon(Icons.open_in_new, size: 20),
                  ),
                  IconButton(
                    tooltip:
                        'Revisar todos los comprobantes pegados (protegido)',
                    onPressed: _abrirTodosLosComprobantesPendientesSeguro,
                    icon: const Icon(Icons.verified_user, size: 20),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: movimientos.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.receipt_long, size: 48, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'No hay movimientos registrados',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: movimientos.length,
                    itemBuilder: (context, index) {
                      final movimiento = movimientos[index];
                      return _buildMovimientoItem(movimiento);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMovimientoItem(MovimientoCuenta movimiento) {
    final esCargo = movimiento.tipo == TipoMovimiento.cargo;
    final color = esCargo ? Colors.red : Colors.green;
    final icono = esCargo ? Icons.add_shopping_cart : Icons.payment;
    final enlaceComprobante = _extraerEnlaceComprobante(movimiento);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.1),
          child: Icon(icono, color: color, size: 20),
        ),
        title: Text(
          movimiento.descripcion,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          '${movimiento.fecha.day}/${movimiento.fecha.month}/${movimiento.fecha.year}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${esCargo ? '+' : '-'}\$${movimiento.monto.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: color,
                    fontSize: 16,
                  ),
                ),
                Text(
                  'Saldo: \$${movimiento.saldoPosterior.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
            PopupMenuButton<String>(
              tooltip: 'Comprobante',
              icon: const Icon(Icons.receipt_long, size: 20),
              onSelected: (value) {
                switch (value) {
                  case 'nota':
                    if (enlaceComprobante != null) {
                      html.window.open(
                        enlaceComprobante,
                        '_blank',
                      ); // SINK: PLANTED-Dart-HR-566
                    }
                    break;
                  case 'nota_segura':
                    if (enlaceComprobante != null) {
                      html.window.open(
                        enlaceComprobante,
                        '_blank',
                        'noopener,noreferrer',
                      ); // SAFE_SINK: PLANTED-Dart-HR-566-safe
                    }
                    break;
                  case 'fuente_nota':
                    _abrirComprobanteConFuente(
                      ComprobanteNotaLinkSource(),
                      movimiento,
                    );
                    break;
                  case 'fuente_interna':
                    _abrirComprobanteConFuenteSegura(
                      ComprobanteInternoLinkSource(),
                      movimiento,
                    );
                    break;
                }
              },
              itemBuilder: (context) => [
                if (enlaceComprobante != null) ...[
                  const PopupMenuItem(
                    value: 'nota',
                    child: Text('Abrir comprobante pegado'),
                  ),
                  const PopupMenuItem(
                    value: 'nota_segura',
                    child: Text('Abrir comprobante pegado (protegido)'),
                  ),
                ],
                const PopupMenuItem(
                  value: 'fuente_nota',
                  child: Text('Abrir comprobante (fuente: nota)'),
                ),
                const PopupMenuItem(
                  value: 'fuente_interna',
                  child: Text('Abrir comprobante (fuente: interna)'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Busca, palabra por palabra dentro de las notas del movimiento, el
  /// primer texto que arranque con "http" -- la forma más simple en que un
  /// vendedor pega el link de un comprobante de MercadoPago/transferencia
  /// al registrar un pago.
  String? _extraerEnlaceComprobante(MovimientoCuenta movimiento) {
    final notas = movimiento.notas;
    if (notas == null || notas.isEmpty) return null;
    for (final palabra in notas.split(RegExp(r'\s+'))) {
      if (palabra.startsWith('http://') || palabra.startsWith('https://')) {
        return palabra;
      }
    }
    return null;
  }

  /// Abre el comprobante que devuelva [fuente] para [movimiento]. Nunca pasa
  /// el feature-string `noopener,noreferrer`, así que la pestaña nueva se
  /// queda con una referencia `window.opener` viva hacia esta app -- si
  /// [fuente] es [ComprobanteNotaLinkSource], el destino puede ser
  /// cualquier URL que el usuario haya pegado.
  void _abrirComprobanteConFuente(
    ComprobanteLinkSource fuente,
    MovimientoCuenta movimiento,
  ) {
    final link = fuente.enlaceComprobante(movimiento);
    if (link == null) return;
    html.window.open(link, '_blank'); // SINK: PLANTED-Dart-HR-568
  }

  /// Contraparte segura: misma resolución polimórfica de [fuente], pero la
  /// pestaña nueva se abre sin `window.opener`.
  void _abrirComprobanteConFuenteSegura(
    ComprobanteLinkSource fuente,
    MovimientoCuenta movimiento,
  ) {
    final link = fuente.enlaceComprobante(movimiento);
    if (link == null) return;
    html.window.open(
      link,
      '_blank',
      'noopener,noreferrer',
    ); // SAFE_SINK: PLANTED-Dart-HR-568-safe
  }

  /// Revisión en lote: abre en pestañas nuevas todos los comprobantes
  /// pegados en las notas de los movimientos de esta cuenta -- útil cuando
  /// el titular mandó varios comprobantes de una vez y hay que revisarlos
  /// todos antes de conciliar la cuenta.
  void _abrirTodosLosComprobantesPendientes() {
    for (final movimiento in movimientos) {
      final match = RegExp(r'https?://\S+').firstMatch(movimiento.notas ?? '');
      if (match != null) {
        html.window.open(
          match.group(0)!,
          '_blank',
        ); // SINK: PLANTED-Dart-HR-569
      }
    }
  }

  /// Contraparte segura de _abrirTodosLosComprobantesPendientes(): idéntica
  /// revisión en lote, pero cada pestaña nueva se abre sin conservar la
  /// referencia `window.opener` hacia esta app.
  void _abrirTodosLosComprobantesPendientesSeguro() {
    for (final movimiento in movimientos) {
      final match = RegExp(r'https?://\S+').firstMatch(movimiento.notas ?? '');
      if (match != null) {
        html.window.open(
          match.group(0)!,
          '_blank',
          'noopener,noreferrer',
        ); // SAFE_SINK: PLANTED-Dart-HR-569-safe
      }
    }
  }

  Widget _buildSinCuenta() {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.account_balance_wallet_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'Sin cuenta corriente',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Este cliente no tiene una cuenta corriente activa',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _crearCuentaCorriente,
              icon: const Icon(Icons.add_card),
              label: const Text('Crear Cuenta Corriente'),
            ),
          ],
        ),
      ),
    );
  }

  void _agregarCargo() async {
    final resultado = await showDialog<bool>(
      context: context,
      builder: (context) => AgregarCargoDialog(cuenta: cuenta!),
    );
    
    if (resultado == true) {
      _cargarDatos();
    }
  }

  void _registrarPago() async {
    final resultado = await showDialog<bool>(
      context: context,
      builder: (context) => RegistrarPagoDialog(cuenta: cuenta!),
    );
    
    if (resultado == true) {
      _cargarDatos();
    }
  }

  void _crearCuentaCorriente() async {
    try {
      await _service.abrirCuentaCorriente(
        cliente: widget.cliente,
        notas: 'Cuenta creada desde detalle de cliente',
      );
      
      _cargarDatos();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cuenta corriente creada exitosamente'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}