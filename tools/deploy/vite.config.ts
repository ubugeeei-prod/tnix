import { defineConfig } from "vite-plus";

export default defineConfig({
  run: {
    tasks: {
      docs: {
        command: "cd ../.. && vp run docs:deploy",
        cache: false,
      },
    },
  },
});

