// Gemini free-tier adapter. No secret is bundled into Flutter or Angular.
export async function consultarModelo({apiKey, modelo = "gemini-3.1-flash-lite", mensagens, fetchImpl = fetch}) {
  if (!apiKey) throw new Error("CREDENCIAL");
  const response = await fetchImpl("https://generativelanguage.googleapis.com/v1beta/openai/chat/completions", {
    method: "POST",
    headers: {"Content-Type": "application/json", "Authorization": `Bearer ${apiKey}`},
    body: JSON.stringify({model: modelo, messages: mensagens, max_tokens: 900}),
    signal: AbortSignal.timeout(35000),
  });
  if (response.status === 429) throw new Error("LIMITE");
  if (response.status === 401 || response.status === 403) throw new Error("CREDENCIAL");
  if (!response.ok) throw new Error("UPSTREAM");
  const body = await response.json();
  const text = body?.choices?.[0]?.message?.content;
  if (typeof text !== "string" || !text.trim()) throw new Error("UPSTREAM");
  return text.trim();
}
