const { contextBridge, ipcRenderer } = require("electron");
contextBridge.exposeInMainWorld("orbit", {
  undo: () => ipcRenderer.invoke("undo"),
  backup: (mode, options) => ipcRenderer.invoke("backup", { mode, ...options }),
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
  onWake: (callback) => ipcRenderer.on("wake", () => callback()),
  onQuickAdd: (callback) => ipcRenderer.on("quick-add", () => callback()),
  desktopSettings: (changes) => ipcRenderer.invoke("desktop-settings", changes ?? null),
  reschedule: (zone) => ipcRenderer.invoke("reschedule", zone),
});
