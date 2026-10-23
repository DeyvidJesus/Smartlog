import {test} from "node:test";
import assert from "node:assert/strict";
import {consultarModelo} from "../ai-provider.js";
test("uses Gemini and retains the scoped messages", async () => {
  const messages = [{role: "user", content: "ENT-TEST: PENDENTE"}];
  let captured;
  const result = await consultarModelo({apiKey: "test-only", mensagens: messages,
    fetchImpl: async (url, options) => {
      captured = {url, options};
      return {ok: true, status: 200, json: async () => ({choices: [{message: {content: "Pendente"}}]})};
    }});
  assert.equal(result, "Pendente");
  assert.match(captured.url, /^https:\/\/generativelanguage.googleapis.com\//);
  assert.deepEqual(JSON.parse(captured.options.body).messages, messages);
});
test("does not call the provider without a key", async () => {
  await assert.rejects(consultarModelo({mensagens: [], fetchImpl: () => {throw new Error("must not call");}}), /CREDENCIAL/);
});
for (const [status, message] of [[429, "LIMITE"], [403, "CREDENCIAL"], [500, "UPSTREAM"]]) {
  test(`propagates HTTP ${status} without inventing an answer`, async () => {
    await assert.rejects(consultarModelo({apiKey: "test-only", mensagens: [], fetchImpl: async () => ({ok: false, status})}), new RegExp(message));
  });
}
test("rejects empty content", async () => {
  await assert.rejects(consultarModelo({apiKey: "test-only", mensagens: [], fetchImpl: async () => ({
    ok: true, status: 200, json: async () => ({choices: []}),
  })}), /UPSTREAM/);
});
