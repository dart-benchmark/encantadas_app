import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/transaction.dart';
import '../models/product.dart';
import '../utils/text_search.dart';

enum SaleTypeFilter { all, product, service }

enum DateRangeFilter { all, today, week, month }

class VentasScreen extends StatefulWidget {
  const VentasScreen({super.key});

  @override
  State<VentasScreen> createState() => _VentasScreenState();
}

class _VentasScreenState extends State<VentasScreen> {
  bool _isSelectionMode = false;
  final Set<String> _selectedSales = <String>{};

  final _searchController = TextEditingController();
  Timer? _debounce;
  String _searchQuery = '';
  SaleTypeFilter _typeFilter = SaleTypeFilter.all;
  DateRangeFilter _dateFilter = DateRangeFilter.all;
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
      _typeFilter = SaleTypeFilter.all;
      _dateFilter = DateRangeFilter.all;
      _selectedTags.clear();
    });
  }

  bool get _hasActiveFilters =>
      _searchQuery.isNotEmpty ||
      _typeFilter != SaleTypeFilter.all ||
      _dateFilter != DateRangeFilter.all ||
      _selectedTags.isNotEmpty;

  /// Devuelve el inicio del período según el filtro seleccionado.
  DateTime? _dateRangeStart() {
    final now = DateTime.now();
    switch (_dateFilter) {
      case DateRangeFilter.all:
        return null;
      case DateRangeFilter.today:
        return DateTime(now.year, now.month, now.day);
      case DateRangeFilter.week:
        return now.subtract(const Duration(days: 7));
      case DateRangeFilter.month:
        return DateTime(now.year, now.month - 1, now.day);
    }
  }

  /// Resuelve los tags del producto referenciado por la venta (vía code o name).
  List<String> _saleProductTags(Transaction sale, Box<Product> productsBox) {
    if (!sale.isProductSale) return const [];
    if (sale.productCode != null && sale.productCode!.isNotEmpty) {
      for (final p in productsBox.values) {
        if (p.code == sale.productCode) return p.tagsNormalized;
      }
    }
    if (sale.productName != null) {
      for (final p in productsBox.values) {
        if (p.name == sale.productName) return p.tagsNormalized;
      }
    }
    return const [];
  }

  List<Transaction> _applyFilters(
    List<Transaction> sales,
    Box<Product> productsBox,
  ) {
    final dateStart = _dateRangeStart();
    return sales.where((s) {
      // Search por nombre del producto/servicio
      if (_searchQuery.isNotEmpty) {
        final fields = <String?>[
          s.productName,
          s.serviceName,
          s.productCode,
        ];
        if (!matchesQuery(_searchQuery, fields)) return false;
      }
      // Tipo
      switch (_typeFilter) {
        case SaleTypeFilter.all:
          break;
        case SaleTypeFilter.product:
          if (!s.isProductSale) return false;
          break;
        case SaleTypeFilter.service:
          if (s.isProductSale) return false;
          break;
      }
      // Fecha
      if (dateStart != null && s.date.isBefore(dateStart)) return false;
      // Tags (solo aplica a ventas de producto; ventas de servicio quedan
      // fuera cuando hay tags filtrados, lo cual es semánticamente correcto).
      if (_selectedTags.isNotEmpty) {
        if (!s.isProductSale) return false;
        final productTags = _saleProductTags(s, productsBox).toSet();
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
                      'Filtrar ventas por tags',
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
                  'Solo se muestran ventas de productos con TODOS los tags.',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
                const SizedBox(height: 16),
                if (allTags.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        'Aún no hay tags creados.',
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

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedSales.clear();
      }
    });
  }

  void _toggleSaleSelection(String saleKey) {
    setState(() {
      if (_selectedSales.contains(saleKey)) {
        _selectedSales.remove(saleKey);
      } else {
        _selectedSales.add(saleKey);
      }
    });
  }

  void _selectAllSales(List<Transaction> sales) {
    setState(() {
      if (_selectedSales.length == sales.length) {
        _selectedSales.clear();
      } else {
        _selectedSales.clear();
        for (final sale in sales) {
          _selectedSales.add(sale.key.toString());
        }
      }
    });
  }

  /// Muestra diálogo de confirmación para eliminar múltiples ventas
  Future<void> _showMultipleDeleteConfirmation(BuildContext context, List<Transaction> selectedSales) async {
    final bool? shouldDelete = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.delete_sweep, color: Colors.red, size: 28),
              const SizedBox(width: 12),
              Text('Eliminar ${selectedSales.length} ventas'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('¿Estás seguro? Esta acción restaurará el stock y ajustará el balance.'),
              const SizedBox(height: 16),
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(
                  child: Column(
                    children: selectedSales.map((sale) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    sale.isProductSale ? sale.productName! : sale.serviceName,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                  Text(
                                    sale.formattedAmount,
                                    style: const TextStyle(color: Colors.green, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Eliminar todas'),
            ),
          ],
        );
      },
    );

    if (shouldDelete == true && context.mounted) {
      await _deleteMultipleSales(context, selectedSales);
    }
  }

  /// Elimina múltiples ventas y restaura el stock
  Future<void> _deleteMultipleSales(BuildContext context, List<Transaction> salesToDelete) async {
    int successCount = 0;
    int errorCount = 0;
    List<String> productErrors = [];

    try {
      final productsBox = Hive.box<Product>('products');

      for (final sale in salesToDelete) {
        try {
          // Si es una venta de producto, restaurar stock
          if (sale.isProductSale && sale.productName != null && sale.quantity != null) {
            // Lookup preferente por código (estable). Fallback a nombre
            // solo para ventas viejas anteriores al schema con productCode.
            final product = _findProductForSale(productsBox, sale);

            if (product != null) {
              // Restaurar stock
              product.quantity += sale.quantity!;
              await product.save();
            } else {
              // Producto no encontrado
              productErrors.add(sale.productName!);
            }
          }

          // Eliminar la transacción
          await sale.delete();
          successCount++;
        } catch (e) {
          errorCount++;
        }
      }

      // Salir del modo selección
      setState(() {
        _isSelectionMode = false;
        _selectedSales.clear();
      });

      // Mostrar mensajes de resultado
      if (context.mounted) {
        if (productErrors.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.warning, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Algunos productos fueron eliminados, no se pudo restaurar stock: ${productErrors.join(", ")}'),
                  ),
                ],
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 5),
            ),
          );
        }

        if (successCount > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Se eliminaron $successCount ventas correctamente.'),
                  ),
                ],
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }

        if (errorCount > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Ocurrieron $errorCount errores durante la eliminación.'),
                  ),
                ],
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Error al eliminar ventas: $e'),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  /// Muestra diálogo de confirmación para eliminar venta
  Future<void> _showDeleteConfirmation(BuildContext context, Transaction sale) async {
    final bool? shouldDelete = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.orange, size: 28),
              SizedBox(width: 12),
              Text('Confirmar eliminación'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('¿Estás seguro de eliminar esta venta?'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sale.isProductSale ? sale.productName! : sale.serviceName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (sale.isProductSale && sale.quantity != null) ...[
                      const SizedBox(height: 4),
                      Text('Cantidad: ${sale.formattedQuantity}'),
                    ],
                    const SizedBox(height: 4),
                    Text('Total: ${sale.formattedAmount}'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Esta acción restaurará el stock del producto y ajustará el balance.',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Eliminar'),
            ),
          ],
        );
      },
    );

    if (shouldDelete == true && context.mounted) {
      await _deleteSale(context, sale);
    }
  }

  /// Lookup estable de producto para una venta.
  /// Prioriza el código guardado en la transacción (immutable).
  /// Fallback al nombre solo para registros pre-productCode.
  Product? _findProductForSale(Box<Product> productsBox, Transaction sale) {
    if (sale.productCode != null && sale.productCode!.isNotEmpty) {
      for (final p in productsBox.values) {
        if (p.code == sale.productCode) return p;
      }
      // Si tenía código pero no se encuentra, el producto fue eliminado
      // — no caer al fallback por nombre porque es ambiguo.
      return null;
    }
    // Registro viejo sin productCode: fallback por nombre.
    if (sale.productName != null) {
      for (final p in productsBox.values) {
        if (p.name == sale.productName) return p;
      }
    }
    return null;
  }

  /// Elimina la venta y restaura el stock
  Future<void> _deleteSale(BuildContext context, Transaction sale) async {
    try {
      // Si es una venta de producto, restaurar stock
      if (sale.isProductSale && sale.productName != null && sale.quantity != null) {
        final productsBox = Hive.box<Product>('products');
        final product = _findProductForSale(productsBox, sale);

        if (product != null) {
          // Restaurar stock
          product.quantity += sale.quantity!;
          await product.save();
        } else {
          // Producto no encontrado, mostrar advertencia pero continuar
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.warning, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('No se puede restaurar stock, el producto ha sido eliminado'),
                    ),
                  ],
                ),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
      }

      // Eliminar la transacción
      await sale.delete();

      // Mostrar mensaje de éxito
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Venta eliminada correctamente. Stock y balance restaurados.'),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      // Mostrar error
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Error al eliminar venta: $e'),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _isSelectionMode 
            ? Text('${_selectedSales.length} seleccionadas')
            : const Text('Ventas'),
        leading: _isSelectionMode 
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _toggleSelectionMode,
              )
            : null,
        actions: [
          if (!_isSelectionMode)
            IconButton(
              icon: const Icon(Icons.checklist_rtl),
              onPressed: _toggleSelectionMode,
              tooltip: 'Selección múltiple',
            ),
          if (_isSelectionMode)
            IconButton(
              icon: const Icon(Icons.select_all),
              onPressed: () {
                final box = Hive.box<Transaction>('transactions');
                final productsBox = Hive.box<Product>('products');
                final all = box.values
                    .where((t) => t.source.toLowerCase() == 'venta')
                    .toList();
                // Selecciona solo las ventas que pasan los filtros activos
                _selectAllSales(_applyFilters(all, productsBox));
              },
              tooltip: 'Seleccionar todas las visibles',
            ),
        ],
      ),
      body: ValueListenableBuilder<Box<Transaction>>(
        valueListenable: Hive.box<Transaction>('transactions').listenable(),
        builder: (context, box, _) {
          final productsBox = Hive.box<Product>('products');
          // Junto todos los tags de productos para el picker
          final allTagsSet = <String>{};
          for (final p in productsBox.values) {
            allTagsSet.addAll(p.tagsNormalized);
          }
          final sortedTags = allTagsSet.toList()..sort();

          final allTransactions = box.values.toList().cast<Transaction>();
          final salesTransactions = allTransactions
              .where((t) => t.source.toLowerCase() == 'venta')
              .toList();
          salesTransactions.sort((a, b) => b.date.compareTo(a.date));

          final filtered = _applyFilters(salesTransactions, productsBox);
          final isEmpty = salesTransactions.isEmpty;
          final noResults = !isEmpty && filtered.isEmpty;
          final totalAmount = filtered.fold<double>(0, (sum, s) => sum + s.amount);

          return Column(
            children: [
              if (!_isSelectionMode)
                _buildFilterBar(
                  total: salesTransactions.length,
                  matching: filtered.length,
                  totalAmount: totalAmount,
                  allTags: sortedTags,
                ),
              Expanded(
                child: isEmpty
                    ? _emptyState()
                    : noResults
                        ? _noResultsState()
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final sale = filtered[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: SaleCard(
                                  transaction: sale,
                                  onDelete: _isSelectionMode
                                      ? null
                                      : () => _showDeleteConfirmation(context, sale),
                                  isSelectionMode: _isSelectionMode,
                                  isSelected: _selectedSales.contains(sale.key.toString()),
                                  onSelectionChanged: (selected) =>
                                      _toggleSaleSelection(sale.key.toString()),
                                ),
                              );
                            },
                          ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: _isSelectionMode && _selectedSales.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () {
                final box = Hive.box<Transaction>('transactions');
                final allTransactions = box.values.toList().cast<Transaction>();
                final salesTransactions = allTransactions
                    .where((transaction) => transaction.source.toLowerCase() == 'venta')
                    .toList();
                final selectedSales = salesTransactions
                    .where((sale) => _selectedSales.contains(sale.key.toString()))
                    .toList();
                _showMultipleDeleteConfirmation(context, selectedSales);
              },
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.delete_sweep),
              label: Text('Eliminar ${_selectedSales.length}'),
            )
          : null,
    );
  }

  Widget _buildFilterBar({
    required int total,
    required int matching,
    required double totalAmount,
    required List<String> allTags,
  }) {
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
                hintText: 'Buscar por producto, servicio o código...',
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
                  _typeChip(label: 'Todas', value: SaleTypeFilter.all),
                  _typeChip(label: '🛍️ Productos', value: SaleTypeFilter.product),
                  _typeChip(label: '💅 Servicios', value: SaleTypeFilter.service),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                _dateMenuButton(),
                const SizedBox(width: 8),
                _tagsButton(allTags),
                const Spacer(),
                if (_hasActiveFilters)
                  IconButton(
                    icon: const Icon(Icons.filter_alt_off, size: 20),
                    onPressed: _clearAllFilters,
                    tooltip: 'Limpiar filtros',
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  matching == total
                      ? '$total ventas'
                      : '$matching de $total',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 12),
                if (matching > 0)
                  Text(
                    'Total: \$${totalAmount.toStringAsFixed(0)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.green[700],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeChip({required String label, required SaleTypeFilter value}) {
    final isSelected = _typeFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) => setState(() {
          _typeFilter = isSelected ? SaleTypeFilter.all : value;
        }),
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _dateMenuButton() {
    return PopupMenuButton<DateRangeFilter>(
      tooltip: 'Filtrar por período',
      onSelected: (v) => setState(() => _dateFilter = v),
      itemBuilder: (_) => const [
        PopupMenuItem(value: DateRangeFilter.all, child: Text('Todo el tiempo')),
        PopupMenuItem(value: DateRangeFilter.today, child: Text('Hoy')),
        PopupMenuItem(value: DateRangeFilter.week, child: Text('Últimos 7 días')),
        PopupMenuItem(value: DateRangeFilter.month, child: Text('Últimos 30 días')),
      ],
      child: Chip(
        avatar: const Icon(Icons.calendar_month, size: 16),
        label: Text(_dateLabel(_dateFilter)),
        backgroundColor: _dateFilter == DateRangeFilter.all
            ? null
            : Colors.blue.withValues(alpha: 0.12),
        side: _dateFilter == DateRangeFilter.all
            ? null
            : BorderSide(color: Colors.blue.withValues(alpha: 0.4)),
      ),
    );
  }

  String _dateLabel(DateRangeFilter f) {
    switch (f) {
      case DateRangeFilter.all:
        return 'Período: todo';
      case DateRangeFilter.today:
        return 'Hoy';
      case DateRangeFilter.week:
        return 'Últimos 7d';
      case DateRangeFilter.month:
        return 'Últimos 30d';
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
          Icon(Icons.shopping_cart, size: 80, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            'Aún no hay ventas registradas',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: Colors.grey),
          ),
          SizedBox(height: 8),
          Text(
            'Presiona el botón + para registrar tu primera venta',
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
              'Sin ventas con estos filtros',
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

class SaleCard extends StatelessWidget {
  final Transaction transaction;
  final VoidCallback? onDelete;
  final bool isSelectionMode;
  final bool isSelected;
  final ValueChanged<bool?>? onSelectionChanged;

  const SaleCard({
    super.key,
    required this.transaction,
    this.onDelete,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onSelectionChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Card(
      elevation: 2,
      color: isSelected ? Colors.blue.withValues(alpha: 0.1) : null,
      child: InkWell(
        onTap: isSelectionMode ? () => onSelectionChanged?.call(!isSelected) : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            // Product name and total row
            Row(
              children: [
                if (isSelectionMode) ...[
                  Checkbox(
                    value: isSelected,
                    onChanged: onSelectionChanged,
                    activeColor: Colors.blue,
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    transaction.isProductSale 
                        ? transaction.productName! 
                        : transaction.serviceName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green, width: 1),
                  ),
                  child: Text(
                    transaction.formattedAmount,
                    style: const TextStyle(
                      color: Colors.green,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (onDelete != null && !isSelectionMode) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                    color: Colors.red,
                    tooltip: 'Eliminar venta',
                    constraints: const BoxConstraints(
                      minWidth: 40,
                      minHeight: 40,
                    ),
                    padding: const EdgeInsets.all(8),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            
            // Quantity and unit price (for product sales)
            if (transaction.isProductSale && transaction.quantity != null) ...[
              Row(
                children: [
                  Icon(
                    Icons.shopping_basket,
                    size: 16,
                    color: theme.iconTheme.color?.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Cantidad: ${transaction.formattedQuantity}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.8),
                    ),
                  ),
                  if (transaction.unitPrice != null) ...[
                    const SizedBox(width: 16),
                    Text(
                      '• ${transaction.formattedUnitPrice} c/u',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
            ],
            
            // Date
            Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  size: 16,
                  color: theme.iconTheme.color?.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 8),
                Text(
                  'Fecha: ${transaction.formattedDate}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.8),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.blue.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    transaction.formattedSource,
                    style: TextStyle(
                      color: Colors.blue,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            ],
          ),
        ),
      ),
    );
  }
}