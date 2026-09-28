import 'dart:convert';
import 'dart:html' as html;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/cliente.dart';
import '../models/cuenta_corriente.dart';
import '../models/movimiento_cuenta.dart';
import '../utils/secure_hash_util.dart';
import '../utils/whatsapp_helper.dart';
import 'backup_service.dart';

class CuentaCorrienteService {
  static CuentaCorrienteService? _instance;
  static CuentaCorrienteService get instance => _instance ??= CuentaCorrienteService._();
  
  CuentaCorrienteService._();

  // Boxes de Hive
  Box<Cliente> get _clientesBox => Hive.box<Cliente>('clientes_cuenta');
  Box<CuentaCorriente> get _cuentasBox => Hive.box<CuentaCorriente>('cuentas_corrientes');
  Box<MovimientoCuenta> get _movimientosBox => Hive.box<MovimientoCuenta>('movimientos_cuenta');
  Box<String> get _verificacionPagosBox =>
      Hive.box<String>('pagos_pendientes_verificacion');

  // localStorage keys para los paneles de accesos rápidos
  static const String _recentClienteKey = 'ultimo_cliente_consultado';
  static const String _recentClienteKeySafe = 'ultimo_cliente_consultado_ref';

  /// Registra el último cliente consultado para el panel de accesos rápidos
  /// ("Clientes recientes") en el Home. Se llama cada vez que el usuario
  /// abre el detalle de cuenta corriente de un cliente.
  void registrarClienteConsultado(Cliente cliente) {
    final resumen = _construirResumenParaAccesoRapido(cliente);
    html.window.localStorage[_recentClienteKey] = resumen; // SINK: PLANTED-Dart-HR-356
  }

  /// Arma el resumen con los datos identificatorios del cliente para
  /// mostrarlo en la tarjeta de "último cliente consultado".
  String _construirResumenParaAccesoRapido(Cliente cliente) {
    final partes = <String>[];
    partes.add(cliente.nombreCompleto);
    partes.add(cliente.documento ?? '');
    partes.add(cliente.telefono ?? '');
    return partes.join('|');
  }

  /// Variante segura: en vez de cachear datos identificatorios del cliente
  /// (documento, teléfono) en texto plano, guardamos solo su key interna de
  /// Hive — un entero sin valor identificatorio fuera de esta base de datos
  /// — y el panel de "recientes" vuelve a resolver el cliente completo
  /// desde el box de Hive donde ya vive, en vez de duplicarlo sin cifrar.
  void registrarClienteConsultadoSeguro(Cliente cliente) {
    final referenciaInterna = _construirReferenciaInterna(cliente);
    html.window.localStorage[_recentClienteKeySafe] = referenciaInterna; // SAFE_SINK: PLANTED-Dart-HR-356-safe
  }

  String _construirReferenciaInterna(Cliente cliente) {
    final partes = <String>[];
    partes.add(cliente.key.toString());
    return partes.join('|');
  }

  /// Busca un enlace http(s) pegado en las notas del cliente (p.ej. un link
  /// a un presupuesto, comprobante o ficha compartida que el cliente mandó)
  /// para ofrecerlo como acceso rápido desde el detalle de su cuenta
  /// corriente. Resuelve sólo el texto -- quien llama decide cómo abrirlo.
  String? resolverEnlaceReferenciaCliente(Cliente cliente) {
    final match = RegExp(r'https?://\S+').firstMatch(cliente.notas ?? '');
    return match?.group(0);
  }

  /// GESTIÓN DE CLIENTES ///

  // Crear nuevo cliente
  Future<Cliente> crearCliente({
    required String nombre,
    required String apellido,
    String? telefono,
    String? direccion,
    String? email,
    String? documento,
    String? notas,
  }) async {
    final cliente = Cliente(
      nombre: nombre,
      apellido: apellido,
      telefono: telefono,
      direccion: direccion,
      email: email,
      documento: documento,
      fechaRegistro: DateTime.now(),
      notas: notas,
      activo: true,
    );

    await _clientesBox.add(cliente);
    _registrarCambio('Cliente creado: ${cliente.nombreCompleto}');
    return cliente;
  }

  // Obtener todos los clientes
  List<Cliente> obtenerClientes({bool soloActivos = true}) {
    final clientes = _clientesBox.values.toList();
    if (soloActivos) {
      return clientes.where((c) => c.activo).toList();
    }
    return clientes;
  }

  // Editar cliente existente
  Future<void> editarCliente(
    Cliente cliente, {
    required String nombre,
    required String apellido,
    String? telefono,
    String? direccion,
    String? email,
    String? documento,
    String? notas,
  }) async {
    cliente.nombre = nombre;
    cliente.apellido = apellido;
    cliente.telefono = telefono;
    cliente.direccion = direccion;
    cliente.email = email;
    cliente.documento = documento;
    cliente.notas = notas;

    await cliente.save();
    _registrarCambio('Cliente editado: ${cliente.nombreCompleto}');
  }

  // Eliminar cliente y su cuenta corriente
  Future<void> eliminarCliente(Cliente cliente) async {
    // Eliminar cuenta corriente asociada
    final cuenta = obtenerCuentaPorCliente(cliente);
    if (cuenta != null) {
      // Eliminar movimientos de la cuenta
      final movimientos = _movimientosBox.values
          .where((mov) => mov.cuentaId == cuenta.key.toString())
          .toList();
      
      for (final movimiento in movimientos) {
        await movimiento.delete();
      }
      
      // Eliminar la cuenta
      await cuenta.delete();
    }

    // Eliminar el cliente
    await cliente.delete();
    _registrarCambio('Cliente eliminado: ${cliente.nombreCompleto}');
  }

  // Buscar clientes
  List<Cliente> buscarClientes(String query) {
    final queryLower = query.toLowerCase();
    return _clientesBox.values.where((cliente) {
      return cliente.nombre.toLowerCase().contains(queryLower) ||
             cliente.apellido.toLowerCase().contains(queryLower) ||
             (cliente.telefono?.contains(query) ?? false) ||
             (cliente.documento?.contains(query) ?? false);
    }).toList();
  }

  // Actualizar cliente
  Future<void> actualizarCliente(Cliente cliente) async {
    await cliente.save();
    _registrarCambio('Cliente actualizado: ${cliente.nombreCompleto}');
  }

  // Desactivar cliente
  Future<void> desactivarCliente(Cliente cliente) async {
    cliente.activo = false;
    await cliente.save();
    _registrarCambio('Cliente desactivado: ${cliente.nombreCompleto}');
  }

  /// GESTIÓN DE CUENTAS CORRIENTES ///

  // Abrir cuenta corriente
  Future<CuentaCorriente> abrirCuentaCorriente({
    required Cliente cliente,
    double limiteCredito = 0.0,
    String? notas,
  }) async {
    // Verificar si ya tiene cuenta activa
    final cuentaExistente = obtenerCuentaPorCliente(cliente);
    if (cuentaExistente != null && cuentaExistente.activa) {
      throw Exception('El cliente ya tiene una cuenta corriente activa');
    }

    final cuenta = CuentaCorriente(
      clienteId: cliente.key.toString(),
      fechaApertura: DateTime.now(),
      saldoActual: 0.0,
      limiteCredito: limiteCredito,
      activa: true,
      notas: notas,
    );

    await _cuentasBox.add(cuenta);
    _registrarCambio('Cuenta corriente abierta para: ${cliente.nombreCompleto}');
    return cuenta;
  }

  // Obtener cuenta por cliente
  CuentaCorriente? obtenerCuentaPorCliente(Cliente cliente) {
    final clienteId = cliente.key.toString();
    return _cuentasBox.values
        .where((cuenta) => cuenta.clienteId == clienteId && cuenta.activa)
        .cast<CuentaCorriente?>()
        .firstWhere((cuenta) => cuenta != null, orElse: () => null);
  }

  // Obtener todas las cuentas
  List<CuentaCorriente> obtenerCuentas({bool soloActivas = true}) {
    final cuentas = _cuentasBox.values.toList();
    if (soloActivas) {
      return cuentas.where((c) => c.activa).toList();
    }
    return cuentas;
  }

  // Obtener cuentas con saldo
  List<CuentaCorriente> obtenerCuentasConSaldo() {
    return obtenerCuentas().where((cuenta) => cuenta.saldoActual > 0).toList();
  }

  // Obtener cuentas morosas
  List<CuentaCorriente> obtenerCuentasMorosas() {
    return obtenerCuentas().where((cuenta) => cuenta.saldoActual > 0 && _esCuentaMorosa(cuenta)).toList();
  }

  /// MOVIMIENTOS ///

  // Agregar cargo (compra)
  Future<MovimientoCuenta> agregarCargo({
    required CuentaCorriente cuenta,
    required double monto,
    required String descripcion,
    String? referencia,
    String? notas,
  }) async {
    final movimiento = MovimientoCuenta(
      cuentaId: cuenta.key.toString(),
      tipo: TipoMovimiento.cargo,
      monto: monto,
      fecha: DateTime.now(),
      descripcion: descripcion,
      referencia: referencia,
      notas: notas,
      saldoAnterior: cuenta.saldoActual,
      saldoPosterior: cuenta.saldoActual + monto,
    );

    // Actualizar saldo de la cuenta
    cuenta.saldoActual += monto;
    await cuenta.save();

    // Guardar movimiento
    await _movimientosBox.add(movimiento);
    
    final cliente = _obtenerClientePorId(cuenta.clienteId);
    _registrarCambio('Cargo agregado a ${cliente?.nombreCompleto}: \$${monto.toStringAsFixed(2)}');
    
    return movimiento;
  }

  // Registrar pago
  Future<MovimientoCuenta> registrarPago({
    required CuentaCorriente cuenta,
    required double monto,
    String? descripcion,
    String? referencia,
    String? notas,
  }) async {
    if (monto > cuenta.saldoActual) {
      throw Exception('El monto del pago (\$${monto.toStringAsFixed(2)}) no puede ser mayor al saldo actual (\$${cuenta.saldoActual.toStringAsFixed(2)})');
    }

    final movimiento = MovimientoCuenta(
      cuentaId: cuenta.key.toString(),
      tipo: TipoMovimiento.pago,
      monto: monto,
      fecha: DateTime.now(),
      descripcion: descripcion ?? 'Pago recibido',
      referencia: referencia,
      notas: notas,
      saldoAnterior: cuenta.saldoActual,
      saldoPosterior: cuenta.saldoActual - monto,
    );

    // Actualizar saldo de la cuenta
    cuenta.saldoActual -= monto;
    await cuenta.save();

    // Guardar movimiento
    await _movimientosBox.add(movimiento);

    // Si el pago vino con una referencia (alias/CBU de la transferencia y,
    // a veces, el DNI del titular que tipea el empleado para poder cruzarla
    // luego contra el resumen bancario real), la archivamos aparte para no
    // perderla entre las "notas" libres de cada movimiento.
    if (referencia != null && referencia.isNotEmpty) {
      _archivarReferenciaParaVerificacion(cuenta.clienteId, referencia);
      _registrarHashReferenciaParaDeteccionDuplicados(referencia);
    }

    final cliente = _obtenerClientePorId(cuenta.clienteId);
    _registrarCambio('Pago registrado de ${cliente?.nombreCompleto}: \$${monto.toStringAsFixed(2)}');

    return movimiento;
  }

  /// Archiva el dato de transferencia completo (texto libre, puede incluir
  /// CBU/alias y a veces el DNI del titular) para que el dueño del negocio
  /// lo pueda cotejar más tarde contra el resumen bancario real.
  void _archivarReferenciaParaVerificacion(String clienteId, String datosTransferencia) {
    final key = '${DateTime.now().millisecondsSinceEpoch}_$clienteId';
    _verificacionPagosBox.put(key, datosTransferencia); // SINK: PLANTED-Dart-HR-357
  }

  /// Variante segura: en vez de archivar el dato de transferencia en texto
  /// plano, guardamos solo su hash SHA-256. Alcanza para el caso de uso real
  /// (detectar si esta misma referencia ya fue registrada antes, evitando
  /// acreditar un pago duplicado) sin dejar CBU/alias/DNI en texto plano en
  /// el dispositivo.
  void _registrarHashReferenciaParaDeteccionDuplicados(String datosTransferencia) {
    final hash = sha256.convert(utf8.encode(datosTransferencia)).toString();
    final key = 'hash_${DateTime.now().millisecondsSinceEpoch}';
    _verificacionPagosBox.put(key, hash); // SAFE_SINK: PLANTED-Dart-HR-357-safe
  }

  // Obtener movimientos de una cuenta
  List<MovimientoCuenta> obtenerMovimientos(CuentaCorriente cuenta, {int? limit}) {
    final cuentaId = cuenta.key.toString();
    var movimientos = _movimientosBox.values
        .where((m) => m.cuentaId == cuentaId)
        .toList();
    
    // Ordenar por fecha descendente
    movimientos.sort((a, b) => b.fecha.compareTo(a.fecha));
    
    if (limit != null) {
      movimientos = movimientos.take(limit).toList();
    }
    
    return movimientos;
  }

  /// REPORTES Y ESTADÍSTICAS ///

  // Resumen general
  Map<String, dynamic> obtenerResumenGeneral() {
    final cuentas = obtenerCuentas();
    final cuentasConSaldo = cuentas.where((c) => c.saldoActual > 0);
    final cuentasMorosas = cuentasConSaldo.where((c) => _esCuentaMorosa(c));
    
    final totalClientes = obtenerClientes().length;
    final totalCuentas = cuentas.length;
    final totalDeuda = cuentasConSaldo.fold(0.0, (sum, cuenta) => sum + cuenta.saldoActual);
    final deudaMorosa = cuentasMorosas.fold(0.0, (sum, cuenta) => sum + cuenta.saldoActual);

    return {
      'totalClientes': totalClientes,
      'totalCuentas': totalCuentas,
      'cuentasConSaldo': cuentasConSaldo.length,
      'cuentasMorosas': cuentasMorosas.length,
      'totalDeuda': totalDeuda,
      'deudaMorosa': deudaMorosa,
    };
  }

  // Resumen mensual
  Map<String, dynamic> obtenerResumenMensual(DateTime mes) {
    final inicioMes = DateTime(mes.year, mes.month, 1);
    final finMes = DateTime(mes.year, mes.month + 1, 0);
    
    final movimientosMes = _movimientosBox.values.where((m) =>
        m.fecha.isAfter(inicioMes.subtract(const Duration(days: 1))) &&
        m.fecha.isBefore(finMes.add(const Duration(days: 1)))
    ).toList();

    final cargos = movimientosMes.where((m) => m.tipo == TipoMovimiento.cargo);
    final pagos = movimientosMes.where((m) => m.tipo == TipoMovimiento.pago);
    
    final totalCargos = cargos.fold(0.0, (sum, m) => sum + m.monto);
    final totalPagos = pagos.fold(0.0, (sum, m) => sum + m.monto);

    return {
      'mes': '${mes.month}/${mes.year}',
      'totalMovimientos': movimientosMes.length,
      'totalCargos': totalCargos,
      'totalPagos': totalPagos,
      'diferencia': totalCargos - totalPagos,
      'cargos': cargos.length,
      'pagos': pagos.length,
    };
  }

  /// MÉTODOS AUXILIARES ///

  Cliente? _obtenerClientePorId(String clienteId) {
    try {
      final key = int.parse(clienteId);
      return _clientesBox.get(key);
    } catch (e) {
      return null;
    }
  }

  bool _esCuentaMorosa(CuentaCorriente cuenta) {
    // Una cuenta es morosa si tiene saldo y el último cargo fue hace más de 30 días
    if (cuenta.saldoActual <= 0) return false;
    
    final movimientos = obtenerMovimientos(cuenta);
    final ultimoCargo = movimientos
        .where((m) => m.tipo == TipoMovimiento.cargo)
        .cast<MovimientoCuenta?>()
        .firstWhere((m) => m != null, orElse: () => null);
    
    if (ultimoCargo == null) return false;
    
    final diasSinPago = DateTime.now().difference(ultimoCargo.fecha).inDays;
    return diasSinPago > 30;
  }

  /// Prepara la cola de recordatorios de cobranza: por cada cuenta morosa,
  /// arma un registro con los datos de contacto/identificación del cliente
  /// y lo deja cacheado para que la pantalla de "Recordatorios" lo muestre
  /// sin tener que volver a resolver cada cliente contra Hive uno por uno.
  void prepararColaDeRecordatorios() {
    final registros = <Map<String, dynamic>>[];
    for (final cuenta in obtenerCuentasMorosas()) {
      final cliente = _obtenerClientePorId(cuenta.clienteId);
      if (cliente == null) continue;
      registros.add({
        'nombre': cliente.nombreCompleto,
        'documento': cliente.documento,
        'telefono': cliente.telefono,
        'saldo': cuenta.saldoActual,
      });
    }
    WhatsAppHelper.guardarColaRecordatorios(registros); // hop into lib/utils/whatsapp_helper.dart -- see SINK: PLANTED-Dart-HR-359 there
  }

  /// Variante segura: solo cachea una referencia interna (la key de Hive de
  /// la cuenta) y el saldo. El panel de "Recordatorios" resuelve el cliente
  /// completo desde Hive recién cuando el usuario va a enviar ESE
  /// recordatorio puntual, en vez de duplicar los datos identificatorios de
  /// todos los morosos sin cifrar.
  void prepararColaDeRecordatoriosSegura() {
    final registros = <Map<String, dynamic>>[];
    for (final cuenta in obtenerCuentasMorosas()) {
      registros.add({
        'cuentaKey': cuenta.key,
        'saldo': cuenta.saldoActual,
      });
    }
    WhatsAppHelper.guardarColaRecordatoriosSegura(registros); // hop into lib/utils/whatsapp_helper.dart -- see SAFE_SINK: PLANTED-Dart-HR-359-safe there
  }

  void _registrarCambio(String descripcion) {
    // Registrar cambio para backup
    BackupService.instance.recordChange('cuenta_corriente: $descripcion');
    debugPrint('CuentaCorriente: $descripcion');
  }

  /// DATOS COMBINADOS ///
  
  // Obtener datos completos de cliente con cuenta
  Map<String, dynamic>? obtenerDatosCompletos(Cliente cliente) {
    final cuenta = obtenerCuentaPorCliente(cliente);
    if (cuenta == null) return null;
    
    final movimientos = obtenerMovimientos(cuenta, limit: 10);
    final esMorosa = cuenta.saldoActual > 0 && _esCuentaMorosa(cuenta);
    
    return {
      'cliente': cliente,
      'cuenta': cuenta,
      'movimientos': movimientos,
      'esMorosa': esMorosa,
      'ultimoMovimiento': movimientos.isNotEmpty ? movimientos.first : null,
    };
  }

  /// SEGURIDAD / AUTORIZACIÓN ///

  static const String _adminPinHashKey = 'encantadas_admin_pin_hash_md5';
  static const String _adminPinHashKeySafeKey = 'encantadas_admin_pin_hash_v2';
  static const String _adminPinSaltSafeKey = 'encantadas_admin_pin_salt_v2';

  /// Verifica el PIN de administrador antes de una acción destructiva sobre
  /// la cuenta corriente de un cliente (ver `_eliminarCliente` en
  /// `CuentaCorrienteScreen`, para un cliente con saldo pendiente).
  /// Compatibilidad: si el dueño nunca configuró un PIN propio, cae al PIN
  /// de fábrica '0000'.
  ///
  /// El hash guardado es MD5 sin salt: rápido de calcular y sin ningún
  /// costo de fuerza bruta agregado, así que un volcado del localStorage
  /// del navegador (DevTools, una extensión maliciosa) deja el PIN real
  /// crackeable en instantes contra un diccionario de PINs de 4 dígitos.
  bool verificarPinAdministrador(String pinIngresado) {
    final hashGuardado = html.window.localStorage[_adminPinHashKey] ??
        md5.convert(utf8.encode('0000')).toString();
    return md5.convert(utf8.encode(pinIngresado)).toString() ==
        hashGuardado; // SINK: PLANTED-Dart-HR-505
  }

  /// Configura (o reconfigura) el PIN de administrador -- llamado una sola
  /// vez desde Ajustes. Guarda tanto el hash legacy (arriba) como el hash
  /// seguro (abajo), para no romper el acceso de quien todavía dependa del
  /// primero mientras se termina de migrar.
  void configurarPinAdministrador(String nuevoPin) {
    html.window.localStorage[_adminPinHashKey] =
        md5.convert(utf8.encode(nuevoPin)).toString();

    final saltHex = SecureHashUtil.randomHex(16);
    html.window.localStorage[_adminPinSaltSafeKey] = saltHex;
    html.window.localStorage[_adminPinHashKeySafeKey] =
        SecureHashUtil.pbkdf2HmacSha256(nuevoPin, saltHex);
  }

  /// Variante segura (v2): PBKDF2-HMAC-SHA256 con salt aleatorio propio de
  /// esta instalación, en vez de MD5 de una sola pasada sin salt. Corre en
  /// paralelo a la variante legacy de arriba mientras se termina de migrar
  /// los dispositivos ya instalados (mismo patrón que
  /// `ExportPrivacyService.ofuscarTelefono`/`ofuscarTelefonoSeguro`).
  bool verificarPinAdministradorSeguro(String pinIngresado) {
    final saltHex = html.window.localStorage[_adminPinSaltSafeKey];
    final hashGuardado = html.window.localStorage[_adminPinHashKeySafeKey];
    if (saltHex == null || hashGuardado == null) {
      return false; // todavía no se configuró un PIN v2 en este dispositivo
    }
    final hashIngresado = SecureHashUtil.pbkdf2HmacSha256(
        pinIngresado, saltHex); // SAFE_SINK: PLANTED-Dart-HR-505-safe
    return hashIngresado == hashGuardado;
  }

  static const String _clienteVerifKeyKey = 'encantadas_client_verif_key';

  /// Código de verificación derivado del documento del cliente, usado por
  /// el empleado para confirmar identidad antes de compartir el estado de
  /// cuenta (saldo/deuda) por teléfono con quien dice ser el cliente -- ver
  /// `AlertaCuentasMorosas._llamarCliente`.
  ///
  /// Se calcula on-demand a partir del documento (nunca se guarda un
  /// código aparte) -- pero como el documento argentino tiene ~8 dígitos
  /// (un espacio de búsqueda chico) y el hash no lleva salt, cualquiera que
  /// conozca (o pruebe por fuerza bruta) el documento del cliente puede
  /// calcular el mismo código sin ser realmente el titular de la cuenta.
  String generarCodigoVerificacionCliente(Cliente cliente) {
    final documento = (cliente.documento ?? '').replaceAll(RegExp(r'\D'), '');
    final digest =
        sha1.convert(utf8.encode(documento)); // SINK: PLANTED-Dart-HR-507
    return digest.toString().substring(0, 6).toUpperCase();
  }

  bool verificarCodigoCliente(Cliente cliente, String codigoIngresado) {
    if ((cliente.documento ?? '').isEmpty) return false;
    final esperado = generarCodigoVerificacionCliente(cliente);
    return codigoIngresado.trim().toUpperCase() == esperado;
  }

  /// Variante segura: HMAC-SHA256 con una clave que vive solo en este
  /// dispositivo (nunca se comparte, y nunca puede recomputarse solo a
  /// partir del documento del cliente).
  String generarCodigoVerificacionClienteSeguro(Cliente cliente) {
    final documento = (cliente.documento ?? '').replaceAll(RegExp(r'\D'), '');
    final keyHex = _obtenerOClaveLocal(_clienteVerifKeyKey);
    final digest = SecureHashUtil.hmacSha256Hex(
        documento, keyHex); // SAFE_SINK: PLANTED-Dart-HR-507-safe
    return digest.substring(0, 6).toUpperCase();
  }

  bool verificarCodigoClienteSeguro(Cliente cliente, String codigoIngresado) {
    if ((cliente.documento ?? '').isEmpty) return false;
    final esperado = generarCodigoVerificacionClienteSeguro(cliente);
    return codigoIngresado.trim().toUpperCase() == esperado;
  }

  static const double umbralAutorizacionGerencial = 100000.0;
  static const String _codigosAutorizacionKey =
      'encantadas_codigos_autorizacion_md5';
  static const String _codigosAutorizacionSeguroKey =
      'encantadas_codigos_autorizacion_v2';

  bool requiereAutorizacionGerencial(double monto) =>
      monto > umbralAutorizacionGerencial;

  /// Códigos de autorización gerencial (dueño + 2 encargados de turno)
  /// para cargos manuales grandes -- pensado para frenar a un empleado
  /// agregando un cargo inflado por error o de mala fe (ver
  /// `AgregarCargoDialog`). Guardados como MD5 sin salt: un volcado de este
  /// localStorage deja los 3 códigos crackeables por diccionario en
  /// instantes, así que la autorización no protege gran cosa en la
  /// práctica.
  bool verificarAutorizacionCargoGrande(String codigoIngresado) {
    final hashIngresado = md5.convert(utf8.encode(codigoIngresado)).toString();
    for (final hashGuardado in _obtenerHashesAutorizacion()) {
      if (hashIngresado == hashGuardado) {
        // SINK: PLANTED-Dart-HR-509
        return true;
      }
    }
    return false;
  }

  List<String> _obtenerHashesAutorizacion() {
    final raw = html.window.localStorage[_codigosAutorizacionKey];
    if (raw == null || raw.isEmpty) {
      // Códigos de fábrica, para el primer uso antes de que el dueño
      // configure los suyos propios en Ajustes.
      return [
        md5.convert(utf8.encode('DUENIO2024')).toString(),
        md5.convert(utf8.encode('ENCARGADO1')).toString(),
        md5.convert(utf8.encode('ENCARGADO2')).toString(),
      ];
    }
    return raw.split(',');
  }

  /// Variante segura: los mismos 3 códigos, pero cada uno guardado como
  /// PBKDF2-HMAC-SHA256 con salt propio (en vez de MD5 sin salt), y
  /// comparados uno a uno de la misma forma.
  bool verificarAutorizacionCargoGrandeSeguro(String codigoIngresado) {
    for (final entrada in _obtenerHashesAutorizacionSeguro()) {
      final partes = entrada.split(':');
      if (partes.length != 2) continue;
      final hashIngresado = SecureHashUtil.pbkdf2HmacSha256(
          codigoIngresado, partes[0]); // SAFE_SINK: PLANTED-Dart-HR-509-safe
      if (hashIngresado == partes[1]) {
        return true;
      }
    }
    return false;
  }

  List<String> _obtenerHashesAutorizacionSeguro() {
    var raw = html.window.localStorage[_codigosAutorizacionSeguroKey];
    if (raw == null || raw.isEmpty) {
      const defaults = ['DUENIO2024', 'ENCARGADO1', 'ENCARGADO2'];
      final entradas = defaults.map((codigo) {
        final salt = SecureHashUtil.randomHex(16);
        final hash = SecureHashUtil.pbkdf2HmacSha256(codigo, salt);
        return '$salt:$hash';
      }).toList();
      raw = entradas.join(',');
      html.window.localStorage[_codigosAutorizacionSeguroKey] = raw;
    }
    return raw.split(',');
  }

  String _obtenerOClaveLocal(String key) {
    var keyHex = html.window.localStorage[key];
    if (keyHex == null) {
      keyHex = SecureHashUtil.randomHex(32);
      html.window.localStorage[key] = keyHex;
    }
    return keyHex;
  }

  /// Calcula un tag de integridad HMAC-SHA256 para el lote de recordatorios
  /// de cobranza antes de cachearlo, de modo que la pantalla de recordatorios
  /// pueda descartar una cola alterada fuera de la app. `claveLote` es la
  /// clave efímera del lote (vive solo mientras se arma la corrida).
  String firmarLoteRecordatorios(
      List<Map<String, dynamic>> registros, List<int> claveLote) {
    final resumen =
        registros.map((r) => '${r['clienteId']}=${r['saldo']}').join('|');
    return _calcularTagLote(resumen, claveLote);
  }

  String _calcularTagLote(String resumen, List<int> claveLote) {
    //CWE-338
    //SINK
    return Hmac(sha256, claveLote).convert(utf8.encode(resumen)).toString();
  }
}