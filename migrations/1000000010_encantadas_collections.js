/// <reference path=../pb_data/types.d.ts />
migrate((app) => {

  // ── Usuarios de Encantadas (auth) ──────────────────────────────────────
  // Single-user en producción (cliente único), pero estructurado para
  // soportar multi-tenant en el futuro sin migración adicional.
  const encantadasUsers = new Collection({
    type: 'auth',
    name: 'encantadas_users',
    passwordAuth: { enabled: true, identityFields: ['email'] },
    fields: [
      { name: 'name',         type: 'text' },
      { name: 'business_name', type: 'text' }
    ],
    listRule:   null,
    viewRule:   '@request.auth.id = id',
    createRule: null,  // Crear solo via admin UI o seed
    updateRule: '@request.auth.id = id',
    deleteRule: null
  });
  app.save(encantadasUsers);

  // ── Backups (un JSON por sync, versionado) ─────────────────────────────
  // Cada record es un snapshot completo de la app.
  // Retención: el cliente puede borrar viejos via UI, o cron en server.
  const encantadasBackups = new Collection({
    type: 'base',
    name: 'encantadas_backups',
    fields: [
      { name: 'owner',
        type: 'relation',
        required: true,
        collectionId: encantadasUsers.id,
        cascadeDelete: true,
        maxSelect: 1 },
      { name: 'data',
        type: 'json',
        required: true,
        maxSize: 5242880 },  // 5MB JSON max (suficiente para miles de transacciones)
      { name: 'data_hash',
        type: 'text',
        required: true,
        max: 64 },           // sha256 hex
      { name: 'version',
        type: 'text',
        required: true,
        max: 32 },
      { name: 'device_info',
        type: 'text',
        max: 200 },
      { name: 'stats',
        type: 'json',
        maxSize: 8192 }      // counts: products, transactions, etc
    ],
    indexes: [
      // Dedup: no guardar 2 veces el mismo snapshot del mismo owner
      'CREATE UNIQUE INDEX idx_encantadas_backups_owner_hash ON encantadas_backups (owner, data_hash)'
    ],
    // Solo el dueño accede a sus backups
    listRule:   '@request.auth.id != "" && owner = @request.auth.id',
    viewRule:   '@request.auth.id != "" && owner = @request.auth.id',
    createRule: '@request.auth.id != "" && owner = @request.auth.id',
    updateRule: null,  // Inmutable: no se editan, solo se crean nuevos
    deleteRule: '@request.auth.id != "" && owner = @request.auth.id'
  });
  app.save(encantadasBackups);

  // ── Archivos del cliente (futuro: fotos de productos) ──────────────────
  // Placeholder ya creado para no requerir migración después.
  const encantadasFiles = new Collection({
    type: 'base',
    name: 'encantadas_files',
    fields: [
      { name: 'owner',
        type: 'relation',
        required: true,
        collectionId: encantadasUsers.id,
        cascadeDelete: true,
        maxSelect: 1 },
      { name: 'kind',
        type: 'select',
        required: true,
        values: ['product_image', 'qr', 'avatar', 'other'] },
      { name: 'ref_id',
        type: 'text',
        max: 100 },           // ej: product code (P-001) o transaction id
      { name: 'file',
        type: 'file',
        required: true,
        maxSize: 5242880,     // 5MB por archivo
        mimeTypes: ['image/jpeg', 'image/png', 'image/webp', 'image/gif'] }
    ],
    indexes: [
      'CREATE INDEX idx_encantadas_files_owner_kind_ref ON encantadas_files (owner, kind, ref_id)'
    ],
    listRule:   '@request.auth.id != "" && owner = @request.auth.id',
    viewRule:   '@request.auth.id != "" && owner = @request.auth.id',
    createRule: '@request.auth.id != "" && owner = @request.auth.id',
    updateRule: '@request.auth.id != "" && owner = @request.auth.id',
    deleteRule: '@request.auth.id != "" && owner = @request.auth.id'
  });
  app.save(encantadasFiles);

}, (app) => {
  ['encantadas_files', 'encantadas_backups', 'encantadas_users'].forEach(name => {
    try { const c = app.findCollectionByNameOrId(name); app.delete(c); } catch(e) {}
  });
});
