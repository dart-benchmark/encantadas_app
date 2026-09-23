import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:html' as html;

import 'theme/theme.dart';
import 'models/appointment.dart';
import 'models/transaction.dart';
import 'models/product.dart';
import 'models/provider.dart';
import 'models/app_settings.dart';
import 'models/cliente.dart';
import 'models/cuenta_corriente.dart';
import 'models/movimiento_cuenta.dart';
import 'widgets/add_appointment_form.dart';
import 'widgets/add_product_form.dart';
import 'widgets/add_provider_form.dart';
import 'widgets/add_sale_form.dart';
import 'screens/home_screen.dart';
import 'screens/turnos_screen.dart';
import 'screens/stock_screen.dart';
import 'screens/ventas_screen.dart';
import 'screens/balance_screen.dart';
import 'screens/providers_screen.dart';
import 'screens/cuenta_corriente_screen.dart';
import 'widgets/qr_processing_dialog.dart';
import 'services/backup_service.dart';
import 'services/pocketbase_sync_service.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Hive.initFlutter();
  
  // Register Hive adapters
  Hive.registerAdapter(AppointmentAdapter());
  Hive.registerAdapter(TransactionAdapter());
  Hive.registerAdapter(ProductCategoryAdapter());
  Hive.registerAdapter(ProductAdapter());
  Hive.registerAdapter(ProviderAdapter());
  Hive.registerAdapter(AppSettingsAdapter());
  Hive.registerAdapter(ClienteAdapter());
  Hive.registerAdapter(CuentaCorrienteAdapter());
  Hive.registerAdapter(TipoMovimientoAdapter());
  Hive.registerAdapter(MovimientoCuentaAdapter());
  
  // Open Hive boxes
  await Hive.openBox<Appointment>('appointments');
  await Hive.openBox<Transaction>('transactions');
  await Hive.openBox<Product>('products');
  await Hive.openBox<Provider>('providers');
  await Hive.openBox<AppSettings>('settings');
  await Hive.openBox<Cliente>('clientes_cuenta');
  await Hive.openBox<CuentaCorriente>('cuentas_corrientes');
  await Hive.openBox<MovimientoCuenta>('movimientos_cuenta');
  await Hive.openBox<String>('pagos_pendientes_verificacion');

  await initializeNotifications();
  
  // Initialize backup service (Drive legacy + nuevo PocketBase sync)
  await BackupService.instance.initialize();
  await PocketBaseSyncService.instance.initialize();

  runApp(const EncantadasApp());
}

Future<void> initializeNotifications() async {
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const DarwinInitializationSettings initializationSettingsIOS =
      DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );

  const LinuxInitializationSettings initializationSettingsLinux =
      LinuxInitializationSettings(
    defaultActionName: 'Open notification',
  );

  const InitializationSettings initializationSettings =
      InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsIOS,
    linux: initializationSettingsLinux,
  );

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: (NotificationResponse response) {
      // Handle notification tap
    },
  );
}

class EncantadasApp extends StatefulWidget {
  const EncantadasApp({super.key});

  @override
  State<EncantadasApp> createState() => _EncantadasAppState();
}

class _EncantadasAppState extends State<EncantadasApp> {
  ThemeMode _themeMode = ThemeMode.light;
  String? _initialQRCode;

  @override
  void initState() {
    super.initState();
    _checkUrlParameters();
  }

  void _checkUrlParameters() {
    try {
      final uri = Uri.parse(html.window.location.href);
      final qrCode = uri.queryParameters['qr'];
      if (qrCode != null && qrCode.isNotEmpty) {
        _initialQRCode = qrCode;
        // Clear the URL parameter for clean navigation
        html.window.history.replaceState(
          null, 
          'Encantadas', 
          uri.origin + uri.path
        );
      }
    } catch (e) {
      // Handle any parsing errors silently
    }
  }

  void toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.light 
          ? ThemeMode.dark 
          : ThemeMode.light;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Encantadas',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _themeMode,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('es', 'ES'),
      ],
      locale: const Locale('es', 'ES'),
      home: MainNavigationScreen(
        onThemeToggle: toggleTheme,
        initialQRCode: _initialQRCode,
      ),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  final VoidCallback onThemeToggle;
  final String? initialQRCode;
  
  const MainNavigationScreen({
    super.key,
    required this.onThemeToggle,
    this.initialQRCode,
  });

  @override
  State<MainNavigationScreen> createState() => MainNavigationScreenState();
}

// Indices estables del bottom nav. Si reordenas la lista de pantallas
// actualiza estas constantes — el deep link de QR (kTabVentas) y los
// FABs por pantalla dependen de estos valores.
class NavTab {
  static const int home = 0;
  static const int turnos = 1;
  static const int stock = 2;
  static const int ventas = 3;
  static const int balance = 4;
  static const int providers = 5;
  static const int fiado = 6;
}

class MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = NavTab.home;

  @override
  void initState() {
    super.initState();
    // If there's an initial QR code, navigate to sales and process it
    if (widget.initialQRCode != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleExternalQRCode(widget.initialQRCode!);
      });
    }
  }

  void _handleExternalQRCode(String qrCode) {
    setState(() {
      _selectedIndex = NavTab.ventas;
    });

    // Show QR processing dialog after a short delay
    Future.delayed(const Duration(milliseconds: 500), () {
      _processExternalQRCode(qrCode);
    });
  }

  void _processExternalQRCode(String qrCode) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => QRProcessingDialog(qrCode: qrCode),
    );
  }

  final List<Widget> _screens = [
    const HomeScreen(),
    const TurnosScreen(),
    const StockScreen(),
    const VentasScreen(),
    const BalanceScreen(),
    const ProvidersScreen(),
    const CuentaCorrienteScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _selectedIndex == index;
    return Flexible(
      child: InkWell(
        onTap: () => _onItemTapped(index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isSelected 
                    ? Theme.of(context).primaryColor 
                    : Colors.grey,
                size: 18,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: isSelected 
                      ? Theme.of(context).primaryColor 
                      : Colors.grey,
                  fontSize: 8,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Método público para navegación desde HomeScreen
  void navigateToTab(int index) {
    _onItemTapped(index);
  }

  // Get the FAB for the current screen
  Widget? _getCurrentFAB() {
    switch (_selectedIndex) {
      case NavTab.turnos:
        return FloatingActionButton(
          onPressed: () {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (context) => const AddAppointmentForm(),
            );
          },
          tooltip: 'Agregar nuevo turno',
          child: const Icon(Icons.add),
        );
      case NavTab.stock:
        return FloatingActionButton(
          onPressed: () {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (context) => const AddProductForm(),
            );
          },
          tooltip: 'Agregar nuevo producto',
          child: const Icon(Icons.add),
        );
      case NavTab.ventas:
        return FloatingActionButton(
          onPressed: () {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (context) => const AddSaleForm(),
            );
          },
          tooltip: 'Registrar nueva venta',
          child: const Icon(Icons.add),
        );
      case NavTab.providers:
        return FloatingActionButton(
          onPressed: () {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (context) => const AddProviderForm(),
            );
          },
          tooltip: 'Agregar nuevo proveedor',
          child: const Icon(Icons.add),
        );
      case NavTab.fiado:
        return null; // La pantalla maneja su propio FAB
      default:
        return FloatingActionButton(
          onPressed: widget.onThemeToggle,
          tooltip: 'Cambiar tema',
          child: Icon(
            Theme.of(context).brightness == Brightness.light
                ? Icons.dark_mode
                : Icons.light_mode,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: Container(
        height: 60,
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 4,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildNavItem(NavTab.home, Icons.home, 'Inicio'),
            _buildNavItem(NavTab.turnos, Icons.schedule, 'Turnos'),
            _buildNavItem(NavTab.stock, Icons.inventory, 'Stock'),
            _buildNavItem(NavTab.ventas, Icons.shopping_cart, 'Ventas'),
            _buildNavItem(NavTab.balance, Icons.account_balance, 'Balance'),
            _buildNavItem(NavTab.providers, Icons.people, 'Proveed.'),
            _buildNavItem(NavTab.fiado, Icons.account_balance_wallet, 'Fiado'),
          ],
        ),
      ),
      floatingActionButton: _getCurrentFAB(),
    );
  }
}