import 'package:flutter/material.dart';
import '../models/cuenta_corriente.dart';
import '../services/cuenta_corriente_service.dart';

class RegistrarPagoDialog extends StatefulWidget {
  final CuentaCorriente cuenta;

  const RegistrarPagoDialog({
    super.key,
    required this.cuenta,
  });

  @override
  State<RegistrarPagoDialog> createState() => _RegistrarPagoDialogState();
}

class _RegistrarPagoDialogState extends State<RegistrarPagoDialog> {
  final _formKey = GlobalKey<FormState>();
  final _montoController = TextEditingController();
  final _descripcionController = TextEditingController();
  final _referenciaController = TextEditingController();
  final _notasController = TextEditingController();

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _descripcionController.text = 'Pago recibido';
  }

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
          Icon(Icons.payment, color: Colors.green),
          const SizedBox(width: 8),
          const Text('Registrar Pago'),
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
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.account_balance_wallet, color: Colors.red, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Saldo pendiente: \$${widget.cuenta.saldoActual.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 20),
                
                // Botones de monto rápido
                Text(
                  'Montos rápidos:',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 8),
                
                Row(
                  children: [
                    _buildBotonMontoRapido('Todo', widget.cuenta.saldoActual),
                    const SizedBox(width: 8),
                    _buildBotonMontoRapido('Mitad', widget.cuenta.saldoActual / 2),
                    const SizedBox(width: 8),
                    _buildBotonMontoRapido('\$1000', 1000),
                    const SizedBox(width: 8),
                    _buildBotonMontoRapido('\$500', 500),
                  ],
                ),
                
                const SizedBox(height: 16),
                
                // Monto
                TextFormField(
                  controller: _montoController,
                  decoration: const InputDecoration(
                    labelText: 'Monto del pago *',
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
                    if (monto > widget.cuenta.saldoActual) {
                      return 'El monto no puede ser mayor al saldo pendiente';
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
                    labelText: 'Descripción',
                    prefixIcon: Icon(Icons.description),
                    border: OutlineInputBorder(),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Referencia
                TextFormField(
                  controller: _referenciaController,
                  decoration: const InputDecoration(
                    labelText: 'Referencia (opcional)',
                    prefixIcon: Icon(Icons.receipt),
                    border: OutlineInputBorder(),
                    hintText: 'Ej: Recibo #123, Transferencia, etc.',
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
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.trending_down, color: Colors.green, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Nuevo saldo: \$${_calcularNuevoSaldo().toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                  color: Colors.green,
                                ),
                              ),
                              if (_calcularNuevoSaldo() == 0)
                                const Text(
                                  '¡Cuenta saldada!',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.green,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                            ],
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
          onPressed: _isLoading ? null : _guardarPago,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Registrar Pago'),
        ),
      ],
    );
  }

  Widget _buildBotonMontoRapido(String label, double monto) {
    return Expanded(
      child: OutlinedButton(
        onPressed: monto <= widget.cuenta.saldoActual 
            ? () {
                _montoController.text = monto.toStringAsFixed(2);
                setState(() {});
              }
            : null,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }

  double _calcularNuevoSaldo() {
    final monto = double.tryParse(_montoController.text) ?? 0.0;
    return widget.cuenta.saldoActual - monto;
  }

  Future<void> _guardarPago() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final service = CuentaCorrienteService.instance;
      final monto = double.parse(_montoController.text);
      
      await service.registrarPago(
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
        
        final nuevoSaldo = widget.cuenta.saldoActual - monto;
        final mensaje = nuevoSaldo == 0 
            ? 'Pago registrado. ¡Cuenta saldada!'
            : 'Pago de \$${monto.toStringAsFixed(2)} registrado';
            
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Text(mensaje),
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
}