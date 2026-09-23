import 'package:flutter/material.dart';
import '../services/cuenta_corriente_service.dart';
import '../models/cliente.dart';

class AddClienteForm extends StatefulWidget {
  final Cliente? cliente;
  
  const AddClienteForm({super.key, this.cliente});

  @override
  State<AddClienteForm> createState() => _AddClienteFormState();
}

class _AddClienteFormState extends State<AddClienteForm> {
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _apellidoController = TextEditingController();
  final _telefonoController = TextEditingController();
  final _direccionController = TextEditingController();
  final _emailController = TextEditingController();
  final _documentoController = TextEditingController();
  final _notasController = TextEditingController();
  final _limiteCreditoController = TextEditingController();

  bool _crearCuentaCorriente = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.cliente != null) {
      _nombreController.text = widget.cliente!.nombre;
      _apellidoController.text = widget.cliente!.apellido;
      _telefonoController.text = widget.cliente!.telefono ?? '';
      _direccionController.text = widget.cliente!.direccion ?? '';
      _emailController.text = widget.cliente!.email ?? '';
      _documentoController.text = widget.cliente!.documento ?? '';
      _notasController.text = widget.cliente!.notas ?? '';
      
      // Para edición, no mostrar la opción de crear cuenta corriente
      _crearCuentaCorriente = false;
    }
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _apellidoController.dispose();
    _telefonoController.dispose();
    _direccionController.dispose();
    _emailController.dispose();
    _documentoController.dispose();
    _notasController.dispose();
    _limiteCreditoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
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
              color: Theme.of(context).primaryColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                const Icon(Icons.person_add, color: Colors.white, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.cliente != null ? 'Editar Cliente' : 'Agregar Cliente',
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
          
          // Form
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Información básica
                    _buildSectionTitle('Información Básica'),
                    const SizedBox(height: 16),
                    
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _nombreController,
                            decoration: const InputDecoration(
                              labelText: 'Nombre *',
                              prefixIcon: Icon(Icons.person),
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'El nombre es obligatorio';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _apellidoController,
                            decoration: const InputDecoration(
                              labelText: 'Apellido *',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'El apellido es obligatorio';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 16),
                    
                    TextFormField(
                      controller: _telefonoController,
                      decoration: const InputDecoration(
                        labelText: 'Teléfono',
                        prefixIcon: Icon(Icons.phone),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                    
                    const SizedBox(height: 16),
                    
                    TextFormField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    
                    const SizedBox(height: 16),
                    
                    TextFormField(
                      controller: _documentoController,
                      decoration: const InputDecoration(
                        labelText: 'DNI/Documento',
                        prefixIcon: Icon(Icons.badge),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    
                    const SizedBox(height: 16),
                    
                    TextFormField(
                      controller: _direccionController,
                      decoration: const InputDecoration(
                        labelText: 'Dirección',
                        prefixIcon: Icon(Icons.location_on),
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Cuenta corriente
                    _buildSectionTitle('Cuenta Corriente'),
                    const SizedBox(height: 16),
                    
                    if (widget.cliente == null)
                      SwitchListTile(
                        title: const Text('Crear cuenta corriente'),
                        subtitle: const Text('Permitir compras a crédito'),
                        value: _crearCuentaCorriente,
                        onChanged: (value) {
                          setState(() {
                            _crearCuentaCorriente = value;
                          });
                        },
                      ),
                    
                    if (widget.cliente == null && _crearCuentaCorriente) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _limiteCreditoController,
                        decoration: const InputDecoration(
                          labelText: 'Límite de crédito (opcional)',
                          prefixIcon: Icon(Icons.monetization_on),
                          border: OutlineInputBorder(),
                          helperText: 'Dejar vacío para sin límite',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ],
                    
                    const SizedBox(height: 16),
                    
                    TextFormField(
                      controller: _notasController,
                      decoration: const InputDecoration(
                        labelText: 'Notas adicionales',
                        prefixIcon: Icon(Icons.note),
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // Botones
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _isLoading ? null : () => Navigator.pop(context),
                            child: const Text('Cancelar'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _guardarCliente,
                            child: _isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : Text(widget.cliente != null ? 'Actualizar' : 'Guardar'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Theme.of(context).primaryColor,
      ),
    );
  }

  Future<void> _guardarCliente() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final service = CuentaCorrienteService.instance;
      
      if (widget.cliente != null) {
        // Editar cliente existente
        await service.editarCliente(
          widget.cliente!,
          nombre: _nombreController.text.trim(),
          apellido: _apellidoController.text.trim(),
          telefono: _telefonoController.text.isEmpty ? null : _telefonoController.text.trim(),
          direccion: _direccionController.text.isEmpty ? null : _direccionController.text.trim(),
          email: _emailController.text.isEmpty ? null : _emailController.text.trim(),
          documento: _documentoController.text.isEmpty ? null : _documentoController.text.trim(),
          notas: _notasController.text.isEmpty ? null : _notasController.text.trim(),
        );

        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 8),
                  Text('${widget.cliente!.nombreCompleto} editado exitosamente'),
                ],
              ),
              backgroundColor: Colors.blue,
            ),
          );
        }
      } else {
        // Crear cliente nuevo
        final cliente = await service.crearCliente(
          nombre: _nombreController.text.trim(),
          apellido: _apellidoController.text.trim(),
          telefono: _telefonoController.text.isEmpty ? null : _telefonoController.text.trim(),
          direccion: _direccionController.text.isEmpty ? null : _direccionController.text.trim(),
          email: _emailController.text.isEmpty ? null : _emailController.text.trim(),
          documento: _documentoController.text.isEmpty ? null : _documentoController.text.trim(),
          notas: _notasController.text.isEmpty ? null : _notasController.text.trim(),
        );

        // Crear cuenta corriente si se solicitó
        if (_crearCuentaCorriente) {
          final limiteCredito = _limiteCreditoController.text.isEmpty 
              ? 0.0 
              : double.tryParse(_limiteCreditoController.text) ?? 0.0;
              
          await service.abrirCuentaCorriente(
            cliente: cliente,
            limiteCredito: limiteCredito,
            notas: 'Cuenta creada junto con el cliente',
          );
        }

        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 8),
                  Text('Cliente ${cliente.nombreCompleto} creado exitosamente'),
                ],
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
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