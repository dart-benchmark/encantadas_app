/// <reference path=../pb_data/types.d.ts />
migrate((app) => {
  // Agregar autodate fields a las collections de encantadas para
  // que ordenamiento por fecha y display funcionen.
  ['encantadas_backups', 'encantadas_files'].forEach(name => {
    const c = app.findCollectionByNameOrId(name);
    // Solo agregar si no existe ya
    if (!c.fields.find(f => f.name === 'created')) {
      c.fields.add(new Field({
        name: 'created',
        type: 'autodate',
        onCreate: true,
        onUpdate: false,
        system: true
      }));
    }
    if (!c.fields.find(f => f.name === 'updated')) {
      c.fields.add(new Field({
        name: 'updated',
        type: 'autodate',
        onCreate: true,
        onUpdate: true,
        system: true
      }));
    }
    app.save(c);
  });
}, (app) => {
  // Down: no removemos autodate (riesgoso)
});
