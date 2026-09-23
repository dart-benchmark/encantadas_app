import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/transaction.dart';
import '../models/appointment.dart';

class BalanceSummaryCard extends StatelessWidget {
  const BalanceSummaryCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: Hive.box<Transaction>('transactions').listenable(),
      builder: (context, _, __) {
        final todayEarnings = _calculateEarnings(DateRange.today);
        final weekEarnings = _calculateEarnings(DateRange.week);
        final monthEarnings = _calculateEarnings(DateRange.month);

        return Container(
          margin: const EdgeInsets.all(16),
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
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.account_balance_wallet,
                      color: Colors.green,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Resumen de Ganancias',
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).brightness == Brightness.dark 
                                ? Colors.white 
                                : Colors.grey.shade800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Ingresos totales por período',
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
              Column(
                children: [
                  _EnhancedSummaryCard(
                    title: 'Hoy',
                    subtitle: 'Ganancias del día',
                    amount: todayEarnings,
                    icon: '🗓️',
                    color: Colors.green,
                    gradient: LinearGradient(
                      colors: [Colors.green.shade400, Colors.green.shade600],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _EnhancedSummaryCard(
                    title: 'Semana',
                    subtitle: 'Ingresos semanales',
                    amount: weekEarnings,
                    icon: '📅',
                    color: Colors.blue,
                    gradient: LinearGradient(
                      colors: [Colors.blue.shade400, Colors.blue.shade600],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _EnhancedSummaryCard(
                    title: 'Mes',
                    subtitle: 'Total mensual',
                    amount: monthEarnings,
                    icon: '📆',
                    color: Colors.purple,
                    gradient: LinearGradient(
                      colors: [Colors.purple.shade400, Colors.purple.shade600],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// Calcula las ganancias para un rango de fechas específico
  static double _calculateEarnings(DateRange range) {
    try {
      final dateRange = _getDateRange(range);
      final startDate = dateRange['start']!;
      final endDate = dateRange['end']!;

      double totalEarnings = 0.0;

      // Sumar ventas (transactions con source 'venta')
      final transactionsBox = Hive.box<Transaction>('transactions');
      for (final transaction in transactionsBox.values) {
        if (transaction.source.toLowerCase() == 'venta' &&
            transaction.date.isAfter(startDate.subtract(const Duration(seconds: 1))) &&
            transaction.date.isBefore(endDate.add(const Duration(seconds: 1)))) {
          totalEarnings += transaction.amount;
        }
      }

      // Sumar turnos completados (appointments con completed = true)
      final appointmentsBox = Hive.box<Appointment>('appointments');
      for (final appointment in appointmentsBox.values) {
        if (appointment.completed &&
            appointment.dateTime.isAfter(startDate.subtract(const Duration(seconds: 1))) &&
            appointment.dateTime.isBefore(endDate.add(const Duration(seconds: 1)))) {
          totalEarnings += appointment.price;
        }
      }

      return totalEarnings;
    } catch (e) {
      // En caso de error, retornar 0
      return 0.0;
    }
  }

  /// Calcula las ganancias de ventas únicamente
  static double calculateSalesEarnings(DateRange range) {
    try {
      final dateRange = _getDateRange(range);
      final startDate = dateRange['start']!;
      final endDate = dateRange['end']!;

      double totalEarnings = 0.0;

      final transactionsBox = Hive.box<Transaction>('transactions');
      for (final transaction in transactionsBox.values) {
        if (transaction.source.toLowerCase() == 'venta' &&
            transaction.date.isAfter(startDate.subtract(const Duration(seconds: 1))) &&
            transaction.date.isBefore(endDate.add(const Duration(seconds: 1)))) {
          totalEarnings += transaction.amount;
        }
      }

      return totalEarnings;
    } catch (e) {
      return 0.0;
    }
  }

  /// Calcula las ganancias de turnos únicamente
  static double calculateAppointmentEarnings(DateRange range) {
    try {
      final dateRange = _getDateRange(range);
      final startDate = dateRange['start']!;
      final endDate = dateRange['end']!;

      double totalEarnings = 0.0;

      final appointmentsBox = Hive.box<Appointment>('appointments');
      for (final appointment in appointmentsBox.values) {
        if (appointment.completed &&
            appointment.dateTime.isAfter(startDate.subtract(const Duration(seconds: 1))) &&
            appointment.dateTime.isBefore(endDate.add(const Duration(seconds: 1)))) {
          totalEarnings += appointment.price;
        }
      }

      return totalEarnings;
    } catch (e) {
      return 0.0;
    }
  }

  /// Obtiene el rango de fechas según el tipo solicitado
  static Map<String, DateTime> _getDateRange(DateRange range) {
    final now = DateTime.now();
    
    switch (range) {
      case DateRange.today:
        final startOfDay = DateTime(now.year, now.month, now.day);
        final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);
        return {'start': startOfDay, 'end': endOfDay};
        
      case DateRange.week:
        // Obtener el lunes de esta semana
        final mondayOfWeek = now.subtract(Duration(days: now.weekday - 1));
        final startOfWeek = DateTime(mondayOfWeek.year, mondayOfWeek.month, mondayOfWeek.day);
        final endOfWeek = DateTime(now.year, now.month, now.day, 23, 59, 59);
        return {'start': startOfWeek, 'end': endOfWeek};
        
      case DateRange.month:
        final startOfMonth = DateTime(now.year, now.month, 1);
        final endOfMonth = DateTime(now.year, now.month, now.day, 23, 59, 59);
        return {'start': startOfMonth, 'end': endOfMonth};
    }
  }
}

/// Widget mejorado para cada tarjeta de resumen
class _EnhancedSummaryCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final double amount;
  final String icon;
  final Color color;
  final Gradient gradient;

  const _EnhancedSummaryCard({
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.icon,
    required this.color,
    required this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: isDark ? null : gradient,
        color: isDark ? Colors.grey.shade700 : null,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark 
              ? color.withValues(alpha: 0.3) 
              : Colors.white.withValues(alpha: 0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark 
                ? Colors.black.withValues(alpha: 0.4) 
                : color.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        children: [
          // Ícono emoji con fondo
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: isDark 
                  ? Colors.white.withValues(alpha: 0.1) 
                  : Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark 
                    ? Colors.white.withValues(alpha: 0.2) 
                    : Colors.white.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Center(
              child: Text(
                icon,
                style: const TextStyle(fontSize: 28),
              ),
            ),
          ),
          const SizedBox(width: 16),
          
          // Contenido de texto
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Título
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                
                // Subtítulo
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isDark 
                        ? Colors.grey.shade300 
                        : Colors.white.withValues(alpha: 0.9),
                  ),
                ),
                const SizedBox(height: 8),
                
                // Monto
                Row(
                  children: [
                    Text(
                      '\$',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white70 : Colors.white70,
                      ),
                    ),
                    Text(
                      _formatAmount(amount),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Indicador visual
          Container(
            width: 4,
            height: 60,
            decoration: BoxDecoration(
              color: isDark 
                  ? Colors.white.withValues(alpha: 0.7) 
                  : Colors.white.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }

  /// Formatea el monto con separadores de miles
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

/// Enum para los rangos de fechas disponibles
enum DateRange {
  today,
  week,
  month,
}