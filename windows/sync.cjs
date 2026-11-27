class Sync {
  constructor(store, client, notify) {
    Object.assign(this, { store, client, notify, busy: false, again: false, status: "Saved on this PC" });
  }
  async run() {
    if (this.busy) {
      this.again = true;
      return;
    }
    if (!this.client) return;
    this.busy = true;
    this.again = false;
    const started = Date.now();
    let uploaded = 0,
      pulled = 0,
      outcome = "ok";
    // The store's change number says whether this pass changed anything (no need to compare every record).
    const before = this.store.seq();
    try {
      const {
        data: { session },
        error,
      } = await this.client.auth.getSession();
      if (error) throw error;
      if (!session) {
        this.status = "Saved on this PC";
        return;
      }
      this.store.bind(session.user.id);
      if (this.beforeUpload) await this.beforeUpload(session.user.id);
      this.status = "Syncing…";
      this.notify("status");
      for (const r of this.store.conflictRows()) this.store.accept(r.conflict);
      for (const row of this.store.dirtyRows().filter((r) => !r.conflict)) {
        const { data, error } = await this.client.rpc("orbit_put", {
          p_key: row.key,
          p_payload: row.payload,
          p_deleted: row.deleted,
          p_base: row.revision,
          p_mutation: row.mutation,
        });
        if (error) throw error;
        if (data.accepted) this.store.accept(data.record, row);
        else this.store.accept(data.record);
        uploaded++;
      }
      for (let offset = 0; ; offset += 500) {
        const { data, error } = await this.client
          .from("orbit_records")
          .select("*")
          .order("key")
          .range(offset, offset + 499);
        if (error) throw error;
        for (const row of data) this.store.accept(row);
        pulled += data.length;
        if (data.length < 500) break;
      }
      const dirty = this.store.dirtyRows();
      this.status = this.store.conflictRows().length
        ? "A change needs review"
        : dirty.length
          ? "Changes waiting to sync"
          : "All changes synced";
      if (dirty.some((r) => !r.conflict)) this.again = true;
    } catch (e) {
      outcome = e?.name || "error";
      this.status = `Saved locally · ${e.message}`;
      this.again = false;
    } finally {
      this.busy = false;
      this.notify("status");
      if (before !== this.store.seq()) this.notify("data");
      console.info("orbit.sync", { durationMs: Date.now() - started, uploaded, pulled, outcome });
      if (this.again) queueMicrotask(() => void this.run());
    }
  }
}
module.exports = { Sync };
