const { contextBridge, ipcRenderer } = require("electron");
contextBridge.exposeInMainWorld("orbit", {
  undo: () => ipcRenderer.invoke("undo"),
  backup: (mode) => ipcRenderer.invoke("backup", mode),
  devices: () => ipcRenderer.invoke("devices"),
  removeDevice: (id) => ipcRenderer.invoke("remove-device", id),
  batch: (changes) => ipcRenderer.invoke("batch", changes),
  read: () => ipcRenderer.invoke("read"),
  put: (key, payload, deleted) => ipcRenderer.invoke("put", { key, payload, deleted }),
  auth: (mode, email, password) => ipcRenderer.invoke("auth", { mode, email, password }),
  sync: () => ipcRenderer.invoke("sync"),
  resolve: (key, choice) => ipcRenderer.invoke("resolve", { key, choice }),
  onSyncStatus: (callback) => ipcRenderer.on("sync-status", (_, value) => callback(value)),
  onChange: (callback) => ipcRenderer.on("changed", () => callback()),
});
