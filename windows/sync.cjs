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
    const before = JSON.stringify(this.store.rows());
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
      this.status = "Syncing…";
      this.notify("status");
      for (const r of this.store.rows().filter((r) => r.conflict)) this.store.accept(r.conflict);
      for (const row of this.store.rows().filter((r) => r.dirty && !r.conflict)) {
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
      }
      for (let offset = 0; ; offset += 500) {
        const { data, error } = await this.client
          .from("orbit_records")
          .select("*")
          .order("key")
          .range(offset, offset + 499);
        if (error) throw error;
        for (const row of data) this.store.accept(row);
        if (data.length < 500) break;
      }
      this.status = this.store.rows().some((r) => r.conflict)
        ? "A change needs review"
        : this.store.rows().some((r) => r.dirty)
          ? "Changes waiting to sync"
          : "All changes synced";
      if (this.store.rows().some((r) => r.dirty && !r.conflict)) this.again = true;
    } catch (e) {
      this.status = `Saved locally · ${e.message}`;
      this.again = false;
    } finally {
      this.busy = false;
      this.notify("status");
      if (before !== JSON.stringify(this.store.rows())) this.notify("data");
      if (this.again) queueMicrotask(() => void this.run());
    }
  }
}
module.exports = { Sync };
