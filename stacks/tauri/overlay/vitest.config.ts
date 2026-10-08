import { defineConfig } from "vitest/config";

// __NAME__ — tauri stack pack overlay (REQ-303/304). src/main.ts is Tauri's
// generated entry point and is excluded from coverage per pack.yml's
// coverage_exclude (REQ-325); the gates hook passes the line threshold on
// the vitest command line (--coverage.thresholds.lines).
export default defineConfig({
  test: {
    include: ["src/**/*.test.ts"],
    coverage: {
      provider: "v8",
      include: ["src/**/*.ts"],
      exclude: ["src/main.ts", "src/**/*.test.ts"],
    },
  },
});
