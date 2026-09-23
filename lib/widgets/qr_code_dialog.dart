import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:open_filex/open_filex.dart';
import '../utils/validate_product_code.dart';
import '../utils/qr_download_helper.dart';

class QRCodeDialog extends StatefulWidget {
  final String productCode;
  final String productName;

  const QRCodeDialog({
    super.key,
    required this.productCode,
    required this.productName,
  });

  @override
  State<QRCodeDialog> createState() => _QRCodeDialogState();
}

class _QRCodeDialogState extends State<QRCodeDialog> {
  final GlobalKey _qrKey = GlobalKey();
  bool _isDownloading = false;

  @override
  Widget build(BuildContext context) {
    // Validate product code before generating QR
    if (!ProductCodeValidator.isCodeValid(widget.productCode)) {
      return _buildErrorDialog(context, 'Código QR inválido', 
          'El código del producto "${widget.productCode}" no es válido para generar un código QR. '
          'Contacte al administrador para corregir este problema.');
    }

    if (widget.productCode.trim().isEmpty) {
      return _buildErrorDialog(context, 'Sin código de producto', 
          'Este producto no tiene un código asignado. No se puede generar el código QR.');
    }

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Código QR',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  tooltip: 'Cerrar',
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Product name
            Text(
              widget.productName,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            
            // QR Code with RepaintBoundary for capture
            RepaintBoundary(
              key: _qrKey,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).dividerColor,
                    width: 1,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Product name in capture
                    Text(
                      widget.productName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    
                    // QR Code
                    QrImageView(
                      data: widget.productCode,
                      version: QrVersions.auto,
                      size: 200.0,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Colors.black,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Colors.black,
                      ),
                      errorCorrectionLevel: QrErrorCorrectLevel.M,
                    ),
                    const SizedBox(height: 16),
                    
                    // Product code in capture
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: Colors.grey.shade300,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.tag,
                            size: 14,
                            color: Colors.black87,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            widget.productCode,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  label: const Text('Cerrar'),
                ),
                ElevatedButton.icon(
                  onPressed: _isDownloading ? null : _downloadQRCode,
                  icon: _isDownloading 
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Theme.of(context).colorScheme.onPrimary,
                            ),
                          ),
                        )
                      : const Icon(Icons.download),
                  label: Text(_isDownloading ? 'Descargando...' : 'Descargar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Maneja la descarga del código QR
  Future<void> _downloadQRCode() async {
    setState(() => _isDownloading = true);
    try {
      final result = await QRDownloadHelper.downloadQRCode(
        _qrKey,
        widget.productCode,
        pixelRatio: 3.0,
      );
      if (result.success && result.fileName != null) {
        _showSuccessSnackBar(result.fileName!, result.filePath);
      } else {
        _showErrorSnackBar(result.error ?? 'No se pudo guardar el archivo');
      }
    } catch (e) {
      _showErrorSnackBar('Error al descargar QR: $e');
    } finally {
      setState(() => _isDownloading = false);
    }
  }

  void _showSuccessSnackBar(String fileName, String? filePath) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Text('✅ ', style: TextStyle(fontSize: 18)),
            Expanded(child: Text('QR descargado como $fileName')),
          ],
        ),
        backgroundColor: Colors.green[600],
        duration: const Duration(seconds: 6),
        action: filePath != null
            ? SnackBarAction(
                label: 'Ver archivo',
                onPressed: () => _openDownloadedFile(filePath),
                textColor: Colors.white,
              )
            : SnackBarAction(
                label: 'OK',
                onPressed: () {},
                textColor: Colors.white,
              ),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red[600],
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'OK',
          onPressed: () {},
          textColor: Colors.white,
        ),
      ),
    );
  }

  /// Abre el archivo descargado con la aplicación predeterminada del sistema
  Future<void> _openDownloadedFile(String filePath) async {
    try {
      final result = await OpenFilex.open(filePath);
      
      // Si no se pudo abrir el archivo, mostrar error
      if (result.type != ResultType.done) {
        _showErrorSnackBar('No se pudo abrir el archivo descargado');
      }
    } catch (e) {
      _showErrorSnackBar('No se pudo abrir el archivo descargado');
    }
  }

  /// Construye un diálogo de error cuando la validación falla
  Widget _buildErrorDialog(BuildContext context, String title, String message) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header con ícono de error
            Row(
              children: [
                Icon(
                  Icons.error_outline,
                  color: Theme.of(context).colorScheme.error,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  tooltip: 'Cerrar',
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Product name
            Text(
              widget.productName,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),

            // Error message
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context).colorScheme.error.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.qr_code_scanner,
                    size: 64,
                    color: Theme.of(context).colorScheme.error.withValues(alpha: 0.7),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    message,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Action button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
                label: const Text('Cerrar'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}