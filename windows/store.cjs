const { DatabaseSync } = require("node:sqlite");
const { randomUUID } = require("node:crypto");
const { isDeepStrictEqual } = require("node:util");
const { merge } = require("./merge.cjs");
class Store {
  constructor(path) {
    this.db = new DatabaseSync(path);
    this.db.exec(
      "PRAGMA journal_mode=WAL; CREATE TABLE IF NOT EXISTS records(key TEXT PRIMARY KEY, payload TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0, revision INTEGER NOT NULL DEFAULT 0, mutation TEXT NOT NULL, dirty INTEGER NOT NULL DEFAULT 1, conflict TEXT); CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY, value TEXT NOT NULL);",
    );
    if (
      !this.db
        .prepare("PRAGMA table_info(records)")
        .all()
        .some((c) => c.name === "base_payload")
    )
      this.db.exec("ALTER TABLE records ADD COLUMN base_payload TEXT");
  }
  setting(key, value) {
    if (value !== undefined) this.db.prepare("INSERT OR REPLACE INTO settings VALUES(?,?)").run(key, value);
    return this.db.prepare("SELECT value FROM settings WHERE key=?").get(key)?.value;
  }
  bind(user) {
    const owner = this.setting("owner");
    if (owner && owner !== user)
      throw Error("This planner belongs to another account. Sign in with the original account.");
    this.setting("owner", user);
  }
  rows() {
    return this.db
      .prepare("SELECT * FROM records ORDER BY key")
      .all()
      .map((r) => ({
        ...r,
        payload: JSON.parse(r.payload),
        deleted: !!r.deleted,
        conflict: r.conflict ? JSON.parse(r.conflict) : null,
      }));
  }
  batch(changes) {
    if (!Array.isArray(changes) || changes.length > 100000) throw Error("Invalid batch");
    this.db.exec("BEGIN IMMEDIATE");
    try {
      for (const c of changes) this.put(c.key, c.payload, c.deleted === true);
      this.db.exec("COMMIT");
    } catch (e) {
      this.db.exec("ROLLBACK");
      throw e;
    }
  }
  put(key, payload, deleted = false) {
    if (!/^(tasks|habits|habit_logs|lists|idea_prompts)\/[a-z0-9-]{1,100}$/.test(key))
      throw Error("Invalid record key");
    if (!payload || typeof payload !== "object" || Array.isArray(payload) || JSON.stringify(payload).length > 100000)
      throw Error("Invalid record");
    if (
      !deleted &&
      ["tasks", "habits", "lists"].includes(key.split("/")[0]) &&
      !(payload.title || payload.name)?.trim()
    )
      throw Error("A name is required");
    this.db
      .prepare(
        "INSERT INTO records(key,payload,deleted,mutation) VALUES(?,?,?,?) ON CONFLICT(key) DO UPDATE SET payload=excluded.payload,deleted=excluded.deleted,mutation=excluded.mutation,dirty=1",
      )
      .run(key, JSON.stringify(payload), +deleted, randomUUID());
  }
  accept(remote, sent) {
    const current = this.rows().find((r) => r.key === remote.key),
      baseline = JSON.stringify(remote.payload);
    if (sent && current?.mutation === sent.mutation) {
      this.db
        .prepare("UPDATE records SET revision=?,dirty=0,conflict=NULL,base_payload=? WHERE key=?")
        .run(remote.revision, baseline, remote.key);
      return;
    }
    if (current?.dirty) {
      if (sent) {
        this.db
          .prepare("UPDATE records SET revision=?,base_payload=? WHERE key=?")
          .run(remote.revision, baseline, remote.key);
      } else if (remote.revision > current.revision) {
        const combined =
          current.deleted === remote.deleted
            ? merge(current.payload, remote.payload, current.base_payload ? JSON.parse(current.base_payload) : null)
            : null;
        if (combined) {
          const dirty = !isDeepStrictEqual(combined, remote.payload);
          this.db
            .prepare(
              "UPDATE records SET payload=?,revision=?,dirty=?,conflict=NULL,base_payload=?,mutation=? WHERE key=?",
            )
            .run(
              JSON.stringify(combined),
              remote.revision,
              +dirty,
              baseline,
              dirty ? randomUUID() : remote.mutation,
              remote.key,
            );
        } else this.db.prepare("UPDATE records SET conflict=? WHERE key=?").run(JSON.stringify(remote), remote.key);
      }
      return;
    }
    if (current && current.revision >= remote.revision) return;
    this.db
      .prepare(
        "INSERT INTO records(key,payload,deleted,revision,mutation,dirty,base_payload) VALUES(?,?,?,?,?,0,?) ON CONFLICT(key) DO UPDATE SET payload=excluded.payload,deleted=excluded.deleted,revision=excluded.revision,mutation=excluded.mutation,dirty=0,conflict=NULL,base_payload=excluded.base_payload",
      )
      .run(remote.key, baseline, +remote.deleted, remote.revision, remote.mutation, baseline);
  }
  resolve(key, choice) {
    const row = this.rows().find((r) => r.key === key);
    if (!row?.conflict) return;
    if (choice === "cloud") {
      this.db.prepare("UPDATE records SET dirty=0 WHERE key=?").run(key);
      this.accept(row.conflict);
    } else if (choice === "local") {
      this.db
        .prepare("UPDATE records SET revision=?,base_payload=?,conflict=NULL,mutation=? WHERE key=?")
        .run(row.conflict.revision, JSON.stringify(row.conflict.payload), randomUUID(), key);
    } else throw Error("Invalid resolution");
  }
  close() {
    this.db.close();
  }
}
module.exports = { Store };
