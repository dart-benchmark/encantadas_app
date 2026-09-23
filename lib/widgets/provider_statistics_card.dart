import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:pie_chart/pie_chart.dart';
import '../models/provider.dart';
import '../models/product.dart';
import '../models/transaction.dart';

class ProviderStatisticsCard extends StatelessWidget {
  const ProviderStatisticsCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box<Product>>(
      valueListenable: Hive.box<Product>('products').listenable(),
      builder: (context, productsBox, _) {
        return ValueListenableBuilder<Box<Provider>>(
          valueListenable: Hive.box<Provider>('providers').listenable(),
          builder: (context, providersBox, _) {
            return ValueListenableBuilder<Box<Transaction>>(
              valueListenable: Hive.box<Transaction>('transactions').listenable(),
              builder: (context, transactionsBox, _) {
                final products = productsBox.values.toList().cast<Product>();
                final providers = providersBox.values.toList().cast<Provider>();
                final transactions = transactionsBox.values.toList().cast<Transaction>();
                
                final stats = _calculateAdvancedStats(products, providers, transactions);
            
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Título principal
                  Text(
                    'Resumen de Proveedores',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[700],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Información sobre tus compras por proveedor',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  if (stats.isEmpty) 
                    _buildEmptyState(context)
                  else ...[
                    // Números principales
                    _buildMainNumbers(context, stats),
                    const SizedBox(height: 24),
                    
                    // Ranking de gastos
                    _buildSimpleRanking(context, stats),
                    const SizedBox(height: 24),
                    
                    // Ranking de ganancias
                    _buildProfitRanking(context, stats),
                    const SizedBox(height: 24),
                    
                    // Gráfico simple (solo si hay más de 1 proveedor)
                    if (stats.length > 1) ...[
                      _buildSimpleChart(context, stats),
                      const SizedBox(height: 24),
                    ],
                    
                    // Lista detallada pero simple
                    _buildSimpleProviderList(context, stats),
                  ],
                ],
              ),
            );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          children: [
            Icon(
              Icons.analytics_outlined,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No hay datos para mostrar',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Agrega productos con precios y proveedores para ver estadísticas',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainNumbers(BuildContext context, List<ProviderStat> stats) {
    final totalSpent = stats.fold(0.0, (sum, stat) => sum + stat.totalSpent);
    final totalProducts = stats.fold(0, (sum, stat) => sum + stat.productCount);
    final totalProfit = stats.fold(0.0, (sum, stat) => sum + stat.totalProfit);
    
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Totales',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildNumberCard(
                    context,
                    '\$${totalSpent.toStringAsFixed(0)}',
                    'Total gastado',
                    Icons.trending_down,
                    Colors.red,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildNumberCard(
                    context,
                    '\$${totalProfit.toStringAsFixed(0)}',
                    'Ganancia total',
                    Icons.trending_up,
                    Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildNumberCard(
                    context,
                    totalProducts.toString(),
                    'Productos comprados',
                    Icons.shopping_bag,
                    Colors.orange,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildNumberCard(
                    context,
                    totalProfit > 0 ? '${((totalProfit / (totalSpent + totalProfit)) * 100).toStringAsFixed(0)}%' : '0%',
                    'Margen de ganancia',
                    Icons.percent,
                    Colors.purple,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNumberCard(BuildContext context, String number, String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            number,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildProfitRanking(BuildContext context, List<ProviderStat> stats) {
    final sortedStats = List<ProviderStat>.from(stats)
      ..sort((a, b) => b.totalProfit.compareTo(a.totalProfit));
    
    if (sortedStats.isEmpty || sortedStats.first.totalProfit <= 0) {
      return const SizedBox.shrink();
    }
    
    final topProvider = sortedStats.first;
    
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.trending_up, color: Colors.green, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Proveedor Más Rentable',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.green[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.green[50]!, Colors.teal[50]!],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  Text(
                    '💰',
                    style: const TextStyle(fontSize: 32),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    topProvider.providerName,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Ganancia: \$${topProvider.totalProfit.toStringAsFixed(0)}',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.green[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (topProvider.mostProfitableProduct != null)
                    Text(
                      'Producto top: ${topProvider.mostProfitableProduct}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[600],
                      ),
                      textAlign: TextAlign.center,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSimpleRanking(BuildContext context, List<ProviderStat> stats) {
    final sortedStats = List<ProviderStat>.from(stats)
      ..sort((a, b) => b.totalSpent.compareTo(a.totalSpent));
    
    final topProvider = sortedStats.first;
    
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.emoji_events, color: Colors.amber, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Proveedor Principal',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.amber[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.amber[50]!, Colors.orange[50]!],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  Text(
                    '🏆',
                    style: const TextStyle(fontSize: 32),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    topProvider.providerName,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Has gastado \$${topProvider.totalSpent.toStringAsFixed(0)}',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    'en ${topProvider.productCount} productos',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSimpleChart(BuildContext context, List<ProviderStat> stats) {
    final chartData = <String, double>{};
    for (final stat in stats) {
      if (stat.totalSpent > 0) {
        chartData[stat.providerName] = stat.totalSpent;
      }
    }
    
    if (chartData.isEmpty) return const SizedBox.shrink();
    
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.pie_chart, color: Colors.purple, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Distribución de Gastos',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.purple[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Proporción de dinero gastado en cada proveedor',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: PieChart(
                dataMap: chartData,
                animationDuration: const Duration(milliseconds: 800),
                chartRadius: MediaQuery.of(context).size.width / 3.5,
                colorList: [
                  Colors.blue,
                  Colors.green,
                  Colors.orange,
                  Colors.red,
                  Colors.purple,
                  Colors.teal,
                ],
                initialAngleInDegree: 0,
                chartType: ChartType.disc,
                legendOptions: const LegendOptions(
                  showLegendsInRow: false,
                  legendPosition: LegendPosition.right,
                  showLegends: true,
                  legendTextStyle: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                  ),
                ),
                chartValuesOptions: const ChartValuesOptions(
                  showChartValueBackground: false,
                  showChartValues: true,
                  showChartValuesInPercentage: true,
                  showChartValuesOutside: false,
                  decimalPlaces: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSimpleProviderList(BuildContext context, List<ProviderStat> stats) {
    final sortedStats = List<ProviderStat>.from(stats)
      ..sort((a, b) => b.totalSpent.compareTo(a.totalSpent));
    
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.list_alt, color: Colors.indigo, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Todos los Proveedores',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...sortedStats.asMap().entries.map((entry) {
              final index = entry.key;
              final stat = entry.value;
              
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: Row(
                  children: [
                    // Posición
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: _getPositionColor(index),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    
                    // Información del proveedor
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            stat.providerName,
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${stat.productCount} productos',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    // Gasto
                    Text(
                      '\$${stat.totalSpent.toStringAsFixed(0)}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.green[700],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Color _getPositionColor(int index) {
    switch (index) {
      case 0: return Colors.amber; // Oro
      case 1: return Colors.grey; // Plata
      case 2: return Colors.brown; // Bronce
      default: return Colors.blue; // Otros
    }
  }

  List<ProviderStat> _calculateAdvancedStats(List<Product> products, List<Provider> providers, List<Transaction> transactions) {
    final statsMap = <String, ProviderStat>{};
    
    // Crear mapa de proveedores por ID
    final providerMap = <String, Provider>{};
    for (final provider in providers) {
      providerMap[provider.key.toString()] = provider;
    }
    
    // Crear mapa de productos por nombre para buscar en transacciones
    final productByName = <String, Product>{};
    for (final product in products) {
      productByName[product.name] = product;
    }
    
    // Calcular estadísticas de costos
    for (final product in products) {
      if (product.providerId == null || product.cost == null) continue;
      
      final provider = providerMap[product.providerId!];
      if (provider == null) continue;
      
      final providerId = product.providerId!;
      
      if (!statsMap.containsKey(providerId)) {
        statsMap[providerId] = ProviderStat(
          providerId: providerId,
          providerName: provider.name,
          totalSpent: 0.0,
          productCount: 0,
          totalProfit: 0.0,
          mostProfitableProduct: null,
        );
      }
      
      final stat = statsMap[providerId]!;
      stat.totalSpent += (product.cost! * product.quantity);
      stat.productCount += 1;
    }
    
    // Calcular ganancias potenciales basadas en precios configurados y transacciones reales
    final profitByProvider = <String, Map<String, double>>{};
    
    // Primero, calcular ganancias por transacciones reales
    for (final transaction in transactions) {
      if (transaction.source.toLowerCase() != 'venta' || transaction.productName == null) continue;
      
      final product = productByName[transaction.productName];
      if (product == null || product.providerId == null || product.cost == null) continue;
      
      final providerId = product.providerId!;
      if (!statsMap.containsKey(providerId)) continue;
      
      // Usar el precio configurado del producto si existe, si no usar el de la transacción
      final salePrice = product.hasSalePriceInfo 
          ? product.calculatedSalePrice 
          : (transaction.unitPrice ?? transaction.amount);
          
      final unitProfit = salePrice - product.cost!;
      final totalProfit = unitProfit * (transaction.quantity ?? 1);
      
      if (totalProfit > 0) {
        profitByProvider[providerId] ??= <String, double>{};
        profitByProvider[providerId]![product.name] = 
            (profitByProvider[providerId]![product.name] ?? 0) + totalProfit;
        
        statsMap[providerId]!.totalProfit += totalProfit;
      }
    }
    
    // También calcular ganancia potencial para productos con precio configurado pero sin ventas
    for (final product in products) {
      if (product.providerId == null || !product.hasSalePriceInfo || !product.hasCostInfo) continue;
      
      final providerId = product.providerId!;
      if (!statsMap.containsKey(providerId)) continue;
      
      final potentialProfit = product.profitAmount;
      if (potentialProfit > 0) {
        profitByProvider[providerId] ??= <String, double>{};
        // Solo agregar si no hay ganancias registradas por transacciones para este producto
        if (!profitByProvider[providerId]!.containsKey(product.name)) {
          profitByProvider[providerId]![product.name] = potentialProfit;
        }
      }
    }
    
    // Encontrar el producto más rentable por proveedor
    for (final providerId in profitByProvider.keys) {
      final productProfits = profitByProvider[providerId]!;
      if (productProfits.isNotEmpty) {
        final mostProfitable = productProfits.entries
            .reduce((a, b) => a.value > b.value ? a : b);
        statsMap[providerId]!.mostProfitableProduct = mostProfitable.key;
      }
    }
    
    return statsMap.values.toList();
  }

  List<ProviderStat> _calculateSimpleStats(List<Product> products, List<Provider> providers) {
    final statsMap = <String, ProviderStat>{};
    
    // Crear mapa de proveedores por ID
    final providerMap = <String, Provider>{};
    for (final provider in providers) {
      providerMap[provider.key.toString()] = provider;
    }
    
    // Calcular estadísticas simples
    for (final product in products) {
      if (product.providerId == null || product.cost == null) continue;
      
      final provider = providerMap[product.providerId!];
      if (provider == null) continue;
      
      final providerId = product.providerId!;
      
      if (!statsMap.containsKey(providerId)) {
        statsMap[providerId] = ProviderStat(
          providerId: providerId,
          providerName: provider.name,
          totalSpent: 0.0,
          productCount: 0,
          totalProfit: 0.0,
        );
      }
      
      final stat = statsMap[providerId]!;
      stat.totalSpent += (product.cost! * product.quantity);
      stat.productCount += 1;
    }
    
    return statsMap.values.toList();
  }
}

class ProviderStat {
  final String providerId;
  final String providerName;
  double totalSpent;
  int productCount;
  double totalProfit;
  String? mostProfitableProduct;
  
  ProviderStat({
    required this.providerId,
    required this.providerName,
    required this.totalSpent,
    required this.productCount,
    required this.totalProfit,
    this.mostProfitableProduct,
  });
}