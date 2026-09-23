import 'package:flutter/material.dart';
import '../models/cuenta_corriente.dart';
import '../services/cuenta_corriente_service.dart';

class AgregarCargoDialog extends StatefulWidget {
  final CuentaCorriente cuenta;

  const AgregarCargoDialog({
    super.key,
    required this.cuenta,
  });

  @override
  State<AgregarCargoDialog> createState() => _AgregarCargoDialogState();
}

class _AgregarCargoDialogState extends State<AgregarCargoDialog> {
  final _formKey = GlobalKey<FormState>();
  final _montoController = TextEditingController();
  final _descripcionController = TextEditingController();
  final _referenciaController = TextEditingController();
  final _notasController = TextEditingController();

  bool _isLoading = false;

  @override
  void dispose() {
    _montoController.dispose();
    _descripcionController.dispose();
    _referenciaController.dispose();
    _notasController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.add_shopping_cart, color: Colors.orange),
          const SizedBox(width: 8),
          const Text('Agregar Cargo'),
        ],
      ),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.8,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Info de saldo actual
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info, color: Colors.blue, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Saldo actual: \$${widget.cuenta.saldoActual.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 20),
                
                // Monto
                TextFormField(
                  controller: _montoController,
                  decoration: const InputDecoration(
                    labelText: 'Monto *',
                    prefixIcon: Icon(Icons.monetization_on),
                    border: OutlineInputBorder(),
                    prefixText: '\$ ',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'El monto es obligatorio';
                    }
                    final monto = double.tryParse(value);
                    if (monto == null || monto <= 0) {
                      return 'Ingrese un monto válido';
                    }
                    return null;
                  },
                  autofocus: true,
                ),
                
                const SizedBox(height: 16),
                
                // Descripción
                TextFormField(
                  controller: _descripcionController,
                  decoration: const InputDecoration(
                    labelText: 'Descripción *',
                    prefixIcon: Icon(Icons.description),
                    border: OutlineInputBorder(),
                    hintText: 'Ej: Compra de ropa, servicios, etc.',
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'La descripción es obligatoria';
                    }
                    return null;
                  },
                ),
                
                const SizedBox(height: 16),
                
                // Referencia
                TextFormField(
                  controller: _referenciaController,
                  decoration: const InputDecoration(
                    labelText: 'Referencia (opcional)',
                    prefixIcon: Icon(Icons.receipt),
                    border: OutlineInputBorder(),
                    hintText: 'Ej: Factura #123, Venta QR, etc.',
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Notas
                TextFormField(
                  controller: _notasController,
                  decoration: const InputDecoration(
                    labelText: 'Notas adicionales',
                    prefixIcon: Icon(Icons.note),
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                
                const SizedBox(height: 16),
                
                // Preview del nuevo saldo
                if (_montoController.text.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.trending_up, color: Colors.orange, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Nuevo saldo: \$${_calcularNuevoSaldo().toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            color: Colors.orange,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _guardarCargo,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Agregar Cargo'),
        ),
      ],
    );
  }

  double _calcularNuevoSaldo() {
    final monto = double.tryParse(_montoController.text) ?? 0.0;
    return widget.cuenta.saldoActual + monto;
  }

  Future<void> _guardarCargo() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final service = CuentaCorrienteService.instance;
      final monto = double.parse(_montoController.text);

      if (service.requiereAutorizacionGerencial(monto)) {
        final autorizado = await _solicitarCodigoAutorizacionGerencial(service);
        if (!autorizado) {
          setState(() {
            _isLoading = false;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Código de autorización incorrecto'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
      }

      await service.agregarCargo(
        cuenta: widget.cuenta,
        monto: monto,
        descripcion: _descripcionController.text.trim(),
        referencia: _referenciaController.text.isEmpty 
            ? null 
            : _referenciaController.text.trim(),
        notas: _notasController.text.isEmpty 
            ? null 
            : _notasController.text.trim(),
      );

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Text('Cargo de \$${monto.toStringAsFixed(2)} agregado'),
              ],
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 8),
                Text('Error: ${e.toString()}'),
              ],
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Pide el código de autorización gerencial para cargos por encima del
  /// umbral (ver `CuentaCorrienteService.requiereAutorizacionGerencial`) --
  /// pensado para frenar un cargo manual inflado por error o de mala fe.
  Future<bool> _solicitarCodigoAutorizacionGerencial(
      CuentaCorrienteService service) async {
    final codigoController = TextEditingController();
    final autorizado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Autorización gerencial requerida'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Los cargos por encima de \$${CuentaCorrienteService.umbralAutorizacionGerencial.toStringAsFixed(2)} '
              'requieren un código de autorización del dueño o un encargado.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: codigoController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Código de autorización'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              final codigo = codigoController.text;
              // Se acepta si cualquiera de las dos variantes coincide, para
              // no cortar el acceso mientras se migra al esquema v2.
              final ok = service.verificarAutorizacionCargoGrande(codigo);
              final okSeguro = service.verificarAutorizacionCargoGrandeSeguro(codigo);
              Navigator.pop(context, ok || okSeguro);
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    return autorizado ?? false;
  }
}