/**
 * Seleção das entregas que entram no contexto do modelo.
 *
 * O contexto não cabe a operação inteira: há um teto de entregas detalhadas
 * para controlar custo de token. Antes esse recorte eram simplesmente as
 * primeiras N entregas na ordem em que o Firestore as devolvia — ou seja,
 * ordem de __name__, que é aleatória. Perguntar por uma entrega fora dessa
 * janela nunca funcionava, mesmo com o dado existindo na base.
 *
 * Aqui o recorte passa a ser guiado pela pergunta: o que o usuário citou
 * entra primeiro; o resto do espaço é preenchido pelas mais recentes.
 *
 * Tudo neste arquivo é função pura — nada de rede, nada de Firestore.
 */

import {chave, maisRecentePrimeiro, normalizarStatus} from "./contexto.js";

// Código amigável da entrega, ex.: ENT-A8F31 (dashboard_admin.dart:706).
const PADRAO_CODIGO = /ENT-[A-Z0-9]{3,}/gi;

// Palavras curtas demais ou genéricas demais para servirem de filtro.
const RUIDO = new Set([
  "a", "à", "as", "o", "os", "um", "uma", "de", "do", "da", "dos", "das",
  "em", "no", "na", "nos", "nas", "por", "para", "com", "sem", "que", "qual",
  "quais", "quantas", "quantos", "onde", "quando", "como", "esta", "está",
  "estao", "estão", "sao", "são", "e", "ou", "me", "meu", "minha", "meus",
  "minhas", "the", "entrega", "entregas", "pedido", "pedidos", "status",
  "hoje", "agora", "ainda", "mais", "menos", "todas", "todos", "lista",
  "listar", "mostrar", "quero", "saber", "ver", "sobre", "qual e", "tem",
]);

/**
 * Quebra a pergunta em tokens comparáveis, descartando ruído.
 *
 * @param {string} pergunta Pergunta do usuário.
 * @return {!Set<string>} Tokens normalizados.
 */
function tokens(pergunta) {
  const saida = new Set();
  for (const bruto of chave(pergunta).split(/[^a-z0-9-]+/)) {
    if (bruto.length < 3) continue;
    if (RUIDO.has(bruto)) continue;
    saida.add(bruto);
  }
  return saida;
}

/**
 * Extrai da pergunta o que serve para localizar entregas.
 *
 * @param {string} pergunta Pergunta do usuário.
 * @return {!Object} Códigos citados e tokens de busca.
 */
export function extrairAlvos(pergunta) {
  const texto = String(pergunta || "");
  const codigos = new Set(
      (texto.match(PADRAO_CODIGO) || []).map((c) => c.toUpperCase()),
  );
  return {codigos, termos: tokens(texto)};
}

/**
 * Uma entrega casa com a pergunta?
 *
 * Só campos que o usuário teria como citar: nunca IDs internos.
 *
 * @param {!Object} e Entrega normalizada.
 * @param {!Object} alvos Saída de extrairAlvos.
 * @return {number} Peso do casamento; 0 se não casa.
 */
function pontuar(e, alvos) {
  if (alvos.codigos.has(String(e.codigo).toUpperCase())) return 100;

  if (alvos.termos.size === 0) return 0;

  let pontos = 0;
  const campos = [
    [e.cliente, 8],
    [e.motorista, 8],
    [e.regiao, 5],
    [e.status, 4],
    [e.endereco, 3],
    [e.recebedor, 3],
  ];

  for (const [valor, peso] of campos) {
    const k = chave(valor);
    if (!k) continue;
    for (const termo of alvos.termos) {
      // Casamento por palavra inteira ou por prefixo do campo, para que
      // "sul" case com "Zona Sul" mas "sul" não case com "consultoria".
      if (k === termo || k.split(/\s+/).includes(termo)) {
        pontos += peso;
      } else if (termo.length >= 4 && k.includes(termo)) {
        pontos += Math.max(1, peso - 2);
      }
    }
  }

  return pontos;
}

/**
 * Escolhe as entregas que vão detalhadas no contexto.
 *
 * Prioridade:
 *   1. código citado literalmente na pergunta;
 *   2. casamento com motorista / cliente / região / status / endereço;
 *   3. preenchimento do espaço restante pelas mais recentes.
 *
 * @param {!Array<!Object>} entregas Entregas normalizadas.
 * @param {string} pergunta Pergunta do usuário.
 * @param {number} teto Máximo de entregas devolvidas.
 * @return {!Object} {lista, criterio, relevantes}.
 */
export function selecionar(entregas, pergunta, teto) {
  const alvos = extrairAlvos(pergunta);

  const comPeso = entregas
      .map((e) => ({e, peso: pontuar(e, alvos)}))
      .filter((x) => x.peso > 0)
      .sort((a, b) => b.peso - a.peso || maisRecentePrimeiro(a.e, b.e));

  const lista = [];
  const vistos = new Set();

  for (const {e} of comPeso) {
    if (lista.length >= teto) break;
    if (vistos.has(e)) continue;
    vistos.add(e);
    lista.push(e);
  }

  const relevantes = lista.length;

  if (lista.length < teto) {
    for (const e of [...entregas].sort(maisRecentePrimeiro)) {
      if (lista.length >= teto) break;
      if (vistos.has(e)) continue;
      vistos.add(e);
      lista.push(e);
    }
  }

  let criterio;
  if (entregas.length <= teto) {
    criterio = "Operação inteira — nenhuma entrega foi omitida.";
  } else if (relevantes > 0) {
    criterio =
      `${relevantes} entrega(s) que correspondem à pergunta, ` +
      `completadas com as mais recentes até ${lista.length}.`;
  } else {
    criterio =
      `As ${lista.length} entregas mais recentes. Nenhuma correspondeu ` +
      "diretamente aos termos da pergunta.";
  }

  return {lista, criterio, relevantes};
}

/**
 * Códigos citados na pergunta que não existem entre os visíveis.
 *
 * Permite ao assistente dizer "esse código não existe" em vez de dizer
 * que não encontrou — são coisas diferentes para quem opera.
 *
 * Recebe a lista COMPLETA de códigos que o perfil enxerga, nunca o recorte
 * detalhado: checar contra o recorte produziria "não existe" para entregas
 * que existem e apenas não couberam no contexto.
 *
 * @param {!Array<string>} codigosVisiveis Todos os códigos do perfil.
 * @param {string} pergunta Pergunta do usuário.
 * @return {!Array<string>} Códigos inexistentes.
 */
export function codigosInexistentes(codigosVisiveis, pergunta) {
  const {codigos} = extrairAlvos(pergunta);
  if (codigos.size === 0) return [];
  const existentes = new Set(
      (codigosVisiveis || []).map((c) => String(c).toUpperCase()),
  );
  return [...codigos].filter((c) => !existentes.has(c));
}

// Reexportado para os testes cobrirem a normalização junto da seleção.
export {normalizarStatus};
