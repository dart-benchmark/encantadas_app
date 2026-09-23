import 'package:flutter/material.dart';
import '../widgets/balance_summary_card.dart';
import '../widgets/pie_chart_card.dart';
import '../widgets/sales_type_summary_card.dart';

class BalanceScreen extends StatelessWidget {
  const BalanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Balance'),
        backgroundColor: Theme.of(context).brightness == Brightness.dark 
            ? Colors.grey.shade900 
            : Colors.green.shade50,
        elevation: 0,
      ),
      backgroundColor: Theme.of(context).brightness == Brightness.dark 
          ? Colors.grey.shade900 
          : Colors.grey.shade50,
      body: const SingleChildScrollView(
        child: Column(
          children: [
            // Tarjeta de resumen de ganancias
            BalanceSummaryCard(),
            
            // Resumen de ventas por tipo (productos y servicios)
            SalesTypeSummaryCard(),
            
            // Gráfico de torta con desglose turnos vs ventas
            PieChartCard(),
            
            // Espaciador para contenido futuro
            SizedBox(height: 20),
            
            // Aquí puedes agregar más widgets en el futuro
            // Por ejemplo: historial detallado, filtros por fecha, etc.
          ],
        ),
      ),
    );
  }
}