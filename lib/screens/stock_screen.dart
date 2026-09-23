import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/product.dart';
import '../models/provider.dart';
import '../services/pocketbase_sync_service.dart';
import '../utils/text_search.dart';
import '../widgets/qr_code_dialog.dart';
import '../widgets/edit_product_form.dart';
import 'providers_screen.dart';

enum StockFilter { all, inStock, lowStock, outOfStock }

class StockScreen extends StatefulWidget {
  const StockScreen({super.key});

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  String _searchQuery = '';
  ProductCategory? _selectedCategory;
  StockFilter _stockFilter = StockFilter.all;
  final Set<String> _selectedTags = <String>{};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _searchQuery = _searchController.text);
    });
  }

  void _clearAllFilters() {
    setState(() {
      _searchController.clear();
      _searchQuery = '';
      _selectedCategory = null;
      _stockFilter = StockFilter.all;
      _selectedTags.clear();
    });
  }

  bool get _hasActiveFilters =>
      _searchQuery.isNotEmpty ||
      _selectedCategory != null ||
      _stockFilter != StockFilter.all ||
      _selectedTags.isNotEmpty;

  List<Product> _applyFilters(List<Product> products) {
    return products.where((p) {
      if (_searchQuery.isNotEmpty &&
          !matchesQuery(_searchQuery, [p.name, p.code])) {
        return false;
      }
      if (_selectedCategory != null && p.category != _selectedCategory) {
        return false;
      }
      switch (_stockFilter) {
        case StockFilter.all:
          break;
        case StockFilter.inStock:
          if (p.quantity <= 5) return false;
          break;
        case StockFilter.lowStock:
          if (p.quantity == 0 || p.quantity > 5) return false;
          break;
        case StockFilter.outOfStock:
          if (p.quantity != 0) return false;
          break;
      }
      if (_selectedTags.isNotEmpty) {
        final productTags = p.tagsNormalized.toSet();
        if (!_selectedTags.every(productTags.contains)) return false;
      }
      return true;
    }).toList();
  }

  Future<void> _showTagsPicker(List<String> allTags) async {
    final selected = Set<String>.from(_selectedTags);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheetState) {
          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.7,
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.local_offer, color: Colors.purple),
                    const SizedBox(width: 8),
                    const Text(
                      'Filtrar por tags',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    if (selected.isNotEmpty)
                      TextButton(
                        onPressed: () => setSheetState(() => selected.clear()),
                        child: const Text('Limpiar'),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Producto debe tener TODOS los tags seleccionados.',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
                const SizedBox(height: 16),
                if (allTags.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        'Aún no hay tags creados. Agregá tags al cargar/editar productos.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: allTags.map((tag) {
                          final isOn = selected.contains(tag);
                          return FilterChip(
                            label: Text(tag),
                            selected: isOn,
                            onSelected: (v) => setSheetState(() {
                              v ? selected.add(tag) : selected.remove(tag);
                            }),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _selectedTags
                          ..clear()
                          ..addAll(selected);
                      });
                      Navigator.of(ctx).pop();
                    },
                    child: Text('Aplicar (${selected.length})'),
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock'),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const ProvidersScreen(),
                ),
              );
            },
            icon: const Icon(Icons.business),
            tooltip: 'Proveedores',
          ),
        ],
      ),
      body: ValueListenableBuilder<Box<Product>>(
        valueListenable: Hive.box<Product>('products').listenable(),
        builder: (context, box, _) {
          final allProducts = box.values.toList().cast<Product>();
          final allTags = <String>{};
          for (final p in allProducts) {
            allTags.addAll(p.tagsNormalized);
          }
          final sortedTags = allTags.toList()..sort();

          allProducts.sort((a, b) {
            final catCmp = a.category.index.compareTo(b.category.index);
            if (catCmp != 0) return catCmp;
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          });

          final filtered = _applyFilters(allProducts);
          final isEmpty = allProducts.isEmpty;
          final noResults = !isEmpty && filtered.isEmpty;

          return Column(
            children: [
              _buildFilterBar(allProducts.length, filtered.length, sortedTags),
              Expanded(
                child: isEmpty
                    ? _emptyState()
                    : noResults
                        ? _noResultsState()
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final product = filtered[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: ProductCard(product: product),
                              );
                            },
                          ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFilterBar(int total, int matching, List<String> allTags) {
    final theme = Theme.of(context);
    return Material(
      elevation: 1,
      child: Container(
        color: theme.scaffoldBackgroundColor,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Buscar por nombre o código...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _categoryChip(label: 'Todas', value: null),
                  ...ProductCategory.values.map(
                    (c) => _categoryChip(label: c.displayName, value: c),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                _stockMenuButton(),
                const SizedBox(width: 8),
                _tagsButton(allTags),
                const Spacer(),
                Text(
                  matching == total
                      ? '$total productos'
                      : '$matching de $total',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_hasActiveFilters)
                  IconButton(
                    icon: const Icon(Icons.filter_alt_off, size: 20),
                    onPressed: _clearAllFilters,
                    tooltip: 'Limpiar filtros',
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _categoryChip({required String label, required ProductCategory? value}) {
    final isSelected = _selectedCategory == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) => setState(() => _selectedCategory = isSelected ? null : value),
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _stockMenuButton() {
    return PopupMenuButton<StockFilter>(
      tooltip: 'Filtrar por estado de stock',
      onSelected: (v) => setState(() => _stockFilter = v),
      itemBuilder: (_) => const [
        PopupMenuItem(value: StockFilter.all, child: Text('Todos')),
        PopupMenuItem(value: StockFilter.inStock, child: Text('En stock')),
        PopupMenuItem(value: StockFilter.lowStock, child: Text('Stock bajo (≤5)')),
        PopupMenuItem(value: StockFilter.outOfStock, child: Text('Sin stock')),
      ],
      child: Chip(
        avatar: const Icon(Icons.inventory_2_outlined, size: 16),
        label: Text(_stockFilterLabel(_stockFilter)),
        backgroundColor: _stockFilter == StockFilter.all
            ? null
            : Colors.blue.withValues(alpha: 0.12),
        side: _stockFilter == StockFilter.all
            ? null
            : BorderSide(color: Colors.blue.withValues(alpha: 0.4)),
      ),
    );
  }

  String _stockFilterLabel(StockFilter f) {
    switch (f) {
      case StockFilter.all:
        return 'Stock: todos';
      case StockFilter.inStock:
        return 'En stock';
      case StockFilter.lowStock:
        return 'Stock bajo';
      case StockFilter.outOfStock:
        return 'Sin stock';
    }
  }

  Widget _tagsButton(List<String> allTags) {
    final count = _selectedTags.length;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => _showTagsPicker(allTags),
      child: Chip(
        avatar: const Icon(Icons.local_offer_outlined, size: 16),
        label: Text(count == 0 ? 'Tags' : 'Tags ($count)'),
        backgroundColor: count == 0
            ? null
            : Colors.purple.withValues(alpha: 0.12),
        side: count == 0
            ? null
            : BorderSide(color: Colors.purple.withValues(alpha: 0.4)),
      ),
    );
  }

  Widget _emptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory, size: 80, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            'Sin productos por el momento',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: Colors.grey),
          ),
          SizedBox(height: 8),
          Text(
            'Presiona el botón + para agregar tu primer producto',
            style: TextStyle(fontSize: 14, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _noResultsState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off, size: 64, color: Colors.grey),
            const SizedBox(height: 12),
            const Text(
              'Sin resultados con estos filtros',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _clearAllFilters,
              icon: const Icon(Icons.filter_alt_off),
              label: const Text('Limpiar filtros'),
            ),
          ],
        ),
      ),
    );
  }
}

class ProductCard extends StatelessWidget {
  final Product product;

  const ProductCard({
    super.key,
    required this.product,
  });

  void _showQRCode(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return QRCodeDialog(
          productCode: product.code,
          productName: product.name,
        );
      },
    );
  }

  Future<void> _deleteProduct(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('¿Eliminar este producto?'),
          content: Text(
            'Se eliminará "${product.name}" permanentemente del stock. Esta acción no se puede deshacer.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Eliminar'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      try {
        // Cleanup: borrar imagen asociada del backend (si existe).
        // Tolerante a fallos: si falla el borrado remoto, igual eliminamos
        // el producto local (la imagen huerfana se puede limpiar despues).
        final imageToCleanup = product.imageId;

        await product.delete();

        if (imageToCleanup != null && imageToCleanup.isNotEmpty) {
          // Fire-and-forget — no esperamos al cleanup remoto
          PocketBaseSyncService.instance.deleteFile(imageToCleanup);
        }

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.delete, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Expanded(child: Text('Producto eliminado del stock')),
                ],
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al eliminar producto: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  Future<void> _editProduct(BuildContext context) async {
    await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return EditProductForm(product: product);
      },
    );
  }

  Future<void> _editQuantity(BuildContext context) async {
    final controller = TextEditingController(text: product.quantity.toString());

    final newQuantity = await showDialog<int>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Editar cantidad'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Producto: ${product.name}',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              Text(
                'Cantidad actual: ${product.quantity} unidades',
                style: TextStyle(color: Colors.grey[600]),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Nueva cantidad',
                  suffixText: 'unidades',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
                onSubmitted: (value) {
                  final quantity = int.tryParse(value);
                  if (quantity != null && quantity >= 0) {
                    Navigator.of(context).pop(quantity);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () {
                final quantity = int.tryParse(controller.text);
                if (quantity != null && quantity >= 0) {
                  Navigator.of(context).pop(quantity);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Ingrese una cantidad válida (0 o mayor)'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );

    if (newQuantity != null && context.mounted) {
      await _updateQuantity(context, newQuantity);
    }

    controller.dispose();
  }

  Future<void> _updateQuantity(BuildContext context, int newQuantity) async {
    try {
      final oldQuantity = product.quantity;
      product.quantity = newQuantity;
      await product.save();

      if (context.mounted) {
        final difference = newQuantity - oldQuantity;
        final message = difference > 0
            ? 'Stock aumentado en ${difference.abs()} unidades'
            : difference < 0
                ? 'Stock reducido en ${difference.abs()} unidades'
                : 'Cantidad actualizada';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  difference > 0 ? Icons.add : difference < 0 ? Icons.remove : Icons.edit,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(message)),
              ],
            ),
            backgroundColor: Colors.blue,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al actualizar cantidad: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _quickAdjustQuantity(BuildContext context, int adjustment) async {
    final newQuantity = (product.quantity + adjustment).clamp(0, 99999);
    if (newQuantity != product.quantity) {
      await _updateQuantity(context, newQuantity);
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
            Row(
              children: [
                if (product.hasImage) ...[
                  _ProductThumbnail(imageId: product.imageId!, productName: product.name),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Text(
                    product.name,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert,
                    color: theme.iconTheme.color?.withValues(alpha: 0.7),
                    size: 20,
                  ),
                  onSelected: (value) {
                    if (value == 'delete') {
                      _deleteProduct(context);
                    } else if (value == 'edit') {
                      _editQuantity(context);
                    } else if (value == 'edit_full') {
                      _editProduct(context);
                    } else if (value == 'qr') {
                      _showQRCode(context);
                    }
                  },
                  itemBuilder: (BuildContext context) => [
                    const PopupMenuItem<String>(
                      value: 'qr',
                      child: Row(children: [
                        Icon(Icons.qr_code, color: Colors.purple, size: 18),
                        SizedBox(width: 8),
                        Text('Ver código QR'),
                      ]),
                    ),
                    const PopupMenuItem<String>(
                      value: 'edit_full',
                      child: Row(children: [
                        Icon(Icons.edit_note, color: Colors.green, size: 18),
                        SizedBox(width: 8),
                        Text('Editar producto'),
                      ]),
                    ),
                    const PopupMenuItem<String>(
                      value: 'edit',
                      child: Row(children: [
                        Icon(Icons.edit, color: Colors.blue, size: 18),
                        SizedBox(width: 8),
                        Text('Editar cantidad'),
                      ]),
                    ),
                    const PopupMenuItem<String>(
                      value: 'delete',
                      child: Row(children: [
                        Icon(Icons.delete, color: Colors.red, size: 18),
                        SizedBox(width: 8),
                        Text('Eliminar'),
                      ]),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: product.quantityStatusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: product.quantityStatusColor, width: 1),
                  ),
                  child: Text(
                    product.quantityStatus,
                    style: TextStyle(
                      color: product.quantityStatusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Icon(Icons.category, size: 16, color: product.categoryColor),
                const SizedBox(width: 8),
                Text(
                  product.categoryDisplayName,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: product.categoryColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (product.tagsNormalized.isNotEmpty) ...[
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: product.tagsNormalized.map((t) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.purple.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      t,
                      style: const TextStyle(color: Colors.purple, fontSize: 11),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
            ],

            Row(
              children: [
                Icon(
                  Icons.qr_code,
                  size: 16,
                  color: theme.iconTheme.color?.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 8),
                Text(
                  'Código: ${product.formattedCode}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.iconTheme.color?.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w500,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _showQRCode(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.purple.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.qr_code, color: Colors.purple, size: 14),
                        SizedBox(width: 4),
                        Text(
                          'Ver QR',
                          style: TextStyle(
                            color: Colors.purple,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            Row(
              children: [
                Icon(
                  Icons.numbers,
                  size: 16,
                  color: theme.iconTheme.color?.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 8),
                Text(
                  '${product.quantity} unidades',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: product.quantityStatusColor,
                  ),
                ),
                const Spacer(),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: product.quantity > 0
                          ? () => _quickAdjustQuantity(context, -1)
                          : null,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: product.quantity > 0
                              ? Colors.red.withValues(alpha: 0.1)
                              : Colors.grey.withValues(alpha: 0.1),
                          border: Border.all(
                            color: product.quantity > 0
                                ? Colors.red.withValues(alpha: 0.3)
                                : Colors.grey.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Icon(
                          Icons.remove,
                          size: 16,
                          color: product.quantity > 0 ? Colors.red : Colors.grey,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => _quickAdjustQuantity(context, 1),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.green.withValues(alpha: 0.1),
                          border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                        ),
                        child: const Icon(Icons.add, size: 16, color: Colors.green),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (product.hasCostInfo || product.hasSalePriceInfo || product.hasProvider) ...[
              if (product.hasCostInfo)
                Row(
                  children: [
                    const Icon(Icons.shopping_cart, size: 16, color: Colors.red),
                    const SizedBox(width: 8),
                    Text(
                      'Costo: ${product.formattedCost}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.red[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              if (product.hasCostInfo && product.hasSalePriceInfo)
                const SizedBox(height: 6),
              if (product.hasSalePriceInfo)
                Row(
                  children: [
                    const Icon(Icons.sell, size: 16, color: Colors.green),
                    const SizedBox(width: 8),
                    Text(
                      'Venta: ${product.formattedCalculatedSalePrice}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.green[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (product.usePercentage && product.profitPercentage != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          '${product.profitPercentage!.toStringAsFixed(0)}%',
                          style: const TextStyle(
                            color: Colors.blue,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              if (product.hasSalePriceInfo && product.hasCostInfo) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.trending_up, size: 16, color: Colors.purple),
                    const SizedBox(width: 8),
                    Text(
                      'Ganancia: ${product.formattedProfit}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.purple[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
              if ((product.hasCostInfo || product.hasSalePriceInfo) && product.hasProvider)
                const SizedBox(height: 6),
              if (product.hasProvider)
                ValueListenableBuilder<Box<Provider>>(
                  valueListenable: Hive.box<Provider>('providers').listenable(),
                  builder: (context, box, _) {
                    Provider? provider;
                    if (product.providerId != null) {
                      for (var p in box.values) {
                        if (p.key.toString() == product.providerId) {
                          provider = p;
                          break;
                        }
                      }
                    }

                    if (provider == null) return const SizedBox.shrink();

                    return Row(
                      children: [
                        Icon(
                          Icons.business,
                          size: 16,
                          color: theme.iconTheme.color?.withValues(alpha: 0.7),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Proveedor: ${provider.name}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.8),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              const SizedBox(height: 8),
            ],

            Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  size: 16,
                  color: theme.iconTheme.color?.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 8),
                Text(
                  'Agregado: ${product.formattedCreatedAt}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Thumbnail compacto que resuelve la URL del archivo asincronamente.
/// Click expande imagen full-screen.
class _ProductThumbnail extends StatefulWidget {
  final String imageId;
  final String productName;

  const _ProductThumbnail({required this.imageId, required this.productName});

  @override
  State<_ProductThumbnail> createState() => _ProductThumbnailState();
}

class _ProductThumbnailState extends State<_ProductThumbnail> {
  String? _url;

  @override
  void initState() {
    super.initState();
    _loadUrl();
  }

  Future<void> _loadUrl() async {
    final u = await PocketBaseSyncService.instance.getFileUrlAsync(
      widget.imageId,
      thumb: true,
    );
    if (mounted) setState(() => _url = u);
  }

  void _openFullScreen() {
    if (_url == null) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            InteractiveViewer(
              child: Image.network(
                _url!.replaceAll('thumb=120x120', ''),
                fit: BoxFit.contain,
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(ctx).pop(),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _openFullScreen,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: _url == null
            ? const Center(
                child: SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : Image.network(
                _url!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.broken_image, size: 20, color: Colors.grey),
              ),
      ),
    );
  }
}
