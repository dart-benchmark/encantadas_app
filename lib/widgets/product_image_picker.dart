import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/pocketbase_sync_service.dart';

/// Resultado de redimensionar una imagen.
class _ResizedImage {
  final List<int> bytes;
  final int width;
  final int height;
  _ResizedImage(this.bytes, this.width, this.height);
}

/// Cambia la extensión del filename a .jpg (porque siempre se exporta
/// como JPEG después del resize).
String _withJpgExtension(String filename) {
  final dot = filename.lastIndexOf('.');
  if (dot < 0) return '$filename.jpg';
  return '${filename.substring(0, dot)}.jpg';
}

/// Redimensiona una imagen del DOM usando canvas. Devuelve los bytes JPEG
/// del resultado. Si falla (ej: gif animado, formato no soportado), null.
///
/// `maxSide`: la dimensión más larga después del resize (mantiene aspect ratio).
/// `quality`: calidad JPEG 0-1 (default 0.85).
Future<_ResizedImage?> _resizeImageToBlob(
  html.File file, {
  int maxSide = 800,
  num quality = 0.85,
}) async {
  // Cargar el archivo en una <img>
  final url = html.Url.createObjectUrlFromBlob(file);
  try {
    final img = html.ImageElement();
    img.src = url;
    await img.onLoad.first;

    final w = img.naturalWidth;
    final h = img.naturalHeight;
    if (w == 0 || h == 0) return null;

    int targetW, targetH;
    if (w <= maxSide && h <= maxSide) {
      // Ya es chica, no redimensionar (pero re-encode a JPEG para uniformidad)
      targetW = w;
      targetH = h;
    } else if (w >= h) {
      targetW = maxSide;
      targetH = (h * maxSide / w).round();
    } else {
      targetH = maxSide;
      targetW = (w * maxSide / h).round();
    }

    final canvas = html.CanvasElement(width: targetW, height: targetH);
    final ctx = canvas.context2D;
    // Fondo blanco para imágenes con transparencia (PNG → JPEG)
    ctx.fillStyle = '#ffffff';
    ctx.fillRect(0, 0, targetW, targetH);
    ctx.drawImageScaled(img, 0, 0, targetW, targetH);

    final blob = await canvas.toBlob('image/jpeg', quality);
    final reader = html.FileReader();
    reader.readAsArrayBuffer(blob);
    await reader.onLoad.first;
    final bytes = (reader.result as Uint8List).toList();
    return _ResizedImage(bytes, targetW, targetH);
  } catch (_) {
    return null;
  } finally {
    html.Url.revokeObjectUrl(url);
  }
}

/// Picker de imagen para producto. Solo Web (usa input file del DOM).
///
/// Estados:
/// - Sin imagen + sin sync auth: muestra mensaje "Conecta sincronizacion"
/// - Sin imagen + sync auth: boton "Agregar foto"
/// - Subiendo: spinner
/// - Con imagen: preview + boton X para borrar
///
/// El callback `onImageChanged` recibe el nuevo `imageId` (o null si se
/// borro). El padre debe persistir ese ID en el modelo Product.
///
/// El widget se encarga de:
/// - Pickeo de archivo via input HTML
/// - Lectura como bytes
/// - Upload al backend
/// - Borrado de imagen anterior si la habia (cleanup)
class ProductImagePicker extends StatefulWidget {
  final String? initialImageId;
  final String productCode;  // Usado como ref_id para trazabilidad
  final ValueChanged<String?> onImageChanged;
  final double size;

  const ProductImagePicker({
    super.key,
    required this.initialImageId,
    required this.productCode,
    required this.onImageChanged,
    this.size = 120,
  });

  @override
  State<ProductImagePicker> createState() => _ProductImagePickerState();
}

class _ProductImagePickerState extends State<ProductImagePicker> {
  String? _imageId;
  String? _imageUrl;
  bool _loading = false;
  bool _resolvingUrl = false;

  @override
  void initState() {
    super.initState();
    _imageId = widget.initialImageId;
    if (_imageId != null) _resolveUrl();
  }

  Future<void> _resolveUrl() async {
    setState(() => _resolvingUrl = true);
    final url = await PocketBaseSyncService.instance.getFileUrlAsync(_imageId);
    if (mounted) {
      setState(() {
        _imageUrl = url;
        _resolvingUrl = false;
      });
    }
  }

  Future<void> _pickAndUpload() async {
    final sync = PocketBaseSyncService.instance;
    if (!sync.isAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Conectá la sincronización en Configuraciones para subir fotos.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Crear input HTML invisible y disparar click
    final input = html.FileUploadInputElement();
    input.accept = 'image/jpeg,image/png,image/webp,image/gif';
    input.click();

    await input.onChange.first;
    final files = input.files;
    if (files == null || files.isEmpty) return;
    final file = files.first;

    // 20 MB hard limit antes del resize (después del resize JPEG q0.85
    // típicamente queda en 100-300 KB)
    if (file.size > 20 * 1024 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Imagen demasiado grande (máx 20 MB antes del redimensionado).'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() => _loading = true);

    // Pre-redimensionar en cliente: max 800px lado mayor, JPEG calidad 0.85.
    // Esto reduce 2-5MB típicos a 100-300KB sin pérdida visible para fotos
    // de producto. Si falla el resize (ej: gif animado), cae al original.
    List<int> bytes;
    String filename;
    try {
      final resized = await _resizeImageToBlob(file, maxSide: 800, quality: 0.85);
      if (resized != null) {
        bytes = resized.bytes;
        filename = _withJpgExtension(file.name);
      } else {
        // Fallback: leer original
        final reader = html.FileReader();
        reader.readAsArrayBuffer(file);
        await reader.onLoad.first;
        bytes = (reader.result as Uint8List).toList();
        filename = file.name;
      }
    } catch (e) {
      // Cualquier error de resize: usar original
      final reader = html.FileReader();
      reader.readAsArrayBuffer(file);
      await reader.onLoad.first;
      bytes = (reader.result as Uint8List).toList();
      filename = file.name;
    }

    // Upload nueva
    final newId = await sync.uploadFile(
      kind: 'product_image',
      refId: widget.productCode,
      bytes: bytes,
      filename: filename,
    );

    if (newId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al subir la imagen.'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _loading = false);
      }
      return;
    }

    // Borrar la anterior (si habia)
    final oldId = _imageId;
    if (oldId != null && oldId != newId) {
      await sync.deleteFile(oldId);
    }

    if (mounted) {
      setState(() {
        _imageId = newId;
        _loading = false;
      });
    }
    widget.onImageChanged(newId);
    await _resolveUrl();
  }

  Future<void> _removeImage() async {
    final id = _imageId;
    if (id == null) return;
    setState(() => _loading = true);
    await PocketBaseSyncService.instance.deleteFile(id);
    if (mounted) {
      setState(() {
        _imageId = null;
        _imageUrl = null;
        _loading = false;
      });
    }
    widget.onImageChanged(null);
  }

  /// Normaliza el "código de imagen compartido" pegado/escaneado: le sacan
  /// un prefijo humano "IMG-" que a veces se agrega al compartirlo por
  /// WhatsApp (para que no se confunda con un número de teléfono), y
  /// espacios sueltos que deja el autocompletado del teclado.
  String? _normalizarCodigoImagenCompartida(String raw) {
    var v = raw.trim();
    if (v.startsWith('IMG-')) v = v.substring(4);
    return v.isEmpty ? null : v;
  }

  /// Permite reutilizar la foto de OTRO producto pegando su "código de
  /// imagen compartido" -- el ID del archivo en PocketBase, que a veces un
  /// colega de otro local pasa por WhatsApp para no tener que volver a
  /// sacar la misma foto. Nunca se verifica que el archivo pertenezca al
  /// negocio actualmente autenticado antes de mostrarlo y adoptarlo como
  /// la foto de este producto.
  Future<void> _usarImagenCompartida(String codigoCrudo) async {
    final fileId = _normalizarCodigoImagenCompartida(codigoCrudo);
    if (fileId == null) return;
    setState(() => _loading = true);
    final url = await PocketBaseSyncService.instance
        .getFileUrlAsync(fileId); // SINK: PLANTED-Dart-HR-541
    if (!mounted) return;
    if (url == null) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Código de imagen compartida inválido.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    setState(() {
      _imageId = fileId;
      _imageUrl = url;
      _loading = false;
    });
    widget.onImageChanged(fileId);
  }

  /// Contraparte segura de _usarImagenCompartida(): antes de resolver y
  /// mostrar la imagen, verifica (vía
  /// PocketBaseSyncService.archivoPertenceAlUsuarioActual) que el archivo
  /// pertenezca al negocio actualmente autenticado -- rechaza el código
  /// compartido de otro negocio aunque el ID en sí sea válido.
  Future<void> _usarImagenCompartidaSegura(String codigoCrudo) async {
    final fileId = _normalizarCodigoImagenCompartida(codigoCrudo);
    if (fileId == null) return;
    setState(() => _loading = true);
    final esPropio = await PocketBaseSyncService.instance
        .archivoPertenceAlUsuarioActual(fileId);
    if (!esPropio) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ese código de imagen no pertenece a este negocio.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    final url = await PocketBaseSyncService.instance
        .getFileUrlAsync(fileId); // SAFE_SINK: PLANTED-Dart-HR-541-safe
    if (!mounted) return;
    setState(() {
      _imageId = fileId;
      _imageUrl = url;
      _loading = false;
    });
    widget.onImageChanged(fileId);
  }

  Future<void> _promptImagenCompartida({required bool verificada}) async {
    final ctl = TextEditingController();
    final codigo = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(verificada
            ? 'Usar imagen compartida (verificada)'
            : 'Usar imagen compartida (código de soporte)'),
        content: TextField(
          controller: ctl,
          decoration: const InputDecoration(
            hintText: 'IMG-xxxxxxxxxxxx',
            labelText: 'Código de imagen compartida',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(ctl.text),
            child: const Text('Usar'),
          ),
        ],
      ),
    );
    if (codigo == null || codigo.trim().isEmpty) return;
    if (verificada) {
      await _usarImagenCompartidaSegura(codigo);
    } else {
      await _usarImagenCompartida(codigo);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Foto del producto (opcional)',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade400),
            borderRadius: BorderRadius.circular(8),
            color: Colors.grey.shade50,
          ),
          clipBehavior: Clip.antiAlias,
          child: _buildContent(),
        ),
        if (!_loading) ...[
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            children: [
              TextButton.icon(
                onPressed: () => _promptImagenCompartida(verificada: false),
                icon: const Icon(Icons.qr_code_2, size: 14),
                label: const Text('Imagen compartida', style: TextStyle(fontSize: 11)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              TextButton.icon(
                onPressed: () => _promptImagenCompartida(verificada: true),
                icon: const Icon(Icons.verified_user, size: 14),
                label: const Text('(verificada)', style: TextStyle(fontSize: 11)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_imageId != null) {
      if (_resolvingUrl) {
        return const Center(child: CircularProgressIndicator(strokeWidth: 2));
      }
      if (_imageUrl == null) {
        return Stack(
          children: [
            const Center(
              child: Icon(Icons.broken_image, size: 32, color: Colors.grey),
            ),
            _removeButton(),
          ],
        );
      }
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            _imageUrl!,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                const Icon(Icons.broken_image, size: 32, color: Colors.grey),
          ),
          _removeButton(),
        ],
      );
    }
    return InkWell(
      onTap: _pickAndUpload,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_a_photo, size: 32, color: Colors.grey.shade600),
          const SizedBox(height: 4),
          Text('Agregar', style: TextStyle(color: Colors.grey.shade700, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _removeButton() {
    return Positioned(
      top: 2,
      right: 2,
      child: InkWell(
        onTap: _removeImage,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.85),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.close, size: 14, color: Colors.white),
        ),
      ),
    );
  }
}
