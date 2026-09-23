# 🚀 Deploy de Encantadas App

## 📱 Funciones Agregadas

### ✅ Import/Export Manual
- **Exportación**: Descarga todos los datos en formato JSON
- **Importación**: Restaura datos desde archivo JSON con vista previa
- **Validación**: Verifica formato de archivos antes de importar
- **Seguridad**: Doble backup (automático + manual)

### 🔧 Cómo Recuperar Datos Perdidos
1. Usar el archivo `encantadas_backup_version_11_2025-08-26.json`
2. Ir a **Configuraciones** → **Backup Manual** 
3. Hacer clic en **"Importar Datos"**
4. Seleccionar el archivo JSON del 12/08
5. Confirmar importación

## 🌐 Deploy en Netlify

### Opción 1: Deploy Manual
1. Ejecutar: `flutter build web --release --no-tree-shake-icons`
2. Crear archivo `build/web/_redirects` con: `/*    /index.html   200`
3. Comprimir carpeta `build/web/` en ZIP
4. Subir a [netlify.com](https://netlify.com) → "Deploy manually"

### Opción 2: Deploy Automático desde Git
1. Conectar repositorio en Netlify
2. Configurar build:
   - **Build command**: `flutter build web --release --no-tree-shake-icons`
   - **Publish directory**: `build/web`
3. Agregar archivo `_redirects` en `build/web/`

## 🔑 Configuración de Google Drive

### Variables de Entorno para Producción
Actualizar `web/google_drive_config.js`:

```javascript
window.googleDriveConfig = {
  clientId: 'TU_CLIENT_ID_DE_GOOGLE_CLOUD',
  scopes: [
    'https://www.googleapis.com/auth/drive.file',
    'https://www.googleapis.com/auth/drive.appdata'
  ],
  discoveryDocs: [
    'https://www.googleapis.com/discovery/v1/apis/drive/v3/rest'
  ]
};
```

### Pasos en Google Cloud Console
1. Crear proyecto en [console.cloud.google.com](https://console.cloud.google.com)
2. Habilitar "Google Drive API"
3. Crear credenciales "OAuth 2.0 Client ID"
4. Agregar dominio de Netlify a "Authorized JavaScript origins"
5. Copiar Client ID al archivo config

## 🛠️ Comandos de Desarrollo

```bash
# Instalar dependencias
flutter pub get

# Ejecutar en desarrollo
flutter run -d chrome

# Analizar código
flutter analyze

# Build para producción
flutter build web --release --no-tree-shake-icons

# Servir localmente
python3 -m http.server 8080 --directory build/web
```

## 📊 Datos Recuperados (12/08/2025)
- ✅ 13 Productos
- ✅ 12 Transacciones/Ventas
- ✅ 9 Citas  
- ✅ 14 Clientes con cuenta corriente
- ✅ 14 Cuentas corrientes
- ✅ 18 Movimientos de cuenta
- ✅ 1 Proveedor

## 🔄 Backup Strategy
1. **Automático**: Google Drive (cada 5 minutos)
2. **Manual**: Exportar/Importar JSON (cuando sea necesario)
3. **Recomendación**: Exportar semanalmente como respaldo local

---

**🤖 Generado con Claude Code**