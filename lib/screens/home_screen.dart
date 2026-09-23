import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/appointment.dart';
import '../models/product.dart';
import '../models/provider.dart';
import '../main.dart';
import 'settings_screen.dart';
import '../widgets/alerta_cuentas_morosas.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Encantadas'),
        elevation: 0,
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Alertas de cuentas morosas
            const AlertaCuentasMorosas(),
            
            // Bienvenida
            _buildWelcomeCard(context),
            const SizedBox(height: 20),
            
            // Estadísticas rápidas
            _buildQuickStats(context),
            const SizedBox(height: 20),
            
            // Accesos rápidos
            _buildQuickActions(context),
            const SizedBox(height: 20),
            
            // Resumen de actividad reciente
            _buildRecentActivity(context),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeCard(BuildContext context) {
    return Card(
      elevation: 4,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [
              Theme.of(context).primaryColor,
              Theme.of(context).primaryColor.withValues(alpha: 0.7),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.waving_hand,
                  color: Colors.white,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '¡Bienvenida a Encantadas!',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Gestiona tu negocio de belleza de forma eficiente',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickStats(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Resumen de Hoy',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                context,
                'Turnos Hoy',
                Icons.schedule,
                Colors.blue,
                _getTodayAppointmentsCount(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                context,
                'Productos',
                Icons.inventory,
                Colors.orange,
                _getTotalProductsCount(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                context,
                'Proveedores',
                Icons.business,
                Colors.green,
                _getTotalProvidersCount(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                context,
                'Sin Stock',
                Icons.warning,
                Colors.red,
                _getOutOfStockCount(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard(BuildContext context, String title, IconData icon,
      Color color, ValueListenableBuilder<Box> valueBuilder) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(
              icon,
              color: color,
              size: 32,
            ),
            const SizedBox(height: 8),
            valueBuilder,
            const SizedBox(height: 4),
            Text(
              title,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Acciones Rápidas',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildActionCard(
                context,
                'Nuevo Turno',
                Icons.add_circle,
                Colors.blue,
                () => _navigateToTab(context, 1),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionCard(
                context,
                'Agregar Producto',
                Icons.inventory_2,
                Colors.orange,
                () => _navigateToTab(context, 2),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildActionCard(
                context,
                'Nueva Venta',
                Icons.shopping_cart,
                Colors.green,
                () => _navigateToTab(context, 3),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionCard(
                context,
                'Ver Balance',
                Icons.account_balance,
                Colors.purple,
                () => _navigateToTab(context, 4),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildActionCard(
                context,
                'Configuraciones',
                Icons.settings,
                Colors.grey,
                () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const SettingsScreen(),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(child: SizedBox()), // Empty space for symmetry
          ],
        ),
      ],
    );
  }

  Widget _buildActionCard(BuildContext context, String title, IconData icon,
      Color color, VoidCallback onTap) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: 28,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentActivity(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Actividad Reciente',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        ValueListenableBuilder<Box<Appointment>>(
          valueListenable: Hive.box<Appointment>('appointments').listenable(),
          builder: (context, appointmentsBox, _) {
            return ValueListenableBuilder<Box<Product>>(
              valueListenable: Hive.box<Product>('products').listenable(),
              builder: (context, productsBox, _) {
                final recentAppointments = appointmentsBox.values
                    .toList()
                    .cast<Appointment>()
                    ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
                
                final recentProducts = productsBox.values
                    .toList()
                    .cast<Product>()
                    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

                return Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (recentAppointments.isNotEmpty) ...[
                          Text(
                            'Último turno: ${recentAppointments.first.clientName}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 8),
                        ],
                        if (recentProducts.isNotEmpty) ...[
                          Text(
                            'Último producto agregado: ${recentProducts.first.name}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 8),
                        ],
                        if (recentAppointments.isEmpty && recentProducts.isEmpty)
                          Text(
                            'No hay actividad reciente. ¡Comienza agregando tu primer turno o producto!',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.grey[600],
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  ValueListenableBuilder<Box<Appointment>> _getTodayAppointmentsCount() {
    return ValueListenableBuilder<Box<Appointment>>(
      valueListenable: Hive.box<Appointment>('appointments').listenable(),
      builder: (context, box, _) {
        final today = DateTime.now();
        final todayAppointments = box.values.where((appointment) {
          final appointmentDate = appointment.dateTime;
          return appointmentDate.year == today.year &&
                 appointmentDate.month == today.month &&
                 appointmentDate.day == today.day;
        }).length;
        
        return Text(
          todayAppointments.toString(),
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        );
      },
    );
  }

  ValueListenableBuilder<Box<Product>> _getTotalProductsCount() {
    return ValueListenableBuilder<Box<Product>>(
      valueListenable: Hive.box<Product>('products').listenable(),
      builder: (context, box, _) {
        return Text(
          box.length.toString(),
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        );
      },
    );
  }

  ValueListenableBuilder<Box<Provider>> _getTotalProvidersCount() {
    return ValueListenableBuilder<Box<Provider>>(
      valueListenable: Hive.box<Provider>('providers').listenable(),
      builder: (context, box, _) {
        return Text(
          box.length.toString(),
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        );
      },
    );
  }

  ValueListenableBuilder<Box<Product>> _getOutOfStockCount() {
    return ValueListenableBuilder<Box<Product>>(
      valueListenable: Hive.box<Product>('products').listenable(),
      builder: (context, box, _) {
        final outOfStock = box.values.where((product) => product.quantity == 0).length;
        return Text(
          outOfStock.toString(),
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: outOfStock > 0 ? Colors.red : null,
          ),
        );
      },
    );
  }

  void _navigateToTab(BuildContext context, int tabIndex) {
    // Buscar el MainNavigationScreen en el widget tree y cambiar de pestaña
    final mainNavState = context.findAncestorStateOfType<MainNavigationScreenState>();
    if (mainNavState != null) {
      mainNavState.navigateToTab(tabIndex);
    }
  }
}

// Necesitamos hacer la clase accesible para el método _navigateToTab
extension MainNavigationScreenExtension on BuildContext {
  void navigateToTab(int index) {
    // Esta es una forma más limpia de manejar la navegación entre pestañas
    // pero requeriría cambios adicionales en main.dart
  }
}