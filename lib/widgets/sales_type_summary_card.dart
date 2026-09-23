import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/transaction.dart';
import '../models/appointment.dart';

class SalesTypeSummaryCard extends StatelessWidget {
  const SalesTypeSummaryCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: Hive.box<Transaction>('transactions').listenable(),
      builder: (context, _, __) {
        return ValueListenableBuilder(
          valueListenable: Hive.box<Appointment>('appointments').listenable(),
          builder: (context, __, ___) {
        final salesCounts = _calculateSalesCounts();
        
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
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.analytics,
                      color: Colors.orange,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Resumen de Ventas',
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).brightness == Brightness.dark 
                                ? Colors.white 
                                : Colors.grey.shade800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Conteo por tipo de servicio',
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
              Row(
                children: [
                  Expanded(
                    child: _SalesTypeCard(
                      title: 'Productos',
                      subtitle: 'Vendidos',
                      count: salesCounts['products'] ?? 0,
                      icon: '🛍️',
                      color: Colors.green,
                      gradient: LinearGradient(
                        colors: [Colors.green.shade400, Colors.green.shade600],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _SalesTypeCard(
                      title: 'Servicios',
                      subtitle: 'Realizados',
                      count: salesCounts['services'] ?? 0,
                      icon: '💅',
                      color: Colors.purple,
                      gradient: LinearGradient(
                        colors: [Colors.purple.shade400, Colors.purple.shade600],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
          },
        );
      },
    );
  }

  /// Calcula el conteo de ventas por tipo
  Map<String, int> _calculateSalesCounts() {
    int productsSold = 0;
    int servicesCompleted = 0;

    try {
      // Contar productos vendidos (transactions con source 'venta')
      final transactionsBox = Hive.box<Transaction>('transactions');
      for (final transaction in transactionsBox.values) {
        if (transaction.source.toLowerCase() == 'venta' && 
            transaction.isProductSale && 
            transaction.quantity != null) {
          productsSold += transaction.quantity!;
        }
      }

      // Contar servicios realizados (appointments completados)
      final appointmentsBox = Hive.box<Appointment>('appointments');
      for (final appointment in appointmentsBox.values) {
        if (appointment.completed) {
          servicesCompleted++;
        }
      }
    } catch (e) {
      // En caso de error, retornar valores por defecto
      productsSold = 0;
      servicesCompleted = 0;
    }

    return {
      'products': productsSold,
      'services': servicesCompleted,
    };
  }
}

/// Widget individual para cada tipo de venta
class _SalesTypeCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final int count;
  final String icon;
  final Color color;
  final Gradient gradient;

  const _SalesTypeCard({
    required this.title,
    required this.subtitle,
    required this.count,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
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
          const SizedBox(height: 16),
          
          // Título
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          
          // Subtítulo
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isDark 
                  ? Colors.grey.shade300 
                  : Colors.white.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 12),
          
          // Contador
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isDark 
                  ? Colors.white.withValues(alpha: 0.1) 
                  : Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark 
                    ? Colors.white.withValues(alpha: 0.2) 
                    : Colors.white.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Text(
              _formatCount(count),
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.white,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Formatea el contador con separadores de miles si es necesario
  String _formatCount(int count) {
    if (count < 1000) {
      return count.toString();
    }
    
    // Para números grandes, agregar separadores de miles
    final countString = count.toString();
    String formattedCount = '';
    for (int i = 0; i < countString.length; i++) {
      if (i > 0 && (countString.length - i) % 3 == 0) {
        formattedCount += '.';
      }
      formattedCount += countString[i];
    }
    
    return formattedCount;
  }
}