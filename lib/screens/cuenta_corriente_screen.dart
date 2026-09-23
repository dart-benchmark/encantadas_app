import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/cliente.dart';
import '../services/cuenta_corriente_service.dart';
import '../widgets/add_cliente_form.dart';
import '../widgets/cuenta_detalle_dialog.dart';
import '../widgets/estadisticas_cuenta_corriente_sheet.dart';
import '../utils/whatsapp_helper.dart';

class CuentaCorrienteScreen extends StatefulWidget {
  const CuentaCorrienteScreen({super.key});

  @override
  State<CuentaCorrienteScreen> createState() => _CuentaCorrienteScreenState();
}

class _CuentaCorrienteScreenState extends State<CuentaCorrienteScreen> {
  final CuentaCorrienteService _service = CuentaCorrienteService.instance;
  final TextEditingController _searchController = TextEditingController();
  String _filtro = 'todos'; // todos, con_saldo, morosos
  
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cuenta Corriente'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.analytics),
            onPressed: _mostrarResumen,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildHeader(),
          _buildFiltros(),
          Expanded(child: _buildListaClientes()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _agregarCliente,
        tooltip: 'Agregar cliente',
        child: const Icon(Icons.person_add),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).primaryColor,
            Theme.of(context).primaryColor.withValues(alpha: 0.7),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        children: [
          // Buscador
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Buscar cliente...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (value) => setState(() {}),
          ),
          const SizedBox(height: 16),
          
          // Resumen rápido
          _buildResumenRapido(),
        ],
      ),
    );
  }

  Widget _buildResumenRapido() {
    final resumen = _service.obtenerResumenGeneral();
    
    return Row(
      children: [
        Expanded(
          child: _buildTarjetaResumen(
            'Clientes',
            '${resumen['totalClientes']}',
            Icons.people,
            Colors.blue,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildTarjetaResumen(
            'Con Saldo',
            '${resumen['cuentasConSaldo']}',
            Icons.account_balance_wallet,
            Colors.orange,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildTarjetaResumen(
            'Total Deuda',
            '\$${resumen['totalDeuda'].toStringAsFixed(0)}',
            Icons.monetization_on,
            Colors.green,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildTarjetaResumen(
            'Morosos',
            '${resumen['cuentasMorosas']}',
            Icons.warning,
            Colors.red,
          ),
        ),
      ],
    );
  }

  Widget _buildTarjetaResumen(String titulo, String valor, IconData icono, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
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

  Widget _buildFiltros() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildChipFiltro('Todos', 'todos'),
                  const SizedBox(width: 8),
                  _buildChipFiltro('Con Saldo', 'con_saldo'),
                  const SizedBox(width: 8),
                  _buildChipFiltro('Morosos', 'morosos'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChipFiltro(String label, String valor) {
    final isSelected = _filtro == valor;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _filtro = valor;
        });
      },
      selectedColor: Theme.of(context).primaryColor.withValues(alpha: 0.2),
      checkmarkColor: Theme.of(context).primaryColor,
    );
  }

  Widget _buildListaClientes() {
    return ValueListenableBuilder<Box<Cliente>>(
      valueListenable: Hive.box<Cliente>('clientes_cuenta').listenable(),
      builder: (context, box, _) {
        var clientes = _service.obtenerClientes();
        
        // Aplicar búsqueda
        if (_searchController.text.isNotEmpty) {
          clientes = _service.buscarClientes(_searchController.text);
        }
        
        // Aplicar filtros
        clientes = _aplicarFiltros(clientes);
        
        if (clientes.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.people_outline,
                  size: 64,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  _searchController.text.isNotEmpty || _filtro != 'todos'
                      ? 'No se encontraron clientes'
                      : 'No hay clientes registrados',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _searchController.text.isNotEmpty || _filtro != 'todos'
                      ? 'Intenta cambiar los filtros o búsqueda'
                      : 'Agrega tu primer cliente con el botón +',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[500],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }
        
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: clientes.length,
          itemBuilder: (context, index) {
            final cliente = clientes[index];
            return _buildClienteCard(cliente);
          },
        );
      },
    );
  }

  List<Cliente> _aplicarFiltros(List<Cliente> clientes) {
    switch (_filtro) {
      case 'con_saldo':
        return clientes.where((cliente) {
          final cuenta = _service.obtenerCuentaPorCliente(cliente);
          return cuenta != null && cuenta.saldoActual > 0;
        }).toList();
      
      case 'morosos':
        final cuentasMorosas = _service.obtenerCuentasMorosas();
        final clientesMorosos = <Cliente>[];
        for (final cuenta in cuentasMorosas) {
          final cliente = _obtenerClientePorId(cuenta.clienteId);
          if (cliente != null) clientesMorosos.add(cliente);
        }
        return clientesMorosos;
      
      default:
        return clientes;
    }
  }

  Cliente? _obtenerClientePorId(String clienteId) {
    try {
      final key = int.parse(clienteId);
      return Hive.box<Cliente>('clientes_cuenta').get(key);
    } catch (e) {
      return null;
    }
  }

  Widget _buildClienteCard(Cliente cliente) {
    final cuenta = _service.obtenerCuentaPorCliente(cliente);
    final tieneCuenta = cuenta != null;
    final saldo = cuenta?.saldoActual ?? 0.0;
    final esMoroso = tieneCuenta && saldo > 0 && cuenta.esMorosa;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: esMoroso 
              ? Colors.red.withValues(alpha: 0.1)
              : saldo > 0 
                  ? Colors.orange.withValues(alpha: 0.1)
                  : Colors.green.withValues(alpha: 0.1),
          child: Icon(
            esMoroso ? Icons.warning : Icons.person,
            color: esMoroso ? Colors.red : saldo > 0 ? Colors.orange : Colors.green,
          ),
        ),
        title: Text(
          cliente.nombreCompleto,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (cliente.telefono != null) 
              Text('📞 ${cliente.telefono}'),
            if (tieneCuenta)
              Text(
                saldo > 0 
                    ? 'Saldo: \$${saldo.toStringAsFixed(2)}'
                    : 'Sin saldo pendiente',
                style: TextStyle(
                  color: saldo > 0 ? Colors.red : Colors.green,
                  fontWeight: FontWeight.w500,
                ),
              )
            else
              const Text(
                'Sin cuenta corriente',
                style: TextStyle(color: Colors.grey),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (WhatsAppHelper.canUseWhatsApp(cliente.telefono))
              IconButton(
                icon: const Icon(Icons.message, color: Color(0xFF25D366)),
                onPressed: () => _contactarPorWhatsApp(cliente),
                tooltip: 'Contactar por WhatsApp',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            if (esMoroso)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'MOROSO',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 16),
              padding: EdgeInsets.zero,
              onSelected: (value) {
                if (value == 'edit') {
                  _editarCliente(cliente);
                } else if (value == 'delete') {
                  _eliminarCliente(cliente);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem<String>(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit, color: Colors.blue, size: 18),
                      SizedBox(width: 8),
                      Text('Editar'),
                    ],
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, color: Colors.red, size: 18),
                      SizedBox(width: 8),
                      Text('Eliminar'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        onTap: () => _verDetalleCliente(cliente),
      ),
    );
  }

  void _agregarCliente() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const AddClienteForm(),
    );
  }

  void _verDetalleCliente(Cliente cliente) {
    showDialog(
      context: context,
      builder: (context) => CuentaDetalleDialog(cliente: cliente),
    );
  }

  void _contactarPorWhatsApp(Cliente cliente) {
    final cuenta = _service.obtenerCuentaPorCliente(cliente);
    final saldo = cuenta?.saldoActual ?? 0.0;
    
    String mensaje = 'Hola ${cliente.nombre}! ';
    
    if (saldo > 0) {
      mensaje += 'Te contacto desde *Encantadas* para recordarte que tienes un saldo pendiente de *\$${saldo.toStringAsFixed(2)}* en tu cuenta corriente. ';
      
      if (cuenta!.esMorosa) {
        mensaje += 'Por favor, cuando puedas, ponte al día con el pago. ';
      }
      
      mensaje += '¿Cuándo podrías pasar a abonar? ¡Gracias! 💕';
    } else {
      mensaje += 'Te contacto desde *Encantadas*. ¡Espero que estés bien! 💕';
    }
    
    WhatsAppHelper.openWhatsApp(context, cliente.telefono!, message: mensaje);
  }

  void _editarCliente(Cliente cliente) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AddClienteForm(cliente: cliente),
    );
  }

  Future<void> _eliminarCliente(Cliente cliente) async {
    final cuenta = _service.obtenerCuentaPorCliente(cliente);
    final tieneSaldo = cuenta != null && cuenta.saldoActual > 0;
    
    String mensaje = '¿Eliminar a ${cliente.nombreCompleto}?\n\n';
    if (tieneSaldo) {
      mensaje += '⚠️ ATENCIÓN: Este cliente tiene un saldo pendiente de \$${cuenta.saldoActual.toStringAsFixed(2)}.\n\n';
      mensaje += 'Al eliminarlo se perderá toda la información de su cuenta corriente y movimientos.\n\n';
    }
    mensaje += 'Esta acción no se puede deshacer.';
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 8),
            Text('Eliminar Cliente'),
          ],
        ),
        content: Text(mensaje),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (tieneSaldo) {
        final autorizado = await _solicitarPinAdministrador();
        if (!autorizado) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('PIN incorrecto, no se eliminó el cliente'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
      }
      try {
        await _service.eliminarCliente(cliente);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 8),
                  Text('${cliente.nombreCompleto} eliminado exitosamente'),
                ],
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.error, color: Colors.white),
                  const SizedBox(width: 8),
                  Text('Error al eliminar: $e'),
                ],
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  /// Pide el PIN de administrador antes de eliminar un cliente que todavía
  /// tiene saldo pendiente en su cuenta corriente (acción destructiva sobre
  /// datos financieros). Ver `CuentaCorrienteService.verificarPinAdministrador`.
  Future<bool> _solicitarPinAdministrador() async {
    final pinController = TextEditingController();
    final autorizado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('PIN de administrador requerido'),
        content: TextField(
          controller: pinController,
          obscureText: true,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'PIN'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              final pin = pinController.text;
              // Se acepta si cualquiera de las dos variantes coincide, para
              // no cortar el acceso de un dispositivo que todavía solo
              // tiene configurado el PIN legacy mientras se migra al v2.
              final ok = _service.verificarPinAdministrador(pin);
              final okSeguro = _service.verificarPinAdministradorSeguro(pin);
              Navigator.pop(context, ok || okSeguro);
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    return autorizado ?? false;
  }

  void _mostrarResumen() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => EstadisticasCuentaCorrienteSheet(service: _service),
    );
  }
}