import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/provider.dart';
import '../utils/whatsapp_helper.dart';
import '../widgets/provider_statistics_card.dart';

class ProvidersScreen extends StatefulWidget {
  const ProvidersScreen({super.key});

  @override
  State<ProvidersScreen> createState() => _ProvidersScreenState();
}

class _ProvidersScreenState extends State<ProvidersScreen> with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _sortByName = true; // true = by name, false = by rubro
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _toggleSort() {
    setState(() {
      _sortByName = !_sortByName;
    });
  }

  List<Provider> _filterAndSortProviders(List<Provider> providers) {
    // Filter by search query
    List<Provider> filteredProviders = providers;
    if (_searchQuery.isNotEmpty) {
      filteredProviders = providers.where((provider) {
        final searchLower = _searchQuery.toLowerCase();
        return provider.name.toLowerCase().contains(searchLower) ||
               provider.rubro.toLowerCase().contains(searchLower);
      }).toList();
    }

    // Sort providers
    if (_sortByName) {
      filteredProviders.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } else {
      filteredProviders.sort((a, b) => a.rubro.toLowerCase().compareTo(b.rubro.toLowerCase()));
    }

    return filteredProviders;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Proveedores'),
        actions: [
          if (_tabController.index == 0) // Solo mostrar en la pestaña de lista
            IconButton(
              icon: Icon(_sortByName ? Icons.sort_by_alpha : Icons.category),
              tooltip: _sortByName ? 'Ordenar por rubro' : 'Ordenar por nombre',
              onPressed: _toggleSort,
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(
              icon: Icon(Icons.list),
              text: 'Lista',
            ),
            Tab(
              icon: Icon(Icons.analytics),
              text: 'Estadísticas',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Pestaña de Lista
          ValueListenableBuilder<Box<Provider>>(
            valueListenable: Hive.box<Provider>('providers').listenable(),
            builder: (context, box, _) {
              final allProviders = box.values.toList().cast<Provider>();
              final filteredProviders = _filterAndSortProviders(allProviders);

              return Column(
                children: [
                  // Search bar
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Buscar por nombre o rubro...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {
                                    _searchQuery = '';
                                  });
                                },
                              )
                            : null,
                        border: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                      ),
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value;
                        });
                      },
                    ),
                  ),
                  
                  // Providers list
                  Expanded(
                    child: _buildProvidersList(allProviders, filteredProviders),
                  ),
                ],
              );
            },
          ),
          
          // Pestaña de Estadísticas
          const SingleChildScrollView(
            child: ProviderStatisticsCard(),
          ),
        ],
      ),
    );
  }

  Widget _buildProvidersList(List<Provider> allProviders, List<Provider> filteredProviders) {
    if (allProviders.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.business,
              size: 80,
              color: Colors.grey,
            ),
            SizedBox(height: 16),
            Text(
              'Sin proveedores por el momento',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Presiona el botón + para agregar tu primer proveedor',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (filteredProviders.isEmpty && _searchQuery.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.search_off,
              size: 80,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            const Text(
              'Sin resultados',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'No se encontraron proveedores que coincidan con "$_searchQuery"',
              style: const TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
      itemCount: filteredProviders.length,
      itemBuilder: (context, index) {
        final provider = filteredProviders[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ProviderCard(provider: provider),
        );
      },
    );
  }
}

class ProviderCard extends StatelessWidget {
  final Provider provider;

  const ProviderCard({
    super.key,
    required this.provider,
  });

  Future<void> _deleteProvider(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('¿Eliminar este proveedor?'),
          content: Text(
            'Se eliminará "${provider.name}" permanentemente. Esta acción no se puede deshacer.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
              ),
              child: const Text('Eliminar'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      try {
        await provider.delete();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.delete, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Proveedor eliminado'),
                  ),
                ],
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al eliminar proveedor: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Provider name row with menu
            Row(
              children: [
                Expanded(
                  child: Text(
                    provider.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                // Three-dot menu
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert,
                    color: theme.iconTheme.color?.withValues(alpha: 0.7),
                    size: 20,
                  ),
                  onSelected: (value) {
                    if (value == 'delete') {
                      _deleteProvider(context);
                    }
                  },
                  itemBuilder: (BuildContext context) => [
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
            
            const SizedBox(height: 8),
            // Rubro info
            Row(
              children: [
                Icon(
                  Icons.category,
                  size: 16,
                  color: theme.iconTheme.color?.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    provider.rubroWithEmoji,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.8),
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            
            if (provider.contact != null && provider.contact!.isNotEmpty) ...[
              const SizedBox(height: 8),
              // Contact info with WhatsApp button
              Row(
                children: [
                  Icon(
                    Icons.contact_phone,
                    size: 16,
                    color: theme.iconTheme.color?.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      provider.formattedContact,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.8),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (provider.canUseWhatsApp) ...[
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () async {
                        await WhatsAppHelper.openWhatsApp(
                          context,
                          provider.contact!,
                          message: 'Hola ${provider.name}, me contacto desde la app Encantadas.',
                        );
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF25D366).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFF25D366).withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Icon(
                          Icons.chat,
                          size: 16,
                          color: Color(0xFF25D366),
                        ),
                      ),
                    ),
                  ],
                  // Algunos proveedores dan un link (catálogo, Instagram) en
                  // vez de un teléfono -- se ofrece un acceso directo para
                  // visitarlo en una pestaña nueva.
                  if (provider.hasWebsiteLink) ...[
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () {
                        html.window.open(
                          provider.websiteLink!,
                          '_blank',
                        ); // SINK: PLANTED-Dart-HR-565
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.blue.withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Icon(
                          Icons.open_in_new,
                          size: 16,
                          color: Colors.blue,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}