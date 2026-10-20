const { migrateRecurring } = require("./ui/conversions.js");

/** Applies data migrations to the local store. Records awaiting conflict review are left alone. */
function runMigrations(store, now = Date.now()) {
  const rows = store.rows().filter((r) => !r.deleted && !r.conflict);
  const entity = (name) => rows.filter((r) => r.key.startsWith(name + "/")).map((r) => ({ ...r.payload, _key: r.key }));
  const changes = migrateRecurring(entity("tasks"), entity("habit_logs"), now);
  if (changes.length) store.batch(changes);
  return changes.length;
}

module.exports = { runMigrations };
