/// <reference path=../pb_data/types.d.ts />
//
// Bootstrap del usuario inicial del cliente Encantadas.
//
// Esta migration genera un password aleatorio que se imprime en los
// logs del container PocketBase al aplicarse. Para verlo:
//
//   docker logs pocketbase 2>&1 | grep ENCANTADAS_INITIAL_PASSWORD
//
// El cliente debe cambiar ese password en su primer login desde la
// app, o desde el admin UI: https://<server>/_/
//
migrate((app) => {
  // Generar password random con caracteres seguros (sin chars ambiguos
  // tipo 0/O o 1/l).
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';
  let pwd = '';
  for (let i = 0; i < 16; i++) {
    pwd += chars.charAt(Math.floor(Math.random() * chars.length));
  }

  const collection = app.findCollectionByNameOrId('encantadas_users');
  const record = new Record(collection);
  record.set('email', 'cliente@encantadas.app');
  record.set('emailVisibility', false);
  record.set('verified', true);
  record.set('name', 'Cliente Encantadas');
  record.set('business_name', 'Encantadas');
  record.setPassword(pwd);
  app.save(record);

  // Log el password una sola vez para que el admin lo capture
  console.log('============================================');
  console.log('ENCANTADAS_INITIAL_PASSWORD: ' + pwd);
  console.log('email: cliente@encantadas.app');
  console.log('Cambialo desde el admin UI tras primer login.');
  console.log('============================================');
}, (app) => {
  try {
    const u = app.findAuthRecordByEmail('encantadas_users', 'cliente@encantadas.app');
    app.delete(u);
  } catch(e) {}
});
