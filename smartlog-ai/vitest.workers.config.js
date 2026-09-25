import { defineWorkersConfig } from "@cloudflare/vitest-pool-workers/config";

export default defineWorkersConfig({
	test: {
		// Só os testes que importam `cloudflare:test`; o resto roda no Node
		// (vitest.config.js).
		include: ["test/endpoints.spec.js"],
		poolOptions: {
			workers: {
				wrangler: { configPath: "./wrangler.jsonc" },
			},
		},
	},
});
