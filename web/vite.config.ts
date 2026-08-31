import { defineConfig } from "vite";
import { tanstackStart } from "@tanstack/react-start/plugin/vite";
import viteReact from "@vitejs/plugin-react";

// Phoenix dev server; keep in sync with server/config/dev.exs.
const SERVER = "http://127.0.0.1:57400";

export default defineConfig({
  resolve: { tsconfigPaths: true },
  plugins: [tanstackStart({ spa: { enabled: true } }), viteReact()],
  server: {
    host: true,
    proxy: {
      "/socket": { target: SERVER, ws: true },
      "/api": { target: SERVER },
    },
  },
});
