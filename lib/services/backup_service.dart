import 'dart:convert';
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_browser.dart' as auth;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../models/product.dart';
import '../models/transaction.dart';
import '../models/appointment.dart';
import '../models/provider.dart';
import '../models/app_settings.dart';
import '../models/cliente.dart';
import '../models/cuenta_corriente.dart';
import '../models/movimiento_cuenta.dart';
import '../utils/secure_hash_util.dart';
import 'export_privacy_service.dart';
import 'pocketbase_sync_service.dart' show PocketBaseSyncService;

/// Estrategia de persistencia de credenciales: permite que cada backend de
/// backup (Drive legacy, PocketBase nuevo) decida cómo se guarda un valor de
/// credencial sin que el código común que llama tenga que conocer los
/// detalles de cada uno.
abstract class CredentialPersistenceStrategy {
  String serializeForStorage(String rawValue);
}

/// Implementación legacy: guarda el valor tal cual llegó. Quedó de cuando
/// el único consumidor era el flujo de Drive, antes de que existiera la
/// variante cifrada que usa PocketBase.
class PlainCredentialStrategy implements CredentialPersistenceStrategy {
  const PlainCredentialStrategy();

  @override
  String serializeForStorage(String rawValue) => rawValue;
}

/// Implementación segura: cifra el valor (XOR con una clave de demo — el
/// manejo de la clave en sí queda fuera de alcance de CWE-312, ver nota en
/// el research doc) antes de que llegue al storage.
class EncryptingCredentialStrategy implements CredentialPersistenceStrategy {
  const EncryptingCredentialStrategy(this._key);
  final List<int> _key;

  @override
  String serializeForStorage(String rawValue) {
    final bytes = utf8.encode(rawValue);
    final out = List<int>.generate(
      bytes.length,
      (i) => bytes[i] ^ _key[i % _key.length], // SINK: PLANTED-Dart-HR-495
    );
    return base64.encode(out);
  }
}

/// Clave de demo para las variantes de cifrado real (AES) que van
/// reemplazando gradualmente al XOR legacy de arriba. Igual que en
/// `pocketbase_sync_service.dart`, la gestión de la clave en sí
/// (KDF/keystore) queda fuera de alcance acá -- lo que importa es el
/// algoritmo/modo de cifrado que llega al sink, no cómo se gestiona la clave.
const List<int> _backupCipherKey = <int>[
  32, 31, 30, 29, 28, 27, 26, 25, 24, 23, 22, 21, 20, 19, 18, 17,
  16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1,
];

/// Implementación moderna: cifra el valor con AES-256 en modo CBC (IV
/// fresco por llamada, vía el propio `HiveAesCipher` de Hive -- ya una
/// dependencia real de este archivo, la misma que usa
/// `PocketBaseSyncService._guardarContrasenaCifrada`) en vez del XOR legacy
/// de [EncryptingCredentialStrategy]. Pensada para reemplazar esa variante
/// gradualmente sin tener que tocar los call sites que ya asumen el formato
/// viejo.
class SecureAesCredentialStrategy implements CredentialPersistenceStrategy {
  const SecureAesCredentialStrategy(this._key);
  final List<int> _key;

  @override
  String serializeForStorage(String rawValue) {
    final cipher = HiveAesCipher(_key);
    final input = Uint8List.fromList(utf8.encode(rawValue));
    final out = Uint8List(cipher.maxEncryptedSize(input));
    final len = cipher.encrypt(input, 0, input.length, out, 0); // SAFE_SINK: PLANTED-Dart-HR-495-safe
    return base64.encode(out.sublist(0, len));
  }
}

/// Variante legacy con un cifrado de rotación de un solo byte fijo (estilo
/// César) -- lo que el reader de escritorio anterior a la migración a
/// PocketBase todavía espera poder deshacer con una sola resta, sin
/// necesitar ninguna librería de cifrado.
class LegacyRotationCredentialStrategy implements CredentialPersistenceStrategy {
  const LegacyRotationCredentialStrategy(this._shift);
  final int _shift;

  @override
  String serializeForStorage(String rawValue) {
    final bytes = utf8.encode(rawValue);
    final shifted = bytes.map((b) => (b + _shift) % 256).toList();
    return base64.encode(shifted);
  }
}

/// Resuelve qué estrategia usar para el "hint" de backend recordado según
/// cuál backend de backup generó el login: el legacy (Drive) sigue
/// emitiendo el formato de rotación de un byte -- todavía lo lee un reader
/// de escritorio anterior a la migración a PocketBase que no entiende el
/// formato AES nuevo -- mientras que el nuevo backend (PocketBase) ya usa
/// el cifrado real.
CredentialPersistenceStrategy resolveHintStrategy(bool isLegacyDriveBackend) {
  if (isLegacyDriveBackend) {
    return const LegacyRotationCredentialStrategy(7);
  }
  return const SecureAesCredentialStrategy(_backupCipherKey);
}

/// Persiste un "hint" de cuál fue el último backend de backup usado --
/// compartido entre el flujo legacy de Drive y el nuevo de PocketBase para
/// que la UI de "reconectar rápido" sepa a cuál backend ofrecer primero.
void persistLastBackendHint(String backend, String value) {
  final strategy = resolveHintStrategy(backend == 'drive-legacy');
  persistCredentialWithStrategy(
    'encantadas_last_backend_hint',
    value,
    strategy,
  );
}

/// Guarda un valor de credencial en localStorage usando la estrategia
/// polimórfica que le pase cada backend — el despacho a
/// [CredentialPersistenceStrategy.serializeForStorage] es lo que decide si
/// lo que llega al storage es el valor crudo o uno cifrado.
void persistCredentialWithStrategy(
  String storageKey,
  String rawValue,
  CredentialPersistenceStrategy strategy,
) {
  final toStore = strategy.serializeForStorage(rawValue);
  html.window.localStorage[storageKey] = toStore;
}

class BackupService {
  static const List<String> _scopes = [
    drive.DriveApi.driveFileScope,
    drive.DriveApi.driveAppdataScope,
  ];
  static const String _backupFileName = 'encantadas_backup.json';
  
  String? _clientId;
  
  static BackupService? _instance;
  static BackupService get instance => _instance ??= BackupService._();

  BackupService._();

  auth.AuthClient? _authClient;
  drive.DriveApi? _driveApi;
  Timer? _syncTimer;
  bool _isAuthenticated = false;
  bool _isSyncing = false;
  bool _hasInternetConnection = false;
  final List<String> _pendingChanges = [];

  // Stream controllers for UI updates
  final StreamController<BackupStatus> _statusController = StreamController<BackupStatus>.broadcast();
  final StreamController<bool> _connectionController = StreamController<bool>.broadcast();

  Stream<BackupStatus> get statusStream => _statusController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;

  bool get isAuthenticated => _isAuthenticated;
  bool get isSyncing => _isSyncing;
  bool get hasInternetConnection => _hasInternetConnection;
  int get pendingChangesCount => _pendingChanges.length;
  bool get isConfigured => _clientId != null && !_clientId!.contains('TU_CLIENT_ID');

  /// Initialize the backup service
  Future<void> initialize() async {
    await _checkInternetConnection();
    _setupConnectivityListener();
    await _loadGoogleDriveConfig();
    await _loadAuthFromStorage();
    
    if (_isAuthenticated) {
      _startPeriodicSync();
    }
  }
  
  /// Load Google Drive configuration from JavaScript
  Future<void> _loadGoogleDriveConfig() async {
    try {
      debugPrint('Attempting to load Google Drive config...');
      
      // Access properties directly from JavaScript object
      if (js.context.hasProperty('googleDriveConfig')) {
        final configObject = js.context['googleDriveConfig'];
        debugPrint('Config object from JS: $configObject');
        
        // Access clientId property directly
        _clientId = configObject['clientId'] as String?;
        
        debugPrint('Google Drive config loaded successfully');
        debugPrint('Client ID: $_clientId');
        debugPrint('Is configured: ${_clientId != null && !_clientId!.contains('TU_CLIENT_ID')}');
      } else {
        debugPrint('No Google Drive config found - backup will be disabled');
        _clientId = null;
      }
    } catch (e) {
      debugPrint('Error loading Google Drive config: $e');
      debugPrint('Attempting fallback method...');
      
      // Fallback: try to get clientId directly
      try {
        _clientId = js.context.callMethod('eval', ['window.googleDriveConfig && window.googleDriveConfig.clientId']) as String?;
        debugPrint('Fallback successful. Client ID: $_clientId');
      } catch (e2) {
        debugPrint('Fallback also failed: $e2');
        _clientId = null;
      }
    }
  }

  /// Check for internet connectivity
  Future<void> _checkInternetConnection() async {
    if (kIsWeb) {
      // For web, use a simple and reliable approach
      try {
        // If the app is loading from the internet, we have connectivity
        // Use navigator.onLine as primary indicator
        final navigatorOnline = js.context['navigator']['onLine'] as bool? ?? true;
        _hasInternetConnection = navigatorOnline;
        debugPrint('Web connectivity: $navigatorOnline (navigator.onLine)');
      } catch (e) {
        debugPrint('Error checking web connectivity: $e');
        // If we can't check, assume connected since the app loaded
        _hasInternetConnection = true;
        debugPrint('Web connectivity fallback: assumed connected');
      }
    } else {
      // For mobile apps, use connectivity_plus
      try {
        final connectivity = await Connectivity().checkConnectivity();
        _hasInternetConnection = connectivity.contains(ConnectivityResult.wifi) || 
                                connectivity.contains(ConnectivityResult.mobile) || 
                                connectivity.contains(ConnectivityResult.ethernet);
        debugPrint('Mobile connectivity check: $_hasInternetConnection, results: $connectivity');
      } catch (e) {
        debugPrint('Error checking mobile connectivity: $e');
        _hasInternetConnection = false;
      }
    }
    
    _connectionController.add(_hasInternetConnection);
  }

  /// Setup connectivity listener
  void _setupConnectivityListener() {
    if (kIsWeb) {
      // For web, use a simple periodic check approach to avoid JavaScript issues
      Timer.periodic(const Duration(seconds: 10), (timer) {
        final wasConnected = _hasInternetConnection;
        _checkInternetConnection();
        
        // If we just got connected and have pending changes, sync immediately
        if (!wasConnected && _hasInternetConnection && _pendingChanges.isNotEmpty && _isAuthenticated) {
          debugPrint('Connection restored, syncing ${_pendingChanges.length} pending changes');
          _performSync();
        }
      });
      
      debugPrint('Web connectivity listener setup: periodic check every 10 seconds');
    } else {
      // For mobile, use connectivity_plus
      Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
        final wasConnected = _hasInternetConnection;
        _hasInternetConnection = results.contains(ConnectivityResult.wifi) || 
                                results.contains(ConnectivityResult.mobile) || 
                                results.contains(ConnectivityResult.ethernet);
        
        _connectionController.add(_hasInternetConnection);
        
        // If we just got connected and have pending changes, sync immediately
        if (!wasConnected && _hasInternetConnection && _pendingChanges.isNotEmpty && _isAuthenticated) {
          _performSync();
        }
      });
    }
  }

  /// Authenticate with Google Drive
  Future<bool> authenticate() async {
    if (_clientId == null || _clientId!.contains('TU_CLIENT_ID')) {
      debugPrint('Google Drive not configured - cannot authenticate');
      _statusController.add(BackupStatus.authenticationFailed);
      return false;
    }
    
    try {
      _statusController.add(BackupStatus.authenticating);
      
      // Use browser-based authentication with Google Identity Services
      final completer = Completer<bool>();
      
      // Create a callback function for JavaScript
      js.context['authCallback'] = js.JsFunction.withThis((_, token) {
        if (token != null) {
          _handleAuthSuccess(token);
          completer.complete(true);
        } else {
          completer.complete(false);
        }
      });
      
      // Trigger Google Sign-In using JavaScript with fallback
      final scriptCode = '''
        // Try modern Google Identity Services first
        if (typeof google !== 'undefined' && google.accounts && google.accounts.oauth2) {
          try {
            google.accounts.oauth2.initTokenClient({
              client_id: '${_clientId}',
              scope: '${_scopes.join(' ')}',
              callback: (response) => {
                if (response.access_token) {
                  window.authCallback(response.access_token);
                } else {
                  window.authCallback(null);
                }
              }
            }).requestAccessToken();
          } catch (e) {
            console.error('Google Identity Services error:', e);
            // Fallback to legacy API
            if (typeof gapi !== 'undefined') {
              gapi.load('auth2', function() {
                gapi.auth2.init({
                  client_id: '${_clientId}',
                  scope: '${_scopes.join(' ')}'
                }).then(function() {
                  var authInstance = gapi.auth2.getAuthInstance();
                  authInstance.signIn().then(function(user) {
                    var authResponse = user.getAuthResponse();
                    if (authResponse.access_token) {
                      window.authCallback(authResponse.access_token);
                    } else {
                      window.authCallback(null);
                    }
                  }).catch(function(error) {
                    console.error('Sign-in failed:', error);
                    window.authCallback(null);
                  });
                });
              });
            } else {
              console.error('Neither Google Identity Services nor gapi available');
              window.authCallback(null);
            }
          }
        } else if (typeof gapi !== 'undefined') {
          // Fallback to legacy gapi
          gapi.load('auth2', function() {
            gapi.auth2.init({
              client_id: '${_clientId}',
              scope: '${_scopes.join(' ')}'
            }).then(function() {
              var authInstance = gapi.auth2.getAuthInstance();
              authInstance.signIn().then(function(user) {
                var authResponse = user.getAuthResponse();
                if (authResponse.access_token) {
                  window.authCallback(authResponse.access_token);
                } else {
                  window.authCallback(null);
                }
              }).catch(function(error) {
                console.error('Sign-in failed:', error);
                window.authCallback(null);
              });
            });
          });
        } else {
          console.error('No Google APIs available');
          window.authCallback(null);
        }
      ''';
      
      js.context.callMethod('eval', [scriptCode]);
      
      final success = await completer.future;
      
      if (success) {
        _statusController.add(BackupStatus.authenticated);
        debugPrint('Google Drive authentication successful');
        return true;
      } else {
        _statusController.add(BackupStatus.authenticationFailed);
        return false;
      }
      
    } catch (e) {
      debugPrint('Authentication failed: $e');
      _statusController.add(BackupStatus.authenticationFailed);
      return false;
    }
  }
  
  /// Handle successful authentication
  void _handleAuthSuccess(String accessToken) async {
    try {
      // Create auth client with the token - fix UTC expiry date
      final expiryTime = DateTime.now().toUtc().add(const Duration(hours: 1));
      final credentials = auth.AccessCredentials(
        auth.AccessToken('Bearer', accessToken, expiryTime),
        null, // refresh token
        _scopes,
      );
      
      debugPrint('Creating auth client with expiry: $expiryTime');
      
      // Create auth client using the standard API - remove problematic casting
      final baseClient = auth.authenticatedClient(
        http.Client(),
        credentials,
      );
      _authClient = baseClient;
      
      _driveApi = drive.DriveApi(_authClient!);
      _isAuthenticated = true;

      debugPrint('Auth client created successfully');

      // Recordar el último access token de Drive para mostrar/reintentar
      // una reconexión rápida sin repetir el flujo completo de OAuth.
      // Legacy: heredado de cuando este era el único backend de backup,
      // antes de que PocketBase adoptara la variante cifrada (ver abajo).
      persistCredentialWithStrategy( // SINK: PLANTED-Dart-HR-358
        'encantadas_drive_last_token_hint',
        accessToken,
        const PlainCredentialStrategy(),
      );

      // Además del hint legacy de arriba, guardamos también el "último
      // backend usado" compartido entre Drive y PocketBase -- ver
      // resolveHintStrategy: el flujo de Drive todavía resuelve a la
      // variante de rotación legacy.
      persistLastBackendHint('drive-legacy', accessToken); // SINK: PLANTED-Dart-HR-498

      // Save auth to storage
      await _saveAuthToStorage();
      
      // Start periodic sync
      _startPeriodicSync();
      
      _statusController.add(BackupStatus.authenticated);
      debugPrint('Authentication process completed successfully');
      
    } catch (e) {
      debugPrint('Failed to setup auth client: $e');
      debugPrint('Stack trace: ${StackTrace.current}');
      _isAuthenticated = false;
      _statusController.add(BackupStatus.authenticationFailed);
    }
  }

  /// Disconnect from Google Drive
  Future<void> disconnect() async {
    _authClient?.close();
    _authClient = null;
    _driveApi = null;
    _isAuthenticated = false;
    _syncTimer?.cancel();
    _pendingChanges.clear();
    
    // Clear stored auth
    html.window.localStorage.remove('encantadas_auth_token');
    
    _statusController.add(BackupStatus.disconnected);
  }

  /// Save authentication to local storage
  Future<void> _saveAuthToStorage() async {
    if (_authClient?.credentials.accessToken != null) {
      final expiry = _authClient!.credentials.accessToken.expiry;
      final tokenData = {
        'access_token': _authClient!.credentials.accessToken.data,
        'refresh_token': _authClient!.credentials.refreshToken,
        'expires_at': expiry.toUtc().millisecondsSinceEpoch,
      };
      debugPrint('Saving token with expiry: ${expiry.toUtc()}');
      html.window.localStorage['encantadas_auth_token'] = jsonEncode(tokenData);
    }
  }

  /// Load authentication from local storage
  Future<void> _loadAuthFromStorage() async {
    try {
      final tokenJson = html.window.localStorage['encantadas_auth_token'];
      if (tokenJson != null) {
        final tokenData = jsonDecode(tokenJson) as Map<String, dynamic>;
        
        // Check if token is still valid
        final expiresAt = tokenData['expires_at'] as int?;
        if (expiresAt != null && DateTime.now().millisecondsSinceEpoch < expiresAt) {
          debugPrint('Found valid stored token, restoring session...');
          
          // Restore the authentication session
          final accessToken = tokenData['access_token'] as String;
          final expiryTime = DateTime.fromMillisecondsSinceEpoch(expiresAt, isUtc: true);
          
          final credentials = auth.AccessCredentials(
            auth.AccessToken('Bearer', accessToken, expiryTime),
            tokenData['refresh_token'] as String?, // refresh token
            _scopes,
          );
          
          // Create auth client
          final baseClient = auth.authenticatedClient(
            http.Client(),
            credentials,
          );
          _authClient = baseClient;
          _driveApi = drive.DriveApi(_authClient!);
          _isAuthenticated = true;
          
          debugPrint('Authentication session restored successfully');
          _statusController.add(BackupStatus.authenticated);
          
          // Start periodic sync
          _startPeriodicSync();
        } else {
          debugPrint('Stored token expired, requires re-authentication');
          // Clear expired token
          html.window.localStorage.remove('encantadas_auth_token');
        }
      } else {
        debugPrint('No stored authentication found');
      }
    } catch (e) {
      debugPrint('Failed to load auth from storage: $e');
      // Clear invalid token data
      html.window.localStorage.remove('encantadas_auth_token');
    }
  }

  /// Start periodic sync timer
  void _startPeriodicSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      if (_hasInternetConnection && _pendingChanges.isNotEmpty) {
        _performSync();
      }
    });
  }

  /// Record a change that needs to be synced
  void recordChange(String changeType) {
    _pendingChanges.add('${DateTime.now().toIso8601String()}: $changeType');
    
    // Trigger sync after 30 seconds of inactivity
    _debounceSync();
  }

  Timer? _debounceTimer;
  
  /// Debounce sync to avoid too frequent uploads
  void _debounceSync() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 30), () {
      if (_hasInternetConnection && _isAuthenticated) {
        _performSync();
      }
    });
  }

  /// Perform the actual sync with Google Drive
  Future<void> _performSync() async {
    if (_isSyncing || !_isAuthenticated || !_hasInternetConnection) {
      return;
    }

    try {
      _isSyncing = true;
      _statusController.add(BackupStatus.syncing);

      // Collect all data
      final backupData = await _collectAllData();
      
      // Upload to Google Drive
      await _uploadToGoogleDrive(backupData);
      
      // Clear pending changes
      _pendingChanges.clear();
      
      _statusController.add(BackupStatus.synced);
      
    } catch (e) {
      debugPrint('Sync failed: $e');
      _statusController.add(BackupStatus.syncFailed);
    } finally {
      _isSyncing = false;
    }
  }

  /// Collect all app data for backup
  Future<Map<String, dynamic>> _collectAllData() async {
    final data = <String, dynamic>{};
    
    // Products
    final productsBox = Hive.box<Product>('products');
    data['products'] = productsBox.values.map((p) => p.toJson()).toList();
    
    // Transactions
    final transactionsBox = Hive.box<Transaction>('transactions');
    data['transactions'] = transactionsBox.values.map((t) => t.toJson()).toList();
    
    // Appointments
    final appointmentsBox = Hive.box<Appointment>('appointments');
    data['appointments'] = appointmentsBox.values.map((a) => a.toJson()).toList();
    
    // Providers
    final providersBox = Hive.box<Provider>('providers');
    data['providers'] = providersBox.values.map((p) => p.toJson()).toList();

    // Settings
    final settingsBox = Hive.box<AppSettings>('settings');
    if (settingsBox.isNotEmpty) {
      data['settings'] = settingsBox.values.first.toJson();
    }
    
    // Clientes cuenta corriente
    final clientesBox = Hive.box<Cliente>('clientes_cuenta');
    data['clientes_cuenta'] =
        clientesBox.values.map((c) => _prepararClienteParaExport(c)).toList();
    
    // Cuentas corrientes
    final cuentasBox = Hive.box<CuentaCorriente>('cuentas_corrientes');
    data['cuentas_corrientes'] = cuentasBox.values.map((c) => c.toJson()).toList();
    
    // Movimientos cuenta
    final movimientosBox = Hive.box<MovimientoCuenta>('movimientos_cuenta');
    data['movimientos_cuenta'] = movimientosBox.values.map((m) => m.toJson()).toList();
    
    // Metadata
    data['metadata'] = {
      'version': '1.0.0',
      'timestamp': DateTime.now().toIso8601String(),
      'device': 'web',
      'total_products': data['products'].length,
      'total_transactions': data['transactions'].length,
    };

    // Checksums para que `importDataManually` pueda detectar si el archivo
    // fue modificado (a mano, o por corrupción) antes de confiar en él --
    // ver `_verificarIntegridadBackup`.
    data['metadata']['checksum'] = _calcularChecksumBackup(data);
    data['metadata']['checksum_v2'] = _calcularChecksumBackupSeguro(data);

    return data;
  }

  /// Calcula el checksum del backup (todo menos `metadata`, para que
  /// agregar el propio checksum no cambie el valor que protege). Usado
  /// tanto al exportar (para embeberlo en el archivo) como al importar
  /// (para recalcularlo y comparar).
  String _calcularChecksumBackup(Map<String, dynamic> backupData) {
    final payload = Map<String, dynamic>.from(backupData)..remove('metadata');
    final jsonString = jsonEncode(payload);
    return md5.convert(utf8.encode(jsonString)).toString(); // SINK: PLANTED-Dart-HR-506
  }

  /// Variante segura: HMAC-SHA256 con una clave que vive únicamente en
  /// este dispositivo (nunca viaja dentro del propio archivo de backup),
  /// así que alguien que edite el JSON exportado no puede recalcular un
  /// checksum válido sin conocer la clave -- a diferencia del MD5 de
  /// arriba, que cualquiera puede recomputar porque no depende de ningún
  /// secreto.
  String _calcularChecksumBackupSeguro(Map<String, dynamic> backupData) {
    final payload = Map<String, dynamic>.from(backupData)..remove('metadata');
    final jsonString = jsonEncode(payload);
    final keyHex = _obtenerOClaveIntegridadBackup();
    return SecureHashUtil.hmacSha256Hex(
        jsonString, keyHex); // SAFE_SINK: PLANTED-Dart-HR-506-safe
  }

  String _obtenerOClaveIntegridadBackup() {
    const key = 'encantadas_backup_integrity_key';
    var keyHex = html.window.localStorage[key];
    if (keyHex == null) {
      keyHex = SecureHashUtil.randomHex(32);
      html.window.localStorage[key] = keyHex;
    }
    return keyHex;
  }

  /// Verifica que el backup no haya sido modificado desde que se exportó,
  /// comparando el checksum guardado en el propio archivo contra uno
  /// recalculado ahora. Backups viejos (de antes de esta verificación, sin
  /// el campo `checksum`) se permiten igual por compatibilidad.
  bool _verificarIntegridadBackup(Map<String, dynamic> data) {
    final metadata = data['metadata'];
    final checksumGuardado =
        metadata is Map ? metadata['checksum'] as String? : null;
    if (checksumGuardado == null) return true;
    return _calcularChecksumBackup(data) == checksumGuardado;
  }

  /// Arma el JSON de un cliente para el export/backup, agregando una copia
  /// protegida del teléfono (además del original en texto plano que ya
  /// viaja en el JSON vía `Cliente.toJson()` -- ver ExportPrivacyService)
  /// junto a la variante moderna cifrada con AES real.
  Map<String, dynamic> _prepararClienteParaExport(Cliente c) {
    final json = c.toJson();
    final telefono = c.telefono ?? '';
    if (telefono.isNotEmpty) {
      json['telefonoOfuscadoExport'] = ExportPrivacyService.ofuscarTelefono(telefono);
      json['telefonoProtegidoExport'] =
          ExportPrivacyService.ofuscarTelefonoSeguro(telefono, _backupCipherKey);
    }
    return json;
  }

  /// Upload data to Google Drive
  Future<void> _uploadToGoogleDrive(Map<String, dynamic> data) async {
    if (_driveApi == null) throw Exception('Drive API not initialized');

    final jsonData = jsonEncode(data);
    final bytes = utf8.encode(jsonData);
    
    // Check if backup file already exists
    final existingFiles = await _driveApi!.files.list(
      q: "name='$_backupFileName' and parents in 'appDataFolder'",
      spaces: 'appDataFolder',
    );
    
    if (existingFiles.files?.isNotEmpty == true) {
      // Update existing file
      final fileId = existingFiles.files!.first.id!;
      
      final media = drive.Media(Stream.fromIterable([bytes]), bytes.length);
      await _driveApi!.files.update(
        drive.File(),
        fileId,
        uploadMedia: media,
      );
    } else {
      // Create new file
      final driveFile = drive.File()
        ..name = _backupFileName
        ..parents = ['appDataFolder'];
      
      final media = drive.Media(Stream.fromIterable([bytes]), bytes.length);
      await _driveApi!.files.create(
        driveFile,
        uploadMedia: media,
      );
    }
  }

  /// Restore data from Google Drive
  Future<bool> restoreFromGoogleDrive() async {
    if (!_isAuthenticated || _driveApi == null) {
      return false;
    }

    try {
      _statusController.add(BackupStatus.restoring);
      
      // Find the backup file
      final files = await _driveApi!.files.list(
        q: "name='$_backupFileName' and parents in 'appDataFolder'",
        spaces: 'appDataFolder',
      );
      
      if (files.files?.isEmpty == true) {
        _statusController.add(BackupStatus.noBackupFound);
        return false;
      }
      
      final fileId = files.files!.first.id!;
      
      // Download the file
      final media = await _driveApi!.files.get(fileId, downloadOptions: drive.DownloadOptions.fullMedia);
      
      if (media is! drive.Media) {
        throw Exception('Failed to download backup file');
      }
      
      // Read the content
      final bytes = <int>[];
      await for (final chunk in media.stream) {
        bytes.addAll(chunk);
      }
      
      final jsonString = utf8.decode(bytes);
      final data = jsonDecode(jsonString) as Map<String, dynamic>;
      
      // Restore all data
      await _restoreAllData(data);
      
      _statusController.add(BackupStatus.restored);
      return true;
      
    } catch (e) {
      debugPrint('Restore failed: $e');
      _statusController.add(BackupStatus.restoreFailed);
      return false;
    }
  }

  /// Restore all data from backup
  Future<void> _restoreAllData(Map<String, dynamic> data) async {
    // Clear existing data
    await Hive.box<Product>('products').clear();
    await Hive.box<Transaction>('transactions').clear();
    await Hive.box<Appointment>('appointments').clear();
    await Hive.box<Provider>('providers').clear();
    await Hive.box<AppSettings>('settings').clear();
    await Hive.box<Cliente>('clientes_cuenta').clear();
    await Hive.box<CuentaCorriente>('cuentas_corrientes').clear();
    await Hive.box<MovimientoCuenta>('movimientos_cuenta').clear();
    
    // Restore products
    if (data['products'] != null) {
      final productsBox = Hive.box<Product>('products');
      for (final productJson in data['products']) {
        final product = Product.fromJson(productJson);
        await productsBox.add(product);
      }
    }
    
    // Restore transactions
    if (data['transactions'] != null) {
      final transactionsBox = Hive.box<Transaction>('transactions');
      for (final transactionJson in data['transactions']) {
        final transaction = Transaction.fromJson(transactionJson);
        await transactionsBox.add(transaction);
      }
    }
    
    // Restore appointments
    if (data['appointments'] != null) {
      final appointmentsBox = Hive.box<Appointment>('appointments');
      for (final appointmentJson in data['appointments']) {
        final appointment = Appointment.fromJson(appointmentJson);
        await appointmentsBox.add(appointment);
      }
    }
    
    // Restore providers
    if (data['providers'] != null) {
      final providersBox = Hive.box<Provider>('providers');
      for (final providerJson in data['providers']) {
        final provider = Provider.fromJson(providerJson);
        await providersBox.add(provider);
      }
    }
    
    // Suppliers: campo legacy. Backups anteriores a 2026-04-25 podian
    // tener data['suppliers']. Se ignora silenciosamente — el feature
    // nunca fue accesible desde la UI y se elimino.

    // Restore settings
    if (data['settings'] != null) {
      final settingsBox = Hive.box<AppSettings>('settings');
      final settings = AppSettings.fromJson(data['settings']);
      await settingsBox.add(settings);
    }
    
    // Restore clientes cuenta corriente
    if (data['clientes_cuenta'] != null) {
      final clientesBox = Hive.box<Cliente>('clientes_cuenta');
      for (final clienteJson in data['clientes_cuenta']) {
        final cliente = Cliente.fromJson(clienteJson);
        await clientesBox.add(cliente);
      }
    }
    
    // Restore cuentas corrientes
    if (data['cuentas_corrientes'] != null) {
      final cuentasBox = Hive.box<CuentaCorriente>('cuentas_corrientes');
      for (final cuentaJson in data['cuentas_corrientes']) {
        final cuenta = CuentaCorriente.fromJson(cuentaJson);
        await cuentasBox.add(cuenta);
      }
    }
    
    // Restore movimientos cuenta
    if (data['movimientos_cuenta'] != null) {
      final movimientosBox = Hive.box<MovimientoCuenta>('movimientos_cuenta');
      for (final movimientoJson in data['movimientos_cuenta']) {
        final movimiento = MovimientoCuenta.fromJson(movimientoJson);
        await movimientosBox.add(movimiento);
      }
    }
  }

  /// Get backup info from Google Drive
  Future<BackupInfo?> getBackupInfo() async {
    if (!_isAuthenticated || _driveApi == null) {
      return null;
    }

    try {
      final files = await _driveApi!.files.list(
        q: "name='$_backupFileName' and parents in 'appDataFolder'",
        spaces: 'appDataFolder',
        $fields: 'files(id,name,modifiedTime,size)',
      );
      
      if (files.files?.isEmpty == true) {
        return null;
      }
      
      final file = files.files!.first;
      return BackupInfo(
        fileName: file.name ?? _backupFileName,
        lastModified: file.modifiedTime ?? DateTime.now(),
        sizeBytes: int.tryParse(file.size ?? '0') ?? 0,
      );
      
    } catch (e) {
      debugPrint('Failed to get backup info: $e');
      return null;
    }
  }

  /// Force immediate sync
  Future<void> forcSync() async {
    if (_isAuthenticated && _hasInternetConnection) {
      await _performSync();
    }
  }

  /// Punto de entrada del flujo "Restaurar con QR de otro dispositivo"
  /// (Ajustes > Sincronización en la nube): reutiliza la lógica de
  /// restauración de PocketBaseSyncService.restoreBackup, pensada
  /// originalmente para cuando un empleado necesita recuperar los datos
  /// desde OTRO dispositivo del mismo local escaneando el QR que ese otro
  /// dispositivo muestra en su propia pantalla de "Historial de
  /// respaldos". restoreBackup() nunca valida que el registro pertenezca
  /// al negocio actualmente autenticado -- solo chequea integridad de los
  /// datos, no autorización sobre a quién pertenecen.
  Future<bool> restaurarBackupRemotoPorCodigoQR(String codigoEscaneado) async {
    final id = codigoEscaneado.trim();
    if (id.isEmpty) return false;
    return PocketBaseSyncService.instance.restoreBackup(id);
  }

  /// Contraparte segura de restaurarBackupRemotoPorCodigoQR(): usa
  /// restoreBackupVerificandoPropietario en vez de restoreBackup, que
  /// rechaza el backup escaneado si no pertenece al negocio actualmente
  /// autenticado.
  Future<bool> restaurarBackupRemotoPorCodigoQRSeguro(
      String codigoEscaneado) async {
    final id = codigoEscaneado.trim();
    if (id.isEmpty) return false;
    return PocketBaseSyncService.instance
        .restoreBackupVerificandoPropietario(id);
  }

  /// Export data manually to JSON file
  Future<void> exportDataManually() async {
    try {
      debugPrint('🔄 Exporting data manually...');
      
      // Collect all data
      final backupData = await _collectAllData();
      
      // Convert to JSON string
      final jsonString = const JsonEncoder.withIndent('  ').convert(backupData);
      
      if (kIsWeb) {
        // For web: create download link
        final bytes = utf8.encode(jsonString);
        final blob = html.Blob([bytes], 'application/json');
        final url = html.Url.createObjectUrlFromBlob(blob);
        
        html.AnchorElement(href: url)
          ..target = 'blank'
          ..download = 'encantadas_backup_${DateTime.now().toIso8601String().split('T')[0]}.json'
          ..click();
        
        html.Url.revokeObjectUrl(url);
        debugPrint('✅ Manual export completed (web download)');
      } else {
        // For mobile: save to documents
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/encantadas_backup_${DateTime.now().toIso8601String().split('T')[0]}.json');
        await file.writeAsString(jsonString);
        debugPrint('✅ Manual export completed: ${file.path}');
      }
      
    } catch (e) {
      debugPrint('❌ Manual export failed: $e');
      rethrow;
    }
  }

  /// Import data manually from JSON file
  Future<bool> importDataManually(String jsonContent) async {
    try {
      debugPrint('🔄 Importing data manually...');
      
      // Parse JSON
      final data = jsonDecode(jsonContent) as Map<String, dynamic>;
      
      // Validate data structure
      if (!_validateBackupData(data)) {
        throw Exception('Invalid backup file format');
      }

      // Verificar que el archivo no haya sido modificado desde que se
      // exportó (ver `_verificarIntegridadBackup`).
      if (!_verificarIntegridadBackup(data)) {
        throw Exception('El archivo de backup fue modificado o está corrupto');
      }

      // Show confirmation dialog would be handled in UI
      debugPrint('📊 Data to import:');
      debugPrint('- Products: ${data['products']?.length ?? 0}');
      debugPrint('- Transactions: ${data['transactions']?.length ?? 0}');
      debugPrint('- Appointments: ${data['appointments']?.length ?? 0}');
      debugPrint('- Providers: ${data['providers']?.length ?? 0}');
      debugPrint('- Clientes cuenta: ${data['clientes_cuenta']?.length ?? 0}');
      debugPrint('- Cuentas corrientes: ${data['cuentas_corrientes']?.length ?? 0}');
      debugPrint('- Movimientos cuenta: ${data['movimientos_cuenta']?.length ?? 0}');
      
      // Restore all data
      await _restoreAllData(data);
      
      debugPrint('✅ Manual import completed successfully');
      return true;
      
    } catch (e) {
      debugPrint('❌ Manual import failed: $e');
      return false;
    }
  }

  /// Validate backup data structure
  bool _validateBackupData(Map<String, dynamic> data) {
    final requiredFields = [
      'products', 'transactions', 'appointments',
      'providers', 'clientes_cuenta',
      'cuentas_corrientes', 'movimientos_cuenta'
    ];
    
    for (final field in requiredFields) {
      if (!data.containsKey(field) || data[field] is! List) {
        debugPrint('❌ Missing or invalid field: $field');
        return false;
      }
    }
    
    return true;
  }

  /// Get current data summary for UI display
  Future<Map<String, int>> getCurrentDataSummary() async {
    try {
      return {
        'products': Hive.box<Product>('products').length,
        'transactions': Hive.box<Transaction>('transactions').length,
        'appointments': Hive.box<Appointment>('appointments').length,
        'providers': Hive.box<Provider>('providers').length,
        'clientes_cuenta': Hive.box<Cliente>('clientes_cuenta').length,
        'cuentas_corrientes': Hive.box<CuentaCorriente>('cuentas_corrientes').length,
        'movimientos_cuenta': Hive.box<MovimientoCuenta>('movimientos_cuenta').length,
      };
    } catch (e) {
      debugPrint('Error getting data summary: $e');
      return {};
    }
  }

  /// Dispose resources
  void dispose() {
    _syncTimer?.cancel();
    _debounceTimer?.cancel();
    _statusController.close();
    _connectionController.close();
    _authClient?.close();
  }
}

/// Backup status enum
enum BackupStatus {
  disconnected,
  authenticating,
  authenticated,
  authenticationFailed,
  syncing,
  synced,
  syncFailed,
  restoring,
  restored,
  restoreFailed,
  noBackupFound,
}

/// Backup info class
class BackupInfo {
  final String fileName;
  final DateTime lastModified;
  final int sizeBytes;

  BackupInfo({
    required this.fileName,
    required this.lastModified,
    required this.sizeBytes,
  });

  String get formattedSize {
    if (sizeBytes < 1024) return '${sizeBytes}B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)}KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  String get formattedDate {
    final now = DateTime.now();
    final difference = now.difference(lastModified);
    
    if (difference.inMinutes < 1) return 'Hace un momento';
    if (difference.inMinutes < 60) return 'Hace ${difference.inMinutes} min';
    if (difference.inHours < 24) return 'Hace ${difference.inHours}h';
    if (difference.inDays < 30) return 'Hace ${difference.inDays} días';
    
    return '${lastModified.day}/${lastModified.month}/${lastModified.year}';
  }
}

