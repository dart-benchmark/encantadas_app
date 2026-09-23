# Encantadas App

Sistema de gestión integral para boutique de uñas. Flutter Web deployado en Netlify con backup automático a Google Drive.

## Funcionalidades

- **Productos** — Catálogo con stock, precios y QR codes por producto
- **Ventas** — Registro de transacciones y historial
- **Citas** — Agenda de turnos con notificaciones locales
- **Clientes** — Base de clientes con cuenta corriente y movimientos
- **Proveedores** — Gestión de proveedores
- **Dashboard** — Estadísticas con gráficos (pie chart)
- **WhatsApp** — Contacto directo con clientes desde la app
- **Backup** — Google Drive automático (cada 5 min) + export/import JSON manual

## Stack

- **Flutter** (Dart) — Web + Android + iOS + Desktop
- **Hive** — Base de datos local (offline-first)
- **Google Drive API** — Backup en la nube automático
- **flutter_local_notifications** — Recordatorios de citas
- **qr_flutter** — Generación de QR por producto
- **mobile_scanner** — Escaneo de QR
- **pie_chart** — Visualizaciones del dashboard
- **url_launcher** — Integración WhatsApp
- Deploy: **Netlify** (Flutter Web)

## Instalación

```bash
flutter pub get
flutter run -d chrome
```

## Build y Deploy

```bash
# Build producción
flutter build web --release --no-tree-shake-icons

# Agregar redirects para SPA en Netlify
echo "/*    /index.html   200" > build/web/_redirects

# Deploy manual: subir build/web/ como ZIP a Netlify
# Deploy automático: conectar repo en Netlify con:
#   Build command: flutter build web --release --no-tree-shake-icons
#   Publish directory: build/web
```

## Configuración Google Drive

Actualizar `web/google_drive_config.js` con el Client ID de Google Cloud Console:

```javascript
window.googleDriveConfig = {
  clientId: 'TU_CLIENT_ID',
  scopes: ['https://www.googleapis.com/auth/drive.file']
};
```

Ver instrucciones completas en [DEPLOY.md](./DEPLOY.md).

## Backup y Recuperación de Datos

- **Automático**: Google Drive cada 5 minutos
- **Manual**: Configuraciones → Backup Manual → Exportar/Importar JSON
- Ante pérdida de datos: importar el archivo `encantadas_backup_version_11_*.json` más reciente

## Estructura

```
lib/
├── main.dart
├── models/       # Modelos de datos (Hive)
├── screens/      # Pantallas de la app
├── services/     # Google Drive, notificaciones, backup
├── theme/        # Tema visual
├── utils/        # Helpers
└── widgets/      # Componentes reutilizables
```
