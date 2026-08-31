import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { fileURLToPath } from "node:url";

// Phoenix dev server; keep in sync with server/config/dev.exs.
const SERVER = "http://127.0.0.1:57400";

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      "@": fileURLToPath(new URL("./src", import.meta.url)),
    },
  },
  server: {
    host: true,
    proxy: {
      "/socket": { target: SERVER, ws: true },
      "/api": { target: SERVER },
    },
  },
});
