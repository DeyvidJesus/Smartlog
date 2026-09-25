// Testes do fetch handler no runtime real do Worker (workerd).
// Importam `cloudflare:test`, então só rodam com a config de workers:
//   npm run test:workers
// O vitest.config.js padrão (Node) exclui este arquivo.
import {
	env,
	createExecutionContext,
	waitOnExecutionContext,
} from "cloudflare:test";
import { describe, it, expect } from "vitest";
import worker from "../src/index.js";

describe("SmartLog AI Worker - endpoints", () => {
	it("retorna 404 para endpoints inexistentes", async () => {
		const request = new Request("http://example.com/");
		const ctx = createExecutionContext();
		const response = await worker.fetch(request, env, ctx);
		await waitOnExecutionContext(ctx);
		expect(response.status).toBe(404);
		const data = await response.json();
		expect(data.erro).toContain("Endpoint não encontrado");
	});

	it("retorna 405 para GET /chat", async () => {
		const request = new Request("http://example.com/chat", { method: "GET" });
		const ctx = createExecutionContext();
		const response = await worker.fetch(request, env, ctx);
		await waitOnExecutionContext(ctx);
		expect(response.status).toBe(405);
	});

	it("retorna 204 para OPTIONS /chat (CORS)", async () => {
		const request = new Request("http://example.com/chat", { method: "OPTIONS" });
		const ctx = createExecutionContext();
		const response = await worker.fetch(request, env, ctx);
		await waitOnExecutionContext(ctx);
		expect(response.status).toBe(204);
	});

	it("retorna 401 para POST /chat sem token", async () => {
		const request = new Request("http://example.com/chat", {
			method: "POST",
			body: JSON.stringify({ pergunta: "Qual o status?" }),
		});
		const ctx = createExecutionContext();
		const response = await worker.fetch(request, env, ctx);
		await waitOnExecutionContext(ctx);
		expect(response.status).toBe(401);
		const data = await response.json();
		expect(data.erro).toContain("Autenticação obrigatória");
	});
});
