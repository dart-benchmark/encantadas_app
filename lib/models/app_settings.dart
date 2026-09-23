import 'package:hive/hive.dart';

part 'app_settings.g.dart';

@HiveType(typeId: 6)
class AppSettings extends HiveObject {
  @HiveField(0)
  bool autoQRMode;

  @HiveField(1)
  bool showConfirmationDialogs;

  @HiveField(2)
  bool enableNotifications;

  @HiveField(3)
  String defaultSaleType;

  AppSettings({
    this.autoQRMode = false,
    this.showConfirmationDialogs = true,
    this.enableNotifications = true,
    this.defaultSaleType = 'venta',
  });

  // Singleton pattern for app settings
  static AppSettings? _instance;
  
  static AppSettings get instance {
    if (_instance == null) {
      final box = Hive.box<AppSettings>('settings');
      if (box.isNotEmpty) {
        _instance = box.values.first;
      } else {
        _instance = AppSettings();
        box.add(_instance!);
      }
    }
    return _instance!;
  }

  // Save changes to Hive
  Future<void> saveSettings() async {
    await save();
  }

  // Helper methods
  String get autoQRModeText {
    return autoQRMode ? 'Activado' : 'Desactivado';
  }

  String get autoQRModeDescription {
    return autoQRMode 
        ? 'Los QR se procesan automáticamente sin confirmación'
        : 'Los QR requieren confirmación antes de procesar';
  }

  /// Convert settings to JSON for backup
  Map<String, dynamic> toJson() {
    return {
      'autoQRMode': autoQRMode,
      'showConfirmationDialogs': showConfirmationDialogs,
      'enableNotifications': enableNotifications,
      'defaultSaleType': defaultSaleType,
    };
  }

  /// Create settings from JSON for restore
  static AppSettings fromJson(Map<String, dynamic> json) {
    return AppSettings(
      autoQRMode: json['autoQRMode'] as bool? ?? false,
      showConfirmationDialogs: json['showConfirmationDialogs'] as bool? ?? true,
      enableNotifications: json['enableNotifications'] as bool? ?? true,
      defaultSaleType: json['defaultSaleType'] as String? ?? 'venta',
    );
  }
}