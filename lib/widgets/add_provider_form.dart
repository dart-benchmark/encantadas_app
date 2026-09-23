import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/provider.dart';

class AddProviderForm extends StatefulWidget {
  const AddProviderForm({super.key});

  @override
  State<AddProviderForm> createState() => _AddProviderFormState();
}

class _AddProviderFormState extends State<AddProviderForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _contactController = TextEditingController();
  String? _selectedRubro;
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _contactController.dispose();
    super.dispose();
  }

  // Contraparte segura de la apertura directa que hace ProviderCard
  // (providers_screen.dart): antes de guardar, el usuario puede "probar" el
  // link que acaba de tipear en el campo Contacto -- la pestaña nueva se
  // abre sin dejarle una referencia window.opener hacia esta app.
  bool _contactoPareceEnlace(String texto) {
    final t = texto.trim();
    return t.startsWith('http://') || t.startsWith('https://');
  }

  void _probarEnlaceContacto() {
    final texto = _contactController.text;
    if (!_contactoPareceEnlace(texto)) return;
    html.window.open(
      texto.trim(),
      '_blank',
      'noopener,noreferrer',
    ); // SAFE_SINK: PLANTED-Dart-HR-565-safe
  }

  Future<void> _saveProvider() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        final providersBox = Hive.box<Provider>('providers');
        
        final provider = Provider(
          name: _nameController.text.trim(),
          contact: _contactController.text.trim().isEmpty 
              ? null 
              : _contactController.text.trim(),
          rubro: _selectedRubro!,
          createdAt: DateTime.now(),
        );

        await providersBox.add(provider);

        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.business, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Proveedor "${provider.name}" agregado'),
                  ),
                ],
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al agregar proveedor: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    const Icon(
                      Icons.business,
                      color: Colors.blue,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Nuevo Proveedor',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Provider name
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del proveedor',
                    hintText: 'Ej: Distribuidora ABC',
                    prefixIcon: Icon(Icons.business),
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.words,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Por favor ingrese el nombre del proveedor';
                    }
                    if (value.trim().length < 2) {
                      return 'El nombre debe tener al menos 2 caracteres';
                    }
                    return null;
                  },
                  onFieldSubmitted: (_) => _saveProvider(),
                ),
                const SizedBox(height: 16),

                // Rubro dropdown
                DropdownButtonFormField<String>(
                  value: _selectedRubro,
                  decoration: const InputDecoration(
                    labelText: 'Rubro',
                    hintText: 'Seleccione el rubro del proveedor',
                    prefixIcon: Icon(Icons.category),
                    border: OutlineInputBorder(),
                  ),
                  items: Provider.availableRubros.map((String rubro) {
                    String emoji;
                    switch (rubro) {
                      case 'Ropa':
                        emoji = '👗';
                        break;
                      case 'Bijouterie':
                        emoji = '💎';
                        break;
                      case 'Pedicura':
                      case 'Manicura':
                        emoji = '💅';
                        break;
                      case 'Belleza':
                        emoji = '✨';
                        break;
                      case 'Accesorios':
                        emoji = '👜';
                        break;
                      case 'Calzado':
                        emoji = '👠';
                        break;
                      case 'Cosméticos':
                        emoji = '💄';
                        break;
                      case 'Herramientas':
                        emoji = '🔧';
                        break;
                      default:
                        emoji = '📦';
                    }
                    return DropdownMenuItem<String>(
                      value: rubro,
                      child: Text('$emoji $rubro'),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    setState(() {
                      _selectedRubro = newValue;
                    });
                  },
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Por favor seleccione un rubro';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Contact (optional)
                TextFormField(
                  controller: _contactController,
                  decoration: const InputDecoration(
                    labelText: 'Contacto (opcional)',
                    hintText: 'Teléfono, email, WhatsApp...',
                    prefixIcon: Icon(Icons.contact_phone),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    // Contact is optional, so no validation needed
                    return null;
                  },
                  onFieldSubmitted: (_) => _saveProvider(),
                ),
                AnimatedBuilder(
                  animation: _contactController,
                  builder: (context, _) {
                    if (!_contactoPareceEnlace(_contactController.text)) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: _probarEnlaceContacto,
                          icon: const Icon(Icons.open_in_new, size: 16),
                          label: const Text('Probar enlace'),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),

                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isLoading ? null : () {
                          Navigator.of(context).pop();
                        },
                        child: const Text('Cancelar'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _saveProvider,
                        child: _isLoading
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Text('Guardar'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}