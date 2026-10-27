const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { NotePhotos } = require("../note-photos.cjs");

test("photos stay local offline, upload before references, and round-trip in a portable backup", async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "orbit-photos-"));
  const photos = new NotePhotos(root);
  const bytes = Buffer.from([255, 216, 255, 217]);
  const photo = photos.save(bytes);
  const records = [{ payload: { photos: [photo] } }];
  const uploads = [];
  const client = {
    storage: {
      from: (bucket) => ({
        upload: async (name, data) => {
          uploads.push({ bucket, name, data });
          return {};
        },
      }),
    },
  };
  try {
    assert.deepEqual(await photos.read(photo.id, null), bytes);
    assert.throws(() => photos.file("../session.enc"), /Invalid photo/);
    assert.throws(() => photos.save(Buffer.alloc(2097153)), /smaller than 2 MB/);
    await photos.uploadPending(records, client, "owner-a");
    await photos.uploadPending(records, client, "owner-a");
    assert.equal(uploads.length, 1);
    assert.equal(uploads[0].bucket, "orbit-note-photos");
    assert.equal(uploads[0].name, `owner-a/${photo.id}.jpg`);
    const backup = photos.backupFiles(records);
    photos.eraseLocal();
    photos.restoreFiles(backup, records);
    assert.deepEqual(await photos.read(photo.id, null), bytes);
    await photos.uploadPending(records, client, "owner-b");
    assert.equal(uploads.at(-1).name, `owner-b/${photo.id}.jpg`);
    assert.throws(
      () => photos.restoreFiles({ [photo.id]: Buffer.from([255, 216, 1, 2]).toString("base64") }, records),
      /conflicting/,
    );
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});
