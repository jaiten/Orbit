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
    // Every write stamps the record with the next change number (`seq`), so the window can ask for just
    // what changed since its last read instead of every record after each save.
    if (
      !this.db
        .prepare("PRAGMA table_info(records)")
        .all()
        .some((c) => c.name === "seq")
    ) {
      this.db.exec("ALTER TABLE records ADD COLUMN seq INTEGER NOT NULL DEFAULT 0");
      this.db.exec("UPDATE records SET seq=rowid");
    }
    this.db.exec(
      "CREATE INDEX IF NOT EXISTS records_seq ON records(seq);" +
        "CREATE TRIGGER IF NOT EXISTS records_seq_insert AFTER INSERT ON records BEGIN " +
        "UPDATE records SET seq=(SELECT COALESCE(MAX(seq),0)+1 FROM records) WHERE key=NEW.key; END;" +
        "CREATE TRIGGER IF NOT EXISTS records_seq_update AFTER UPDATE OF payload,deleted,revision,mutation,dirty,conflict,base_payload ON records BEGIN " +
        "UPDATE records SET seq=(SELECT COALESCE(MAX(seq),0)+1 FROM records) WHERE key=NEW.key; END;",
    );
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
  static parse(r) {
    return {
      ...r,
      payload: JSON.parse(r.payload),
      deleted: !!r.deleted,
      conflict: r.conflict ? JSON.parse(r.conflict) : null,
    };
  }
  rows() {
    return this.db.prepare("SELECT * FROM records ORDER BY key").all().map(Store.parse);
  }
  /** One record by key (undefined when there is none). */
  row(key) {
    const r = this.db.prepare("SELECT * FROM records WHERE key=?").get(key);
    return r ? Store.parse(r) : undefined;
  }
  /** Records with local changes not yet uploaded (`dirty`), or awaiting review (`conflict`). */
  dirtyRows() {
    return this.db.prepare("SELECT * FROM records WHERE dirty=1 ORDER BY key").all().map(Store.parse);
  }
  conflictRows() {
    return this.db.prepare("SELECT * FROM records WHERE conflict IS NOT NULL ORDER BY key").all().map(Store.parse);
  }
  /** Records of some kinds only ("tasks", "habits"…), for readers that need nothing else. */
  rowsOf(kinds) {
    const where = kinds.map(() => "key LIKE ?").join(" OR ");
    return this.db
      .prepare(`SELECT * FROM records WHERE ${where} ORDER BY key`)
      .all(...kinds.map((kind) => kind + "/%"))
      .map(Store.parse);
  }
  /** Whether any live task still carries an old-style repeat rule (see migrations.cjs). */
  hasLegacyRepeats() {
    return !!this.db
      .prepare(
        "SELECT 1 FROM records WHERE key LIKE 'tasks/%' AND deleted=0 AND conflict IS NULL AND COALESCE(json_extract(payload,'$.recurrenceRule'),'')<>'' LIMIT 1",
      )
      .get();
  }
  /** The latest change number: every write raises it. */
  seq() {
    return this.db.prepare("SELECT COALESCE(MAX(seq),0) AS seq FROM records").get().seq;
  }
  /** Records written after change number `seq` (deleted ones included, so the window can drop them). */
  changedSince(seq) {
    return this.db.prepare("SELECT * FROM records WHERE seq>? ORDER BY seq").all(seq).map(Store.parse);
  }
  /** Changes whenever records can disappear without a newer change (clearing the planner). */
  generation() {
    return this.setting("generation") || "0";
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
    if (!/^(tasks|habits|habit_logs|lists|idea_prompts|preferences|calendars|events)\/[a-z0-9-]{1,100}$/.test(key))
      throw Error("Invalid record key");
    if (!payload || typeof payload !== "object" || Array.isArray(payload) || JSON.stringify(payload).length > 100000)
      throw Error("Invalid record");
    if (
      !deleted &&
      ["tasks", "habits", "lists"].includes(key.split("/")[0]) &&
      !(payload.title || payload.name)?.trim() &&
      !(key.startsWith("tasks/") && payload.isNote === true)
    )
      throw Error("A name is required");
    this.db
      .prepare(
        "INSERT INTO records(key,payload,deleted,mutation) VALUES(?,?,?,?) ON CONFLICT(key) DO UPDATE SET payload=excluded.payload,deleted=excluded.deleted,mutation=excluded.mutation,dirty=1",
      )
      .run(key, JSON.stringify(payload), +deleted, randomUUID());
  }
  accept(remote, sent) {
    const current = this.row(remote.key),
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
    const row = this.row(key);
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
  clearPlanner() {
    this.db.exec("BEGIN IMMEDIATE");
    try {
      this.db.exec("DELETE FROM records; DELETE FROM settings WHERE key='owner';");
      this.setting("generation", String(Date.now()));
      this.db.exec("COMMIT");
    } catch (e) {
      this.db.exec("ROLLBACK");
      throw e;
    }
  }
  close() {
    this.db.close();
  }
}
module.exports = { Store };
