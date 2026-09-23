import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:pie_chart/pie_chart.dart';
import '../models/transaction.dart';
import '../models/appointment.dart';

class PieChartCard extends StatelessWidget {
  const PieChartCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: Hive.box<Transaction>('transactions').listenable(),
      builder: (context, _, __) {
        final earningsData = _calculateEarningsBreakdown();
        
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark 
                ? Colors.grey.shade800 
                : Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).brightness == Brightness.dark 
                    ? Colors.black.withValues(alpha: 0.4) 
                    : Colors.grey.withValues(alpha: 0.15),
                blurRadius: 12,
                offset: const Offset(0, 6),
                spreadRadius: 1,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.pie_chart,
                      color: Colors.blue,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Desglose de Ganancias',
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).brightness == Brightness.dark 
                                ? Colors.white 
                                : Colors.grey.shade800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Distribución por tipo de ingreso',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).brightness == Brightness.dark 
                                ? Colors.grey.shade300 
                                : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildChartContent(context, earningsData),
            ],
          ),
        );
      },
    );
  }

  Widget _buildChartContent(BuildContext context, Map<String, double> data) {
    final totalEarnings = data.values.fold(0.0, (sum, value) => sum + value);
    
    if (totalEarnings == 0) {
      return _buildEmptyState();
    }

    return Column(
      children: [
        SizedBox(
          height: 200,
          child: PieChart(
            dataMap: data,
            animationDuration: const Duration(milliseconds: 800),
            chartLegendSpacing: 32,
            chartRadius: MediaQuery.of(context).size.width / 3.2,
            colorList: _getChartColors(context),
            initialAngleInDegree: 0,
            chartType: ChartType.ring,
            centerText: "Total\n\$${_formatAmount(totalEarnings)}",
            centerTextStyle: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).brightness == Brightness.dark 
                  ? Colors.white 
                  : Colors.grey.shade700,
            ),
            ringStrokeWidth: 32,
            legendOptions: LegendOptions(
              showLegendsInRow: false,
              legendPosition: LegendPosition.right,
              showLegends: true,
              legendShape: BoxShape.circle,
              legendTextStyle: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 14,
                color: Theme.of(context).brightness == Brightness.dark 
                    ? Colors.white70 
                    : Colors.grey.shade700,
              ),
            ),
            chartValuesOptions: ChartValuesOptions(
              showChartValueBackground: true,
              showChartValues: true,
              showChartValuesInPercentage: true,
              showChartValuesOutside: false,
              decimalPlaces: 1,
              chartValueBackgroundColor: Theme.of(context).brightness == Brightness.dark 
                  ? Colors.grey.shade800.withValues(alpha: 0.8)
                  : Colors.white.withValues(alpha: 0.8),
              chartValueStyle: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: Theme.of(context).brightness == Brightness.dark 
                    ? Colors.white 
                    : Colors.grey.shade800,
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        _buildSummaryStats(data),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Container(
      height: 200,
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.pie_chart_outline,
            size: 64,
            color: Colors.grey,
          ),
          SizedBox(height: 16),
          Text(
            'Aún no hay datos para mostrar',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.grey,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Registra turnos y ventas para ver el desglose',
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

  Widget _buildSummaryStats(Map<String, double> data) {
    return Column(
      children: [
        _EnhancedStatCard(
          title: 'Turnos',
          subtitle: 'Servicios completados',
          amount: data['Turnos'] ?? 0,
          color: _getChartColors(null)[0],
          icon: '💅',
        ),
        const SizedBox(height: 12),
        _EnhancedStatCard(
          title: 'Ventas',
          subtitle: 'Productos vendidos',
          amount: data['Ventas'] ?? 0,
          color: _getChartColors(null)[1],
          icon: '🛍️',
        ),
      ],
    );
  }

  List<Color> _getChartColors(BuildContext? context) {
    final isDark = context != null 
        ? Theme.of(context).brightness == Brightness.dark 
        : false;
    
    if (isDark) {
      // Colores para modo oscuro - más vibrantes
      return [
        const Color(0xFF4FC3F7), // Azul claro para turnos
        const Color(0xFF81C784), // Verde claro para ventas
      ];
    } else {
      // Colores para modo claro
      return [
        const Color(0xFF2196F3), // Azul para turnos
        const Color(0xFF4CAF50), // Verde para ventas
      ];
    }
  }

  Map<String, double> _calculateEarningsBreakdown() {
    double salesEarnings = 0.0;
    double appointmentEarnings = 0.0;

    try {
      // Calcular ganancias de ventas
      final transactionsBox = Hive.box<Transaction>('transactions');
      for (final transaction in transactionsBox.values) {
        if (transaction.source.toLowerCase() == 'venta') {
          salesEarnings += transaction.amount;
        }
      }

      // Calcular ganancias de turnos completados
      final appointmentsBox = Hive.box<Appointment>('appointments');
      for (final appointment in appointmentsBox.values) {
        if (appointment.completed) {
          appointmentEarnings += appointment.price;
        }
      }
    } catch (e) {
      // En caso de error, retornar valores por defecto
      salesEarnings = 0.0;
      appointmentEarnings = 0.0;
    }

    return {
      'Turnos': appointmentEarnings,
      'Ventas': salesEarnings,
    };
  }

  String _formatAmount(double amount) {
    if (amount == 0) {
      return '0';
    }
    
    // Convertir a string sin decimales
    final amountString = amount.toStringAsFixed(0);
    
    // Agregar separadores de miles
    String formattedInteger = '';
    for (int i = 0; i < amountString.length; i++) {
      if (i > 0 && (amountString.length - i) % 3 == 0) {
        formattedInteger += '.';
      }
      formattedInteger += amountString[i];
    }
    
    return formattedInteger;
  }
}

/// Widget mejorado para mostrar estadísticas individuales
class _EnhancedStatCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final double amount;
  final Color color;
  final String icon;

  const _EnhancedStatCard({
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark 
            ? Colors.grey.shade700.withValues(alpha: 0.5) 
            : color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark 
                ? Colors.black.withValues(alpha: 0.2) 
                : color.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Ícono emoji
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                icon,
                style: const TextStyle(fontSize: 24),
              ),
            ),
          ),
          const SizedBox(width: 16),
          
          // Contenido de texto
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isDark 
                        ? Colors.grey.shade300 
                        : color.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '\$${_formatAmount(amount)}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.grey.shade800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatAmount(double amount) {
    if (amount == 0) {
      return '0';
    }
    
    final amountString = amount.toStringAsFixed(0);
    String formattedInteger = '';
    for (int i = 0; i < amountString.length; i++) {
      if (i > 0 && (amountString.length - i) % 3 == 0) {
        formattedInteger += '.';
      }
      formattedInteger += amountString[i];
    }
    
    return formattedInteger;
  }
}