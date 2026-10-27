const fs = require("node:fs");
const path = require("node:path");
const { randomUUID } = require("node:crypto");
const BUCKET = "orbit-note-photos";
const validID = (id) => typeof id === "string" && /^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/.test(id);
class NotePhotos {
  constructor(directory) {
    this.directory = directory;
    fs.mkdirSync(directory, { recursive: true });
  }
  file(id) {
    if (!validID(id)) throw Error("Invalid photo");
    return path.join(this.directory, id + ".jpg");
  }
  save(bytes, id = randomUUID()) {
    const buffer = Buffer.from(bytes);
    if (buffer.length > 2097152 || buffer.length < 4 || buffer[0] !== 255 || buffer[1] !== 216)
      throw Error("Choose a photo smaller than 2 MB after resizing.");
    fs.writeFileSync(this.file(id), buffer, { mode: 0o600 });
    return { id, contentType: "image/jpeg" };
  }
  async uploadPending(records, client, uid) {
    for (const record of records.filter((r) => !r.deleted))
      for (const photo of record.payload.photos || []) {
        const file = this.file(photo.id),
          marker = file + ".uploaded";
        if (!fs.existsSync(file) || (fs.existsSync(marker) && fs.readFileSync(marker, "utf8") === uid)) continue;
        const { error } = await client.storage
          .from(BUCKET)
          .upload(`${uid}/${photo.id}.jpg`, fs.readFileSync(file), { contentType: "image/jpeg", upsert: true });
        if (error) throw error;
        fs.writeFileSync(marker, uid, { mode: 0o600 });
      }
  }
  async read(id, client) {
    const file = this.file(id);
    if (fs.existsSync(file)) return fs.readFileSync(file);
    const {
      data: { session },
    } = (await client?.auth.getSession()) || { data: {} };
    if (!session) throw Error("Connect to sync to load this photo.");
    const { data, error } = await client.storage.from(BUCKET).download(`${session.user.id}/${id}.jpg`);
    if (error) throw error;
    const bytes = Buffer.from(await data.arrayBuffer());
    this.save(bytes, id);
    fs.writeFileSync(file + ".uploaded", session.user.id, { mode: 0o600 });
    return bytes;
  }
  backupFiles(records) {
    const files = {};
    for (const record of records.filter((r) => !r.deleted))
      for (const photo of record.payload.photos || []) {
        files[photo.id] = fs.readFileSync(this.file(photo.id)).toString("base64");
      }
    return files;
  }
  restoreFiles(files, records) {
    for (const record of records)
      for (const photo of record.payload.photos || []) {
        if (!files[photo.id]) continue;
        const bytes = Buffer.from(files[photo.id], "base64"),
          file = this.file(photo.id);
        if (fs.existsSync(file)) {
          if (!fs.readFileSync(file).equals(bytes)) throw Error("This backup contains a conflicting photo.");
        } else this.save(bytes, photo.id);
      }
  }
  async eraseRemote(client) {
    const {
      data: { session },
    } = await client.auth.getSession();
    if (!session) throw Error("Sign in first");
    const bucket = client.storage.from(BUCKET),
      uid = session.user.id;
    while (true) {
      const { data, error } = await bucket.list(uid, { limit: 1000 });
      if (error) throw error;
      if (!data.length) break;
      const result = await bucket.remove(data.map((file) => `${uid}/${file.name}`));
      if (result.error) throw result.error;
    }
  }
  eraseLocal() {
    fs.rmSync(this.directory, { recursive: true, force: true });
    fs.mkdirSync(this.directory, { recursive: true });
  }
}
module.exports = { NotePhotos, validID };
