/**
 * Montagem do contexto operacional enviado à OpenAI.
 *
 * O contexto é SEMPRE construído a partir da identidade validada — nada do
 * que o cliente manda no corpo influencia o que o modelo enxerga.
 *
 * ⚠️ CONVIVÊNCIA DE SCHEMAS
 * A coleção `entregas` foi escrita por dois caminhos diferentes do app, com
 * nomes de campo distintos para a mesma informação:
 *
 *   dashboard_admin.dart      → id, motorista, motoristaId, data, status
 *   dashboard_controller.dart → clienteId, emailCliente, motoristaId, criadoEm
 *
 * Nenhum dos dois grava `motoristaUid`, `dataCriacao`, `ordemEntrega` ou
 * `recebedor`, que é o que a versão anterior deste arquivo lia. Resultado:
 * o motorista recebia contexto vazio e "atrasadas" era sempre zero.
 *
 * `normalizar()` abaixo é a única porta de entrada: toda entrega passa por
 * ela antes de qualquer contagem, filtro ou projeção.
 */

// Mesmo valor do DashboardController.horasLimiteAtraso, para o assistente
// e o painel AI Insights nunca divergirem sobre o que é "atraso".
export const HORAS_LIMITE_ATRASO = 24;

// Teto de entregas detalhadas no contexto — controla custo de token.
export const MAX_ENTREGAS_CONTEXTO = 60;

// Status que contam como entrega concluída, já normalizados.
const CONCLUIDOS = new Set(["entregue", "concluida", "finalizada"]);

/**
 * Minúsculas, sem acento e sem espaço sobrando.
 *
 * Usado em toda comparação de texto: o app grava "Zona Sul", "zona sul" e
 * "ZONA SUL" em telas diferentes, e comparação exata perdia o vínculo.
 *
 * @param {*} t Texto bruto.
 * @return {string} Texto comparável.
 */
export function chave(t) {
  return String(t == null ? "" : t)
      .normalize("NFD")
      .replace(/[̀-ͯ]/g, "")
      .trim()
      .toLowerCase();
}

/**
 * Canonicaliza o status. "A Caminho" e "Em Rota" são o mesmo estado: o app
 * usa os dois nomes (dashboard_controller.dart:414).
 *
 * @param {*} s Status bruto.
 * @return {string} Status exibível.
 */
export function normalizarStatus(s) {
  const k = chave(s);
  if (!k) return "Pendente";
  if (k === "pendente") return "Pendente";
  if (k === "em rota" || k === "a caminho") return "Em Rota";
  if (CONCLUIDOS.has(k)) return "Entregue";
  if (k === "atrasada") return "Atrasada";
  return String(s).trim();
}

/**
 * @param {!Object} e Entrega já normalizada.
 * @return {boolean} true se a entrega foi concluída.
 */
export function foiEntregue(e) {
  return CONCLUIDOS.has(chave(e.status));
}

/**
 * A base convive com Timestamp (vira ISO 8601 no cliente REST) e String ISO.
 *
 * @param {*} v Valor bruto do campo de data.
 * @return {?Date} Data convertida, ou null se ausente/ilegível.
 */
function lerData(v) {
  if (!v) return null;
  if (v instanceof Date) return isNaN(v.getTime()) ? null : v;
  if (typeof v === "string") {
    const d = new Date(v);
    return isNaN(d.getTime()) ? null : d;
  }
  return null;
}

/**
 * Lê o campo `data` da entrega, digitado à mão como "dd/mm/aaaa".
 *
 * new Date("25/12/2026") é inválido em JS, por isso o parser dedicado.
 *
 * @param {*} v Valor bruto.
 * @return {?Date} Data agendada, ou null.
 */
export function lerDataBr(v) {
  if (!v) return null;
  const t = String(v).trim();
  const m = t.match(/^(\d{1,2})[/-](\d{1,2})[/-](\d{4})$/);
  if (m) {
    const dia = Number(m[1]);
    const mes = Number(m[2]);
    const ano = Number(m[3]);
    if (mes < 1 || mes > 12 || dia < 1 || dia > 31) return null;
    const d = new Date(Date.UTC(ano, mes - 1, dia));
    return isNaN(d.getTime()) ? null : d;
  }
  return lerData(t);
}

/**
 * Código amigável derivado do ID do documento.
 *
 * Espelha `codigoEntrega()` em lib/controllers/dashboard_controller.dart —
 * as duas implementações precisam gerar o mesmo texto, senão o assistente
 * cita um código que o usuário não encontra na tela. Serve para as entregas
 * antigas, gravadas antes de o app passar a persistir o campo `id`.
 *
 * @param {string} docId ID do documento no Firestore.
 * @return {string} Código no formato ENT-XXXX.
 */
function codigoDerivado(docId) {
  const base = docId.length >= 4 ? docId.slice(0, 4) : docId;
  return `ENT-${base.toUpperCase()}`;
}

/**
 * Traduz um documento cru de `entregas` para a forma canônica usada aqui.
 *
 * Cada campo aceita todos os nomes já gravados na base.
 *
 * @param {!Object} e Documento cru do Firestore.
 * @return {!Object} Entrega normalizada.
 */
export function normalizar(e) {
  const d = e || {};
  return {
    // Nunca o ID cru do documento: é identificador técnico, que o prompt
    // proíbe revelar, e não corresponde a nada que o usuário veja.
    codigo: d.id || d.Id ||
      (d._docId ? codigoDerivado(String(d._docId)) : "sem código"),
    endereco: d.endereco || "não informado",
    regiao: d.regiao || "não definida",
    status: normalizarStatus(d.status),
    motorista: d.motorista || d.motoristaNome || null,
    motoristaId: String(d.motoristaId || d.motoristaUid || ""),
    cliente: d.cliente || "não informado",
    clienteId: String(d.clienteId || ""),
    clienteEmail: chave(d.emailCliente || d.clienteEmail || ""),
    ordemEntrega: d.ordemEntrega == null ? null : Number(d.ordemEntrega),
    criadoEm: lerData(d.criadoEm ?? d.dataCriacao),
    dataAgendada: lerDataBr(d.data ?? d.dataAgendada),
    entregueEm: lerData(d.entregueEm ?? d.dataEntrega),
    recebedor: d.recebedor ?? d.recebidoPor ?? null,
  };
}

/**
 * Horas inteiras decorridas desde uma data.
 *
 * @param {?Date} data Data inicial.
 * @param {!Date} agora Instante de referência.
 * @return {?number} Horas, ou null se a data for nula.
 */
function horasDesde(data, agora) {
  if (!data) return null;
  return Math.floor((agora.getTime() - data.getTime()) / 36e5);
}

/**
 * Atrasada = status explícito, ou não concluída além do limite.
 *
 * Devolve `null` — e não `false` — quando a entrega não tem nenhuma data
 * gravada. Antes isso virava "no prazo", e o assistente afirmava com
 * segurança que não havia atrasos numa base inteira sem datas.
 *
 * @param {!Object} e Entrega já normalizada.
 * @param {!Date} agora Instante de referência.
 * @return {?boolean} true, false, ou null se indeterminado.
 */
export function estaAtrasada(e, agora) {
  if (chave(e.status) === "atrasada") return true;
  if (foiEntregue(e)) return false;

  const h = horasDesde(e.criadoEm, agora);
  if (h !== null) return h >= HORAS_LIMITE_ATRASO;

  // Sem criadoEm, a data agendada ainda permite uma conclusão segura:
  // prazo vencido e não entregue = atrasada.
  if (e.dataAgendada) return e.dataAgendada.getTime() < agora.getTime();

  return null;
}

/**
 * Ordenação padrão: mais recentes primeiro, sem data por último.
 *
 * @param {!Object} a Entrega normalizada.
 * @param {!Object} b Entrega normalizada.
 * @return {number} Comparador.
 */
export function maisRecentePrimeiro(a, b) {
  const ta = (a.criadoEm || a.dataAgendada || null);
  const tb = (b.criadoEm || b.dataAgendada || null);
  if (ta && tb) return tb.getTime() - ta.getTime();
  if (ta) return -1;
  if (tb) return 1;
  return String(a.codigo).localeCompare(String(b.codigo));
}

/**
 * Projeção enxuta enviada ao modelo: sem UIDs nem campos internos.
 *
 * @param {!Object} e Entrega já normalizada.
 * @param {!Date} agora Instante de referência.
 * @return {!Object} Entrega resumida.
 */
function resumir(e, agora) {
  return {
    codigo: e.codigo,
    endereco: e.endereco,
    regiao: e.regiao,
    status: e.status,
    motorista: e.motorista || "sem motorista atribuído",
    cliente: e.cliente,
    paradaNaRota: e.ordemEntrega,
    dataAgendada: e.dataAgendada ? iso(e.dataAgendada) : null,
    horasDesdeCriacao: horasDesde(e.criadoEm, agora),
    atrasada: estaAtrasada(e, agora),
    recebidoPor: e.recebedor,
  };
}

/**
 * @param {!Date} d Data.
 * @return {string} Só a parte da data, em ISO.
 */
function iso(d) {
  return d.toISOString().slice(0, 10);
}

/**
 * Bloco de tempo presente em todo contexto.
 *
 * Sem isto o modelo não tem como responder "quantas entregas para hoje?",
 * porque não sabe que dia é hoje.
 *
 * @param {!Date} agora Instante de referência.
 * @return {!Object} Referência temporal.
 */
function agoraLegivel(agora) {
  return {
    dataHoraAtual: agora.toISOString(),
    hoje: iso(agora),
    fusoHorario: "UTC (converta para America/Sao_Paulo ao responder)",
  };
}

/**
 * Contexto do Administrador: visão agregada da empresa.
 *
 * Os agregados cobrem TODAS as entregas da empresa, não só as que cabem na
 * lista detalhada — o modelo nunca precisa contar nada por conta própria.
 *
 * @param {!Array<!Object>} entregas Entregas normalizadas da empresa.
 * @param {!Array<!Object>} selecionadas Recorte relevante para a pergunta.
 * @param {number} totalMotoristas Motoristas cadastrados.
 * @param {number} totalClientes Clientes cadastrados.
 * @param {!Date} agora Instante de referência.
 * @param {string} criterioSelecao Como as entregas detalhadas foram escolhidas.
 * @return {!Object} Contexto para o modelo.
 */
export function contextoAdministrador(
    entregas,
    selecionadas,
    totalMotoristas,
    totalClientes,
    agora,
    criterioSelecao,
) {
  const porStatus = {};
  const porRegiao = {};
  const porMotorista = {};
  const porCliente = {};
  let atrasadas = 0;
  let noPrazo = 0;
  let semData = 0;
  let semMotorista = 0;

  for (const e of entregas) {
    porStatus[e.status] = (porStatus[e.status] || 0) + 1;

    const regiao = String(e.regiao || "").trim();
    if (regiao && regiao !== "não definida") {
      const r = porRegiao[regiao] || (porRegiao[regiao] = {total: 0});
      r.total++;
      r[e.status] = (r[e.status] || 0) + 1;
    }

    const nome = String(e.motorista || "").trim();
    const temMotorista = nome && chave(nome) !== "sem motorista";
    if (!temMotorista) {
      semMotorista++;
    } else {
      const m = porMotorista[nome] ||
        (porMotorista[nome] = {ativas: 0, entregues: 0});
      if (foiEntregue(e)) m.entregues++;
      else m.ativas++;
    }

    const cliente = String(e.cliente || "").trim();
    if (cliente && cliente !== "não informado") {
      porCliente[cliente] = (porCliente[cliente] || 0) + 1;
    }

    const atraso = estaAtrasada(e, agora);
    if (atraso === true) atrasadas++;
    else if (atraso === false) noPrazo++;
    else semData++;
  }

  const concluidas = porStatus["Entregue"] || 0;
  const cargaAtiva = Object.entries(porMotorista)
      .sort((a, b) => b[1].ativas - a[1].ativas || a[0].localeCompare(b[0]))
      .map(([motorista, n]) => ({
        motorista,
        entregasAtivas: n.ativas,
        entregasConcluidas: n.entregues,
      }));

  const topClientes = Object.entries(porCliente)
      .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
      .slice(0, 10)
      .map(([cliente, totalEntregas]) => ({cliente, totalEntregas}));

  const truncou = selecionadas.length < entregas.length;

  return {
    escopo: "Operação completa da empresa",
    ...agoraLegivel(agora),
    totalEntregas: entregas.length,
    totalMotoristasCadastrados: totalMotoristas,
    totalClientesCadastrados: totalClientes,
    distribuicaoPorStatus: porStatus,
    distribuicaoPorRegiao: porRegiao,
    percentualConcluidas: entregas.length === 0 ?
      0 :
      Math.round((concluidas / entregas.length) * 100),
    entregasAtrasadas: atrasadas,
    entregasNoPrazo: noPrazo,
    entregasSemDataRegistrada: semData,
    criterioDeAtraso: `Não concluída há ${HORAS_LIMITE_ATRASO}h ou mais, ` +
      "ou com data agendada vencida",
    entregasSemMotorista: semMotorista,
    cargaAtivaPorMotorista: cargaAtiva,
    clientesComMaisEntregas: topClientes,
    entregas: selecionadas.map((e) => resumir(e, agora)),
    criterioSelecao,
    observacao: truncou ?
      `Lista detalhada limitada a ${selecionadas.length} de ` +
        `${entregas.length} entregas. Todos os números agregados acima ` +
        "consideram a operação inteira." :
      null,
  };
}

/**
 * Contexto do Motorista: só as entregas atribuídas a ele.
 *
 * O vínculo é por `motoristaId` (o UID gravado pelo app). Como parte das
 * entregas antigas ficou com `motoristaId: ''` e só o nome preenchido, há
 * um fallback por nome — senão o motorista vê uma rota vazia.
 *
 * @param {!Array<!Object>} entregas Entregas normalizadas da empresa.
 * @param {string} uid UID autenticado do motorista.
 * @param {string} nomeMotorista Nome cadastrado em usuarios/<uid>.
 * @param {!Date} agora Instante de referência.
 * @return {!Object} Contexto para o modelo.
 */
export function contextoMotorista(entregas, uid, nomeMotorista, agora) {
  const nome = chave(nomeMotorista);
  const minhas = entregas.filter((e) => {
    if (e.motoristaId && e.motoristaId === uid) return true;
    if (!e.motoristaId && nome && chave(e.motorista) === nome) return true;
    return false;
  });

  const pendentes = minhas
      .filter((e) => !foiEntregue(e))
      .sort((a, b) => {
        const oa = a.ordemEntrega == null ? Infinity : a.ordemEntrega;
        const ob = b.ordemEntrega == null ? Infinity : b.ordemEntrega;
        if (oa !== ob) return oa - ob;
        return maisRecentePrimeiro(a, b);
      });
  const concluidas = minhas.filter(foiEntregue);

  return {
    escopo: "Somente as entregas atribuídas a este motorista",
    ...agoraLegivel(agora),
    totalAtribuidas: minhas.length,
    entregasRestantes: pendentes.length,
    entregasConcluidas: concluidas.length,
    entregasAtrasadas: pendentes
        .filter((e) => estaAtrasada(e, agora) === true).length,
    proximaEntrega: pendentes.length > 0 ? resumir(pendentes[0], agora) : null,
    rotaPendente: pendentes
        .slice(0, MAX_ENTREGAS_CONTEXTO)
        .map((e) => resumir(e, agora)),
    ultimasConcluidas: concluidas
        .sort(maisRecentePrimeiro)
        .slice(0, 5)
        .map((e) => resumir(e, agora)),
    // Lista completa de códigos: as projeções acima são recortes, e sem isto
    // o assistente diria que uma entrega concluída antiga não existe.
    codigosAtribuidos: minhas.map((e) => e.codigo),
    avisoVinculo: minhas.length === 0 ?
      "Nenhuma entrega atribuída a este motorista. As entregas são " +
        "vinculadas pelo campo motoristaId no momento da criação da rota." :
      null,
  };
}

/**
 * Contexto do Cliente: só os pedidos vinculados a ele.
 *
 * O app grava o cliente de três formas (nome, emailCliente e clienteId,
 * este último um slug do e-mail). Casar só pelo nome, como antes, deixava
 * o cliente sem nenhum pedido à menor divergência de grafia.
 *
 * @param {!Array<!Object>} entregas Entregas normalizadas da empresa.
 * @param {string} nomeCliente Nome cadastrado do cliente autenticado.
 * @param {string} emailCliente E-mail cadastrado do cliente autenticado.
 * @param {!Date} agora Instante de referência.
 * @return {!Object} Contexto para o modelo.
 */
export function contextoCliente(entregas, nomeCliente, emailCliente, agora) {
  const nome = chave(nomeCliente);
  const email = chave(emailCliente);
  // Mesma regra de dashboard_controller.dart:160-162
  const slug = email ? email.replace(/[^a-z0-9]/g, "_") : "";

  const meus = entregas.filter((e) => {
    if (email && e.clienteEmail === email) return true;
    if (slug && e.clienteId && chave(e.clienteId) === slug) return true;
    if (nome && chave(e.cliente) === nome) return true;
    return false;
  });

  return {
    escopo: "Somente os pedidos deste cliente",
    ...agoraLegivel(agora),
    nomeCadastrado: nomeCliente || "não informado",
    totalPedidos: meus.length,
    pedidos: meus
        .sort(maisRecentePrimeiro)
        .slice(0, MAX_ENTREGAS_CONTEXTO)
        .map((e) => resumir(e, agora)),
    // Lista completa de códigos — "pedidos" acima é um recorte.
    codigosDosPedidos: meus.map((e) => e.codigo),
    avisoVinculo: meus.length === 0 ?
      "Nenhum pedido encontrado. As entregas são vinculadas pelo e-mail ou " +
        "pelo nome cadastrado do cliente; divergência nos dois impede o " +
        "vínculo." :
      null,
  };
}
