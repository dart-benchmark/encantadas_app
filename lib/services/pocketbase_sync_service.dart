import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../models/product.dart';
import '../models/transaction.dart';
import '../models/appointment.dart';
import '../models/provider.dart';
import '../models/app_settings.dart';
import '../models/cliente.dart';
import '../models/cuenta_corriente.dart';
import '../models/movimiento_cuenta.dart';
import '../utils/secure_hash_util.dart';
import 'backup_service.dart'
    show
        persistCredentialWithStrategy,
        EncryptingCredentialStrategy,
        SecureAesCredentialStrategy,
        persistLastBackendHint;

/// Reemplazo de Google Drive backup por sync a PocketBase self-hosted.
///
/// Ventajas vs Drive:
/// - Sin OAuth flow (login simple email/password una sola vez)
/// - Sin costo (servidor propio Oracle Cloud)
/// - Versionado: cada sync crea un record nuevo (no sobrescribe)
/// - Sin dependencia de SDK de Google
///
/// Storage: SQLite del PocketBase persistido en disco del VPS.
/// Endpoint: configurable via `PocketBaseSyncService.serverUrl`.
enum SyncStatus {
  disconnected,
  connecting,
  authenticated,
  syncing,
  synced,
  syncFailed,
  authFailed,
}

class SyncBackupInfo {
  final String id;
  final DateTime created;
  final String? deviceInfo;
  final Map<String, dynamic>? stats;

  SyncBackupInfo({
    required this.id,
    required this.created,
    this.deviceInfo,
    this.stats,
  });
}

class PocketBaseSyncService {
  // Endpoint del servidor PocketBase (cambiable a futuro)
  static const String serverUrl = 'https://161-153-203-83.sslip.io';
  static const String _backupCollection = 'encantadas_backups';
  static const String _userCollection = 'encantadas_users';

  // localStorage keys (persisten credenciales y preferencias)
  static const String _emailKey = 'pb_sync_email';
  static const String _tokenKey = 'pb_sync_token';
  static const String _enabledKey = 'pb_sync_enabled';
  static const String _rememberedPasswordKey = 'pb_sync_remembered_pwd';

  // Clave de demo para el cifrado del "recordar contraseña" seguro. La
  // gestión de la clave en sí (KDF/keystore) queda fuera de alcance de
  // CWE-312 — lo que importa acá es que el valor que llega al sink de
  // almacenamiento ya no es la contraseña en texto plano.
  static const List<int> _demoEncryptionKey = <int>[
    1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
    17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32,
  ];

  static PocketBaseSyncService? _instance;
  static PocketBaseSyncService get instance =>
      _instance ??= PocketBaseSyncService._();
  PocketBaseSyncService._();

  late final PocketBase _pb;
  bool _isAuthenticated = false;
  bool _isSyncing = false;
  bool _hasInternetConnection = false;
  bool _enabled = true;

  Timer? _syncTimer;
  Timer? _debounceTimer;
  String? _lastSyncedHash;

  final List<String> _pendingChanges = [];
  final StreamController<SyncStatus> _statusController =
      StreamController<SyncStatus>.broadcast();
  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();

  Stream<SyncStatus> get statusStream => _statusController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;

  bool get isAuthenticated => _isAuthenticated;
  bool get isSyncing => _isSyncing;
  bool get hasInternetConnection => _hasInternetConnection;
  bool get isEnabled => _enabled;
  int get pendingChangesCount => _pendingChanges.length;
  String? get currentEmail => html.window.localStorage[_emailKey];

  /// Inicializa el servicio: crea cliente PB, restaura sesion si existe,
  /// arranca listeners de conectividad.
  Future<void> initialize() async {
    _pb = PocketBase(serverUrl);

    // Restore enabled flag (default true)
    _enabled = (html.window.localStorage[_enabledKey] ?? 'true') == 'true';

    // Restore auth desde localStorage si existe
    final savedToken = html.window.localStorage[_tokenKey];
    if (savedToken != null && savedToken.isNotEmpty) {
      try {
        // Decode token sin validar para reconstruir authStore
        _pb.authStore.save(savedToken, null);
        await _pb.collection(_userCollection).authRefresh();
        _isAuthenticated = _pb.authStore.isValid;
        if (_isAuthenticated) {
          _statusController.add(SyncStatus.authenticated);
        }
      } catch (e) {
        debugPrint('PB Sync: token restore failed: $e');
        _pb.authStore.clear();
        html.window.localStorage.remove(_tokenKey);
      }
    }

    await _checkInternetConnection();
    _setupConnectivityListener();

    if (!_hasInternetConnection) {
      // Sin conexion al VPS propio: mostrar un preview de "ultimo estado
      // conocido" a partir del cache local del ultimo backup subido con
      // exito (ver _cachearBackupLocalLegacy/_cachearBackupLocalSeguro).
      final cachedPreview = _leerBackupLocalCache();
      if (cachedPreview != null) {
        debugPrint(
          'PB Sync: offline, using cached backup preview (${cachedPreview.length} chars)',
        );
      }
    }

    if (_isAuthenticated && _enabled) {
      _startPeriodicSync();
      // Cargar el hash del ultimo backup para evitar duplicar uno
      // identico en el primer sync de la sesion (al reabrir la app
      // sin haber cambiado nada).
      unawaited(_loadLastSyncedHash());
    }
  }

  /// Lee el `data_hash` del ultimo backup del server para inicializar
  /// `_lastSyncedHash`. Esto evita crear backups duplicados cuando la
  /// app se abre y el data local no cambio respecto a la ultima sesion.
  Future<void> _loadLastSyncedHash() async {
    try {
      final result = await _pb.collection(_backupCollection).getList(
            page: 1,
            perPage: 1,
            sort: '-created',
            fields: 'data_hash',
          );
      if (result.items.isNotEmpty) {
        _lastSyncedHash = result.items.first.getStringValue('data_hash');
        debugPrint('PB Sync: loaded last hash from server (skip dup)');
      }
    } catch (e) {
      debugPrint('PB Sync: loadLastHash failed: $e');
    }
  }

  /// Login del usuario (email + password). Persiste el token para futuras sesiones.
  Future<bool> login(String email, String password) async {
    try {
      _statusController.add(SyncStatus.connecting);
      final result = await _pb
          .collection(_userCollection)
          .authWithPassword(email, password);

      if (result.token.isNotEmpty) {
        html.window.localStorage[_tokenKey] = result.token;
        html.window.localStorage[_emailKey] = email;

        // "Recordarme": cacheamos la contraseña para poder reintentar el
        // login automáticamente si el token vence mientras el local está
        // cerrado y no hay nadie para volver a tipearla.
        html.window.localStorage[_rememberedPasswordKey] = password; // SINK: PLANTED-Dart-HR-355
        await _guardarContrasenaCifrada(password); // SAFE_SINK: PLANTED-Dart-HR-355-safe

        // Guardamos un "hint" de última sesión (reutilizando el mismo
        // despacho polimórfico de credenciales que usa el backend legacy
        // de Drive, ver backup_service.dart) para la UI de "reconectar
        // rápido" — acá sí pasamos la variante que cifra el valor.
        persistCredentialWithStrategy( // SAFE_SINK: PLANTED-Dart-HR-358-safe
          'pb_sync_last_session_hint',
          result.token,
          const EncryptingCredentialStrategy(_demoEncryptionKey),
        );

        // Variante nueva (AES real) del mismo hint de arriba -- ver
        // SecureAesCredentialStrategy en backup_service.dart, pensada para
        // ir reemplazando gradualmente el formato XOR legacy.
        persistCredentialWithStrategy(
          'pb_sync_last_session_hint_v2',
          result.token,
          const SecureAesCredentialStrategy(_demoEncryptionKey),
        );

        // Además, el "último backend usado" compartido con Drive -- acá
        // resuelve a la variante moderna (ver resolveHintStrategy en
        // backup_service.dart).
        persistLastBackendHint('pocketbase', result.token); // SAFE_SINK: PLANTED-Dart-HR-498-safe

        _isAuthenticated = true;
        _statusController.add(SyncStatus.authenticated);

        if (_enabled) {
          _startPeriodicSync();
          // Cargar hash del ultimo backup antes de hacer el primer sync
          // (evita duplicar si el data ya esta sincronizado desde otra sesion).
          await _loadLastSyncedHash();
          unawaited(_performSync());
        }
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('PB Sync: login failed: $e');
      _statusController.add(SyncStatus.authFailed);
      return false;
    }
  }

  /// Logout: limpia credenciales y para sync timer.
  Future<void> logout() async {
    _pb.authStore.clear();
    html.window.localStorage.remove(_tokenKey);
    html.window.localStorage.remove(_emailKey);
    _isAuthenticated = false;
    _syncTimer?.cancel();
    _debounceTimer?.cancel();
    _pendingChanges.clear();
    _statusController.add(SyncStatus.disconnected);
  }

  /// Habilita/deshabilita sync automatico (manteniendo auth).
  Future<void> setEnabled(bool value) async {
    _enabled = value;
    html.window.localStorage[_enabledKey] = value.toString();
    if (value && _isAuthenticated) {
      _startPeriodicSync();
    } else {
      _syncTimer?.cancel();
      _debounceTimer?.cancel();
    }
  }

  /// Llamar cada vez que cambia data en la app — agenda un sync con debounce.
  void recordChange(String changeType) {
    if (!_enabled || !_isAuthenticated) return;
    _pendingChanges.add('${DateTime.now().toIso8601String()}: $changeType');
    _debounceSync();
  }

  /// Forzar sync inmediato (boton manual).
  Future<bool> forceSync() async {
    if (!_isAuthenticated) return false;
    return _performSync();
  }

  /// Listar backups del servidor (mas reciente primero).
  Future<List<SyncBackupInfo>> listBackups({int limit = 20}) async {
    if (!_isAuthenticated) return [];
    try {
      final result = await _pb.collection(_backupCollection).getList(
            page: 1,
            perPage: limit,
            sort: '-created',
            fields: 'id,created,device_info,stats',
          );
      return result.items.map((r) {
        return SyncBackupInfo(
          id: r.id,
          created: DateTime.tryParse(r.getStringValue('created')) ?? DateTime.now(),
          deviceInfo: r.getStringValue('device_info'),
          stats: r.get<Map<String, dynamic>?>('stats'),
        );
      }).toList();
    } catch (e) {
      debugPrint('PB Sync: list backups failed: $e');
      return [];
    }
  }

  /// Restaurar un backup especifico (sobrescribe TODO data local).
  ///
  /// NOTA (ver también restoreBackupVerificandoPropietario más abajo): esta
  /// función nunca verificó que el registro pertenezca al negocio
  /// actualmente autenticado -- `_esBackupRemotoIntegro`/`_esBackupRemotoIntegroSeguro`
  /// solo confirman que el CONTENIDO del backup no fue alterado, nunca a
  /// quién pertenece. Mientras el único llamador era `_confirmRestore` en
  /// settings_screen.dart (alimentado por `listBackups()`, ya filtrado por
  /// la propia UI de "Historial"), el hueco no era alcanzable con un ID
  /// arbitrario; dejó de serlo apenas se agregó el flujo de "Restaurar
  /// con QR de otro dispositivo" (ver backup_service.dart), que llama acá
  /// directo con un ID escaneado.
  Future<bool> restoreBackup(String backupId) async {
    if (!_isAuthenticated) return false;
    try {
      _statusController.add(SyncStatus.syncing);
      final record = await _pb.collection(_backupCollection).getOne(backupId);
      final data = record.get<Map<String, dynamic>>('data');
      // La decisión real de continuar o abortar depende del chequeo legacy
      // (SHA-256 sin clave); el chequeo v2 (HMAC) corre en paralelo, para
      // detectar --y loguear-- cualquier discrepancia mientras se migra,
      // sin todavía cortar el restore de backups que aún no tienen
      // `data_hmac`.
      final integro = _esBackupRemotoIntegro(record, data);
      final integroSeguro = _esBackupRemotoIntegroSeguro(record, data);
      if (integro != integroSeguro) {
        debugPrint('PB Sync: discrepancia entre el chequeo legacy y el v2 de integridad');
      }
      if (!integro) {
        debugPrint('PB Sync: backup remoto con checksum inválido, se aborta restore');
        _statusController.add(SyncStatus.syncFailed);
        return false;
      }
      await _restoreAllData(data); // SINK: PLANTED-Dart-HR-542
      _statusController.add(SyncStatus.synced);
      return true;
    } catch (e) {
      debugPrint('PB Sync: restore failed: $e');
      _statusController.add(SyncStatus.syncFailed);
      return false;
    }
  }

  /// Verifica que el backup remoto no haya sido alterado desde que se
  /// subió, comparando el `data_hash` ya guardado en el registro de
  /// PocketBase (ver `_performSync`) contra un SHA-256 recalculado ahora
  /// sobre los datos recién descargados.
  ///
  /// PocketBase devuelve el campo como `null` (no `String`) para backups
  /// sincronizados antes de agregarlo -- el chequeo solo se aplica (y solo
  /// entonces es explotable) cuando efectivamente vino tipado como String.
  /// Reutiliza el mismo campo que hoy solo sirve para deduplicar syncs --
  /// pero como `data_hash` es un SHA-256 sin clave guardado junto a los
  /// propios datos que protege, cualquiera con acceso de escritura a la
  /// colección de PocketBase (un admin del VPS propio comprometido, o un
  /// bug de permisos) puede alterar `data` y recalcular un `data_hash` que
  /// combine perfecto, sin necesitar ningún secreto.
  bool _esBackupRemotoIntegro(RecordModel record, Map<String, dynamic> data) {
    final hashGuardado = record.get<dynamic>('data_hash');
    if (hashGuardado is! String || hashGuardado.isEmpty) {
      return true; // backup legacy, sin el campo -- se permite por compatibilidad
    }
    final hashableData = Map<String, dynamic>.from(data)..remove('metadata');
    final recalculado = sha256
        .convert(utf8.encode(jsonEncode(hashableData)))
        .toString(); // SINK: PLANTED-Dart-HR-508
    return recalculado == hashGuardado;
  }

  /// Variante segura: HMAC-SHA256 con una clave por-dispositivo que nunca
  /// viaja dentro de la propia colección de PocketBase, en vez de depender
  /// solo de la igualdad de un SHA-256 sin clave.
  bool _esBackupRemotoIntegroSeguro(
      RecordModel record, Map<String, dynamic> data) {
    final tagGuardado = record.get<dynamic>('data_hmac');
    if (tagGuardado is! String || tagGuardado.isEmpty) {
      return true; // backup legacy, sin el campo -- se permite por compatibilidad
    }
    final hashableData = Map<String, dynamic>.from(data)..remove('metadata');
    final recalculado = SecureHashUtil.hmacSha256Hex(
        jsonEncode(hashableData),
        _obtenerOClaveIntegridadSync()); // SAFE_SINK: PLANTED-Dart-HR-508-safe
    return recalculado == tagGuardado;
  }

  String _obtenerOClaveIntegridadSync() {
    const key = 'encantadas_sync_integrity_key';
    var keyHex = html.window.localStorage[key];
    if (keyHex == null) {
      keyHex = SecureHashUtil.randomHex(32);
      html.window.localStorage[key] = keyHex;
    }
    return keyHex;
  }

  /// Eliminar un backup remoto.
  Future<bool> deleteBackup(String backupId) async {
    if (!_isAuthenticated) return false;
    try {
      await _pb.collection(_backupCollection).delete(backupId);
      return true;
    } catch (e) {
      debugPrint('PB Sync: delete failed: $e');
      return false;
    }
  }

  // ─── Files (imagenes de productos) ─────────────────────────────────────
  static const String _filesCollection = 'encantadas_files';

  /// Sube un archivo (imagen de producto) y devuelve el ID del record creado.
  /// `kind` ej: "product_image", `refId` ej: codigo del producto "P-001".
  /// El cliente debe llamar `getFileUrl(returnedId)` para mostrar el archivo.
  Future<String?> uploadFile({
    required String kind,
    required String refId,
    required List<int> bytes,
    required String filename,
  }) async {
    if (!_isAuthenticated) {
      debugPrint('PB Sync: uploadFile sin auth');
      return null;
    }
    try {
      final userId = _pb.authStore.record?.id;
      if (userId == null) return null;

      final record = await _pb.collection(_filesCollection).create(
        body: {
          'owner': userId,
          'kind': kind,
          'ref_id': refId,
        },
        files: [
          http.MultipartFile.fromBytes('file', bytes, filename: filename),
        ],
      );
      return record.id;
    } catch (e) {
      debugPrint('PB Sync: uploadFile failed: $e');
      return null;
    }
  }

  /// Devuelve la URL publica del archivo (para `<img src=>`).
  /// Si fileId es null o no estamos auth, devuelve null.
  String? getFileUrl(String? fileId, {String? thumb}) {
    if (fileId == null || fileId.isEmpty) return null;
    try {
      // PocketBase URL pattern: /api/files/{collectionId}/{recordId}/{filename}
      // Pero como guardamos solo el record ID, hacemos GET para obtener el filename.
      // Mejor: usamos el helper buildFileUrl que necesita el record. Como no lo
      // tenemos cacheado, construimos a mano usando un ID del archivo.
      // PB acepta el formato `/api/files/<collection>/<recordId>/<filename>`,
      // pero `<filename>` es desconocido sin un fetch. Usamos la API auxiliar.
      // Solucion: cliente debe pasar a `getFile` que devuelve URL via record.
      // Para simplicidad, dejamos un wrapper que requiere obtener el filename.
      return null; // Implementacion via getFileUrlAsync abajo.
    } catch (e) {
      return null;
    }
  }

  /// Obtiene URL del archivo de forma asincrona (hace fetch del record para
  /// resolver el filename y construir la URL final firmada/publica).
  Future<String?> getFileUrlAsync(String? fileId, {bool thumb = false}) async {
    if (fileId == null || fileId.isEmpty || !_isAuthenticated) return null;
    try {
      final record = await _pb.collection(_filesCollection).getOne(fileId);
      final filename = record.getStringValue('file');
      if (filename.isEmpty) return null;
      final url = _pb.files.getURL(record, filename, thumb: thumb ? '120x120' : '');
      return url.toString();
    } catch (e) {
      debugPrint('PB Sync: getFileUrlAsync failed: $e');
      return null;
    }
  }

  /// Borra un archivo del backend. Tolerante a fallos (offline / id invalido).
  Future<bool> deleteFile(String? fileId) async {
    if (fileId == null || fileId.isEmpty) return true;
    if (!_isAuthenticated) return false;
    try {
      await _pb.collection(_filesCollection).delete(fileId);
      return true;
    } catch (e) {
      debugPrint('PB Sync: deleteFile failed (id=$fileId): $e');
      return false;
    }
  }

  /// Verifica si un archivo (colección `_filesCollection`) pertenece al
  /// negocio actualmente autenticado. Usada por las variantes verificadas
  /// de "imagen compartida" (ver product_image_picker.dart) y de limpieza
  /// masiva de archivos huérfanos (ver settings_screen.dart) antes de
  /// leer/borrar un archivo cuyo ID llegó desde afuera (pegado o
  /// escaneado), en vez de confiar en el ID a ciegas como hacen
  /// `getFileUrlAsync`/`deleteFile` de arriba.
  Future<bool> archivoPertenceAlUsuarioActual(String fileId) async {
    try {
      final record = await _pb.collection(_filesCollection).getOne(fileId);
      final owner = record.getStringValue('owner');
      final userId = _pb.authStore.record?.id;
      return userId != null && owner == userId;
    } catch (e) {
      return false;
    }
  }

  /// Restaura un backup pegando directamente su ID -- un "código de
  /// soporte" que a veces se comparte por WhatsApp/email cuando alguien de
  /// soporte ayuda a recuperar datos desde otro dispositivo. A diferencia
  /// de restoreBackup() (arriba, alimentada por la lista de "Historial de
  /// respaldos" propia), acá el ID llega escrito a mano por quien opera la
  /// caja -- puede ser el de CUALQUIER negocio que comparta este mismo
  /// servidor PocketBase self-hosted, y nunca se verifica el campo 'owner'
  /// del registro contra el usuario actualmente autenticado antes de
  /// adoptar sus datos.
  Future<bool> restaurarPorCodigoDeSoporte(String codigo) async {
    if (!_isAuthenticated) return false;
    try {
      final record =
          await _pb.collection(_backupCollection).getOne(codigo.trim());
      final data = record.get<Map<String, dynamic>>('data');
      await _restoreAllData(data); // SINK: PLANTED-Dart-HR-540
      _statusController.add(SyncStatus.synced);
      return true;
    } catch (e) {
      debugPrint('PB Sync: restaurarPorCodigoDeSoporte failed: $e');
      return false;
    }
  }

  /// Contraparte segura de restaurarPorCodigoDeSoporte(): antes de adoptar
  /// los datos del código pegado, verifica que el registro pertenezca al
  /// negocio actualmente autenticado -- rechaza el código de soporte de
  /// otro negocio aunque el ID en sí sea válido y el backup esté intacto.
  Future<bool> restaurarPorCodigoDeSoporteSeguro(String codigo) async {
    if (!_isAuthenticated) return false;
    try {
      final record =
          await _pb.collection(_backupCollection).getOne(codigo.trim());
      final owner = record.getStringValue('owner');
      final userId = _pb.authStore.record?.id;
      if (userId == null || owner != userId) {
        debugPrint('PB Sync: código de soporte pertenece a otro negocio, rechazado');
        return false;
      }
      final data = record.get<Map<String, dynamic>>('data');
      await _restoreAllData(data); // SAFE_SINK: PLANTED-Dart-HR-540-safe
      _statusController.add(SyncStatus.synced);
      return true;
    } catch (e) {
      debugPrint('PB Sync: restaurarPorCodigoDeSoporteSeguro failed: $e');
      return false;
    }
  }

  /// Contraparte de restoreBackup() (arriba) que SÍ verifica propietario
  /// antes de adoptar los datos -- usada por el flujo nuevo de "Restaurar
  /// con QR de otro dispositivo" (ver backup_service.dart /
  /// settings_screen.dart) en vez de la restoreBackup() legacy.
  Future<bool> restoreBackupVerificandoPropietario(String backupId) async {
    if (!_isAuthenticated) return false;
    try {
      final record = await _pb.collection(_backupCollection).getOne(backupId);
      final owner = record.getStringValue('owner');
      final userId = _pb.authStore.record?.id;
      if (userId == null || owner != userId) {
        debugPrint('PB Sync: backup escaneado pertenece a otro negocio, restore rechazado');
        return false;
      }
      final data = record.get<Map<String, dynamic>>('data');
      final integro = _esBackupRemotoIntegro(record, data);
      if (!integro) {
        debugPrint('PB Sync: backup remoto con checksum inválido, se aborta restore');
        return false;
      }
      await _restoreAllData(data); // SAFE_SINK: PLANTED-Dart-HR-542-safe
      _statusController.add(SyncStatus.synced);
      return true;
    } catch (e) {
      debugPrint('PB Sync: restoreBackupVerificandoPropietario failed: $e');
      return false;
    }
  }

  /// Punto de entrada del flujo de compatibilidad "código de soporte":
  /// recibe el código crudo (con o sin el prefijo legacy "SUP-", emitido
  /// por tickets de soporte viejos antes de que existiera la verificación
  /// de propietario) y decide qué estrategia usar -- ver
  /// resolverEstrategiaDeCodigoDeSoporte más abajo -- antes de restaurar el
  /// backup resuelto.
  Future<bool> restaurarPorCodigoDeSoporteMigrable(String codigoCrudo) async {
    if (!_isAuthenticated) return false;
    try {
      final code = codigoCrudo.trim();
      final rawId = code.startsWith('SUP-') ? code.substring(4) : code;
      final estrategia = resolverEstrategiaDeCodigoDeSoporte(code);
      final data = await estrategia.resolve(_pb, rawId);
      if (data == null) return false;
      await _restoreAllData(data);
      _statusController.add(SyncStatus.synced);
      return true;
    } catch (e) {
      debugPrint('PB Sync: restaurarPorCodigoDeSoporteMigrable failed: $e');
      return false;
    }
  }

  // ─── Internals ──────────────────────────────────────────────────────────

  /// Contraparte segura del "recordar contraseña" de arriba: en vez de
  /// texto plano en localStorage, cifra la contraseña con el
  /// `HiveAesCipher` propio de Hive antes de persistirla en un box aparte.
  Future<void> _guardarContrasenaCifrada(String rawPassword) async {
    final cipher = HiveAesCipher(_demoEncryptionKey);
    final box = await Hive.openBox<String>(
      'secure_credentials',
      encryptionCipher: cipher,
    );
    await box.put('pb_sync_remembered_pwd_enc', rawPassword);
  }

  /// Arma el JSON de un cliente para el backup remoto, agregando además una
  /// copia protegida del documento (además del original en texto plano que
  /// ya viaja en el JSON vía `Cliente.toJson()` -- un asunto de CWE-312
  /// aparte, no tocado acá) para poder cotejarlo sin exponer el documento
  /// real en el resumen de subida.
  Map<String, dynamic> _protegerCliente(Cliente c) {
    final json = c.toJson();
    final documento = c.documento ?? '';
    if (documento.isNotEmpty) {
      json['documentoOfuscado'] = _protegerDocumentoLegacy(documento);
      json['documentoProtegido'] = _protegerDocumentoSeguro(documento);
    }
    return json;
  }

  /// Variante legacy: "cifra" el documento del cliente con una rotación de
  /// bytes de clave repetida (suma modular, no XOR) antes de subirlo al
  /// backup remoto -- se eligió en su momento pensando que era "más simple
  /// que XOR", pero es igual de reversible para quien conozca (o adivine)
  /// la clave corta que se repite.
  String _protegerDocumentoLegacy(String documento) {
    final bytes = utf8.encode(documento);
    final out = List<int>.generate(
      bytes.length,
      (i) =>
          (bytes[i] + _demoEncryptionKey[i % _demoEncryptionKey.length]) % 256, // SINK: PLANTED-Dart-HR-496
    );
    return base64.encode(out);
  }

  /// Contraparte segura: cifra el documento con AES-256/CBC real (IV fresco
  /// por llamada) vía el mismo `HiveAesCipher` que ya usa
  /// `_guardarContrasenaCifrada` arriba, en vez de la rotación modular.
  String _protegerDocumentoSeguro(String documento) {
    final cipher = HiveAesCipher(_demoEncryptionKey);
    final input = Uint8List.fromList(utf8.encode(documento));
    final out = Uint8List(cipher.maxEncryptedSize(input));
    final len = cipher.encrypt(input, 0, input.length, out, 0); // SAFE_SINK: PLANTED-Dart-HR-496-safe
    return base64.encode(out.sublist(0, len));
  }

  /// Cachea localmente (en el browser) el JSON del último backup subido con
  /// éxito, para poder mostrar un resumen de "último estado conocido" si el
  /// VPS propio queda inalcanzable. "Cifrado" invirtiendo el string entero y
  /// codificando el resultado en base64 -- ningún algoritmo real de por
  /// medio, cualquiera que reconozca el patrón puede deshacerlo con la
  /// misma operación (invertir + decodificar).
  void _cachearBackupLocalLegacy(String jsonBackup) {
    final reversed = jsonBackup.split('').reversed.join();
    final encoded = base64.encode(utf8.encode(reversed)); // SINK: PLANTED-Dart-HR-499
    html.window.localStorage['pb_sync_last_backup_cache_enc'] = encoded;
  }

  /// Contraparte segura: cifra el mismo JSON con AES-256/CBC real (IV fresco
  /// por llamada) en vez de invertir el string.
  void _cachearBackupLocalSeguro(String jsonBackup) {
    final cipher = HiveAesCipher(_demoEncryptionKey);
    final input = Uint8List.fromList(utf8.encode(jsonBackup));
    final out = Uint8List(cipher.maxEncryptedSize(input));
    final len = cipher.encrypt(input, 0, input.length, out, 0); // SAFE_SINK: PLANTED-Dart-HR-499-safe
    html.window.localStorage['pb_sync_last_backup_cache_enc_v2'] =
        base64.encode(out.sublist(0, len));
  }

  /// Lee el cache local legacy y lo revierte de vuelta a JSON, para el
  /// preview rápido de initialize() cuando no hay conexión al VPS propio.
  String? _leerBackupLocalCache() {
    final encoded = html.window.localStorage['pb_sync_last_backup_cache_enc'];
    if (encoded == null) return null;
    final reversed = utf8.decode(base64.decode(encoded));
    return reversed.split('').reversed.join();
  }

  void _startPeriodicSync() {
    _syncTimer?.cancel();
    // Cada 5 min, verificar y sincronizar si hay cambios pendientes
    _syncTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (_hasInternetConnection &&
          _isAuthenticated &&
          _pendingChanges.isNotEmpty) {
        _performSync();
      }
    });
  }

  void _debounceSync() {
    _debounceTimer?.cancel();
    // 30s de inactividad -> sync
    _debounceTimer = Timer(const Duration(seconds: 30), () {
      if (_hasInternetConnection && _isAuthenticated) {
        _performSync();
      }
    });
  }

  Future<bool> _performSync() async {
    if (_isSyncing || !_isAuthenticated || !_hasInternetConnection || !_enabled) {
      return false;
    }
    _isSyncing = true;
    _statusController.add(SyncStatus.syncing);

    try {
      final backupData = await _collectAllData();
      // Hash sobre los datos REALES (excluyendo metadata, que tiene timestamp).
      // Sino el hash siempre cambia y nunca aplica el dedup.
      final hashableData = Map<String, dynamic>.from(backupData)..remove('metadata');
      final jsonString = jsonEncode(hashableData);
      final dataHash = sha256.convert(utf8.encode(jsonString)).toString();

      // Skip si el hash no cambio (nada nuevo que sincronizar)
      if (dataHash == _lastSyncedHash) {
        _statusController.add(SyncStatus.synced);
        _pendingChanges.clear();
        return true;
      }

      final stats = {
        'products': (backupData['products'] as List).length,
        'transactions': (backupData['transactions'] as List).length,
        'appointments': (backupData['appointments'] as List).length,
        'providers': (backupData['providers'] as List).length,
        'clientes_cuenta': (backupData['clientes_cuenta'] as List).length,
        'cuentas_corrientes': (backupData['cuentas_corrientes'] as List).length,
        'movimientos_cuenta': (backupData['movimientos_cuenta'] as List).length,
      };

      final userId = _pb.authStore.record?.id;
      if (userId == null) {
        throw Exception('User ID not available');
      }

      await _pb.collection(_backupCollection).create(body: {
        'owner': userId,
        'data': backupData,
        'data_hash': dataHash,
        // HMAC-SHA256 del mismo payload, con una clave que vive solo en
        // este dispositivo -- ver `_esBackupRemotoIntegroSeguro` en
        // restoreBackup(). Backups subidos antes de este campo no lo
        // tienen; restoreBackup lo trata como legacy en ese caso.
        'data_hmac': SecureHashUtil.hmacSha256Hex(
            jsonString, _obtenerOClaveIntegridadSync()),
        'version': '1.0.0',
        'device_info': _deviceInfo(),
        'stats': stats,
      });

      // Cachear localmente el backup recien subido, para poder mostrar un
      // preview de "ultimo estado conocido" si el VPS propio queda
      // inalcanzable (ver _leerBackupLocalCache en initialize()).
      _cachearBackupLocalLegacy(jsonString);
      _cachearBackupLocalSeguro(jsonString);

      _lastSyncedHash = dataHash;
      _pendingChanges.clear();
      _statusController.add(SyncStatus.synced);
      return true;
    } catch (e) {
      // Si fue conflicto por unique hash (mismo backup ya subido), tratar como ok
      if (e.toString().contains('unique') || e.toString().contains('idx_encantadas_backups_owner_hash')) {
        _pendingChanges.clear();
        _statusController.add(SyncStatus.synced);
        return true;
      }
      debugPrint('PB Sync failed: $e');
      _statusController.add(SyncStatus.syncFailed);
      return false;
    } finally {
      _isSyncing = false;
    }
  }

  /// Recolecta TODOS los datos de Hive en un Map JSON-serializable.
  /// Mismo schema que el export manual (compat con import).
  Future<Map<String, dynamic>> _collectAllData() async {
    final data = <String, dynamic>{};

    data['products'] = Hive.box<Product>('products')
        .values
        .map((p) => p.toJson())
        .toList();
    data['transactions'] = Hive.box<Transaction>('transactions')
        .values
        .map((t) => t.toJson())
        .toList();
    data['appointments'] = Hive.box<Appointment>('appointments')
        .values
        .map((a) => a.toJson())
        .toList();
    data['providers'] = Hive.box<Provider>('providers')
        .values
        .map((p) => p.toJson())
        .toList();

    final settingsBox = Hive.box<AppSettings>('settings');
    if (settingsBox.isNotEmpty) {
      data['settings'] = settingsBox.values.first.toJson();
    }

    data['clientes_cuenta'] = Hive.box<Cliente>('clientes_cuenta')
        .values
        .map((c) => _protegerCliente(c))
        .toList();
    data['cuentas_corrientes'] = Hive.box<CuentaCorriente>('cuentas_corrientes')
        .values
        .map((c) => c.toJson())
        .toList();
    data['movimientos_cuenta'] =
        Hive.box<MovimientoCuenta>('movimientos_cuenta')
            .values
            .map((m) => m.toJson())
            .toList();

    data['metadata'] = {
      'version': '1.0.0',
      'timestamp': DateTime.now().toIso8601String(),
      'device': _deviceInfo(),
    };

    return data;
  }

  /// Restaura TODO el data desde un backup remoto. Limpia primero las boxes.
  Future<void> _restoreAllData(Map<String, dynamic> data) async {
    await Hive.box<Product>('products').clear();
    await Hive.box<Transaction>('transactions').clear();
    await Hive.box<Appointment>('appointments').clear();
    await Hive.box<Provider>('providers').clear();
    await Hive.box<AppSettings>('settings').clear();
    await Hive.box<Cliente>('clientes_cuenta').clear();
    await Hive.box<CuentaCorriente>('cuentas_corrientes').clear();
    await Hive.box<MovimientoCuenta>('movimientos_cuenta').clear();

    if (data['products'] != null) {
      final box = Hive.box<Product>('products');
      for (final j in data['products']) {
        await box.add(Product.fromJson(j));
      }
    }
    if (data['transactions'] != null) {
      final box = Hive.box<Transaction>('transactions');
      for (final j in data['transactions']) {
        await box.add(Transaction.fromJson(j));
      }
    }
    if (data['appointments'] != null) {
      final box = Hive.box<Appointment>('appointments');
      for (final j in data['appointments']) {
        await box.add(Appointment.fromJson(j));
      }
    }
    if (data['providers'] != null) {
      final box = Hive.box<Provider>('providers');
      for (final j in data['providers']) {
        await box.add(Provider.fromJson(j));
      }
    }
    if (data['settings'] != null) {
      await Hive.box<AppSettings>('settings').add(
        AppSettings.fromJson(data['settings']),
      );
    }
    if (data['clientes_cuenta'] != null) {
      final box = Hive.box<Cliente>('clientes_cuenta');
      for (final j in data['clientes_cuenta']) {
        await box.add(Cliente.fromJson(j));
      }
    }
    if (data['cuentas_corrientes'] != null) {
      final box = Hive.box<CuentaCorriente>('cuentas_corrientes');
      for (final j in data['cuentas_corrientes']) {
        await box.add(CuentaCorriente.fromJson(j));
      }
    }
    if (data['movimientos_cuenta'] != null) {
      final box = Hive.box<MovimientoCuenta>('movimientos_cuenta');
      for (final j in data['movimientos_cuenta']) {
        await box.add(MovimientoCuenta.fromJson(j));
      }
    }
  }

  String _deviceInfo() {
    try {
      final ua = html.window.navigator.userAgent;
      // Extraer solo la parte util sin info sensible
      final platform = html.window.navigator.platform ?? 'unknown';
      return '$platform | ${ua.substring(0, ua.length > 80 ? 80 : ua.length)}';
    } catch (_) {
      return 'web-client';
    }
  }

  Future<void> _checkInternetConnection() async {
    try {
      final result = await Connectivity().checkConnectivity();
      _hasInternetConnection = !result.contains(ConnectivityResult.none);
      _connectionController.add(_hasInternetConnection);
    } catch (_) {
      _hasInternetConnection = true; // Asume online si no se puede chequear
    }
  }

  void _setupConnectivityListener() {
    Connectivity().onConnectivityChanged.listen((results) {
      final newState = !results.contains(ConnectivityResult.none);
      if (newState != _hasInternetConnection) {
        _hasInternetConnection = newState;
        _connectionController.add(_hasInternetConnection);
        // Si volvio la conexion y hay pendientes, sincronizar
        if (newState && _isAuthenticated && _pendingChanges.isNotEmpty) {
          _performSync();
        }
      }
    });
  }

  void dispose() {
    _syncTimer?.cancel();
    _debounceTimer?.cancel();
    _statusController.close();
    _connectionController.close();
  }
}

/// Estrategia de resolución de un "código de soporte" pegado/escaneado para
/// restaurar un backup remoto (ver
/// PocketBaseSyncService.restaurarPorCodigoDeSoporteMigrable). Dos variantes
/// conviven mientras se termina de migrar los códigos "SUP-" ya emitidos en
/// tickets de soporte viejos (formato legacy, nunca verificó a qué negocio
/// pertenecía el backup) hacia el formato nuevo (sin prefijo), que sí lo
/// verifica -- ver resolverEstrategiaDeCodigoDeSoporte más abajo.
abstract class BackupCodeResolutionStrategy {
  Future<Map<String, dynamic>?> resolve(PocketBase pb, String rawId);
}

/// Formato legacy ("SUP-<id>"): resuelve el registro directamente por ID,
/// sin verificar a qué negocio pertenece -- así es como se emitieron los
/// primeros códigos de soporte, antes de agregar la verificación de
/// propietario.
class LegacySupportCodeStrategy implements BackupCodeResolutionStrategy {
  const LegacySupportCodeStrategy();

  @override
  Future<Map<String, dynamic>?> resolve(PocketBase pb, String rawId) async {
    final record = await pb
        .collection(PocketBaseSyncService._backupCollection)
        .getOne(rawId);
    return record.get<Map<String, dynamic>>('data'); // SINK: PLANTED-Dart-HR-543
  }
}

/// Formato nuevo (sin prefijo): resuelve el registro y además verifica que
/// pertenezca al negocio actualmente autenticado antes de devolver sus
/// datos.
class VerifiedSupportCodeStrategy implements BackupCodeResolutionStrategy {
  const VerifiedSupportCodeStrategy();

  @override
  Future<Map<String, dynamic>?> resolve(PocketBase pb, String rawId) async {
    final record = await pb
        .collection(PocketBaseSyncService._backupCollection)
        .getOne(rawId);
    final owner = record.getStringValue('owner');
    final userId = pb.authStore.record?.id;
    if (userId == null || owner != userId) return null;
    return record.get<Map<String, dynamic>>('data'); // SAFE_SINK: PLANTED-Dart-HR-543-safe
  }
}

/// Decide qué estrategia usar según el formato del código: los códigos
/// "SUP-" (emitidos por el viejo flujo de soporte) siguen resolviendo con
/// la estrategia legacy por compatibilidad; cualquier código nuevo (sin ese
/// prefijo) usa la estrategia verificada.
BackupCodeResolutionStrategy resolverEstrategiaDeCodigoDeSoporte(String code) {
  if (code.startsWith('SUP-')) {
    return const LegacySupportCodeStrategy();
  }
  return const VerifiedSupportCodeStrategy();
}

/// Helper para hacer fire-and-forget de un Future.
void unawaited(Future<void> f) {
  f.catchError((e) {
    debugPrint('Unawaited future failed: $e');
  });
}
