import {describe, it, expect} from "vitest";

import {
  chave,
  normalizar,
  normalizarStatus,
  foiEntregue,
  estaAtrasada,
  lerDataBr,
  maisRecentePrimeiro,
  contextoAdministrador,
  contextoMotorista,
  contextoCliente,
  HORAS_LIMITE_ATRASO,
} from "../src/contexto.js";

import {
  extrairAlvos,
  selecionar,
  codigosInexistentes,
} from "../src/relevancia.js";

const AGORA = new Date("2026-09-21T12:00:00.000Z");

/** @param {number} h Horas no passado. @return {string} ISO. */
function horasAtras(h) {
  return new Date(AGORA.getTime() - h * 36e5).toISOString();
}

// Schema gravado por dashboard_admin.dart:693
const CRU_ADMIN = {
  _docId: "abc123xyz",
  id: "ENT-ABC1",
  empresaId: "emp1",
  cliente: "Padaria do Zé",
  emailCliente: "ze@padaria.com",
  endereco: "Rua A, 100",
  regiao: "Zona Sul",
  motorista: "Carlos Silva",
  motoristaId: "uid-carlos",
  status: "Pendente",
  data: "20/09/2026",
  criadoEm: horasAtras(2),
};

// Schema gravado por dashboard_controller.dart:197 — sem id nem motorista
const CRU_CONTROLLER = {
  _docId: "def456uvw",
  empresaId: "emp1",
  cliente: "Mercado Central",
  emailCliente: "contato@mercado.com",
  clienteId: "contato_mercado_com",
  endereco: "Av. B, 200",
  regiao: "Zona Norte",
  motoristaId: "",
  status: "Em Rota",
  data: "",
  criadoEm: horasAtras(50),
};

describe("chave", () => {
  it("remove acento e caixa para comparação", () => {
    expect(chave("Zona Sul")).toBe("zona sul");
    expect(chave("  SÃO PAULO ")).toBe("sao paulo");
    expect(chave(null)).toBe("");
  });
});

describe("normalizarStatus", () => {
  it("trata 'A Caminho' e 'Em Rota' como o mesmo estado", () => {
    expect(normalizarStatus("A Caminho")).toBe("Em Rota");
    expect(normalizarStatus("em rota")).toBe("Em Rota");
  });

  it("normaliza variações de conclusão e o vazio", () => {
    expect(normalizarStatus("ENTREGUE")).toBe("Entregue");
    expect(normalizarStatus("concluída")).toBe("Entregue");
    expect(normalizarStatus("")).toBe("Pendente");
    expect(normalizarStatus(undefined)).toBe("Pendente");
  });
});

describe("lerDataBr", () => {
  it("lê o formato dd/mm/aaaa digitado no app", () => {
    // new Date("20/09/2026") é inválido em JS — daí o parser dedicado
    expect(lerDataBr("20/09/2026").toISOString()).toBe(
        "2026-09-20T00:00:00.000Z",
    );
  });

  it("devolve null para vazio e para data impossível", () => {
    expect(lerDataBr("")).toBeNull();
    expect(lerDataBr("32/13/2026")).toBeNull();
  });
});

describe("normalizar", () => {
  it("lê o schema de dashboard_admin.dart", () => {
    const e = normalizar(CRU_ADMIN);
    expect(e.codigo).toBe("ENT-ABC1");
    expect(e.motorista).toBe("Carlos Silva");
    expect(e.motoristaId).toBe("uid-carlos");
    expect(e.criadoEm).toBeInstanceOf(Date);
    expect(e.dataAgendada).toBeInstanceOf(Date);
  });

  it("lê o schema de dashboard_controller.dart, sem id nem motorista", () => {
    const e = normalizar(CRU_CONTROLLER);
    // Sem o campo 'id', deriva o código do ID do documento com a mesma
    // regra de codigoEntrega() no app — nunca expõe o ID cru.
    expect(e.codigo).toBe("ENT-DEF4");
    expect(e.motorista).toBeNull();
    expect(e.status).toBe("Em Rota");
    expect(e.clienteEmail).toBe("contato@mercado.com");
  });

  it("aceita os nomes antigos motoristaUid e dataCriacao", () => {
    const e = normalizar({
      motoristaUid: "uid-antigo",
      dataCriacao: horasAtras(1),
      recebidoPor: "Ana",
    });
    expect(e.motoristaId).toBe("uid-antigo");
    expect(e.criadoEm).toBeInstanceOf(Date);
    expect(e.recebedor).toBe("Ana");
  });

  it("não quebra com documento vazio", () => {
    const e = normalizar({});
    expect(e.codigo).toBe("sem código");
    expect(e.status).toBe("Pendente");
    expect(e.criadoEm).toBeNull();
  });
});

describe("estaAtrasada", () => {
  it("usa criadoEm quando existe", () => {
    const nova = normalizar({...CRU_ADMIN, criadoEm: horasAtras(1)});
    const velha = normalizar({
      ...CRU_ADMIN,
      criadoEm: horasAtras(HORAS_LIMITE_ATRASO + 1),
    });
    expect(estaAtrasada(nova, AGORA)).toBe(false);
    expect(estaAtrasada(velha, AGORA)).toBe(true);
  });

  it("entrega concluída nunca está atrasada", () => {
    const e = normalizar({
      ...CRU_ADMIN,
      status: "Entregue",
      criadoEm: horasAtras(500),
    });
    expect(estaAtrasada(e, AGORA)).toBe(false);
  });

  it("cai para a data agendada quando não há criadoEm", () => {
    const vencida = normalizar({status: "Pendente", data: "01/01/2026"});
    const futura = normalizar({status: "Pendente", data: "31/12/2026"});
    expect(estaAtrasada(vencida, AGORA)).toBe(true);
    expect(estaAtrasada(futura, AGORA)).toBe(false);
  });

  it("devolve null — e não false — sem nenhuma data", () => {
    // Este é o bug antigo: sem data virava "no prazo", e o assistente
    // afirmava com segurança que não havia atrasos.
    const e = normalizar({status: "Pendente"});
    expect(estaAtrasada(e, AGORA)).toBeNull();
  });
});

describe("contextoAdministrador", () => {
  const entregas = [
    normalizar(CRU_ADMIN),
    normalizar(CRU_CONTROLLER),
    normalizar({...CRU_ADMIN, id: "ENT-ZZZ9", status: "Entregue"}),
    normalizar({id: "ENT-SEMD", status: "Pendente", cliente: "X"}),
  ];

  it("separa atrasadas, no prazo e sem data registrada", () => {
    const c = contextoAdministrador(entregas, entregas, 3, 7, AGORA, "todas");
    expect(c.entregasAtrasadas).toBe(1); // CRU_CONTROLLER, 50h
    expect(c.entregasNoPrazo).toBe(2); // CRU_ADMIN (2h) + a Entregue
    expect(c.entregasSemDataRegistrada).toBe(1); // ENT-SEMD
  });

  it("agrega por motorista separando ativas de concluídas", () => {
    const c = contextoAdministrador(entregas, entregas, 3, 7, AGORA, "todas");
    const carlos = c.cargaAtivaPorMotorista
        .find((m) => m.motorista === "Carlos Silva");
    expect(carlos).toEqual({
      motorista: "Carlos Silva",
      entregasAtivas: 1,
      entregasConcluidas: 1,
    });
  });

  it("informa a data de hoje", () => {
    const c = contextoAdministrador(entregas, entregas, 3, 7, AGORA, "todas");
    expect(c.hoje).toBe("2026-09-21");
  });

  it("agrega sobre tudo mesmo com lista detalhada recortada", () => {
    const c = contextoAdministrador(
        entregas,
        entregas.slice(0, 1),
        3,
        7,
        AGORA,
        "recorte",
    );
    expect(c.totalEntregas).toBe(4);
    expect(c.entregas).toHaveLength(1);
    expect(c.observacao).toContain("1 de 4");
  });
});

describe("contextoMotorista", () => {
  const entregas = [
    normalizar(CRU_ADMIN), // motoristaId: uid-carlos
    normalizar(CRU_CONTROLLER), // sem motorista
    normalizar({
      id: "ENT-P2",
      motoristaId: "uid-carlos",
      status: "Pendente",
      ordemEntrega: 1,
    }),
    normalizar({id: "ENT-OUT", motoristaId: "uid-outro", status: "Pendente"}),
  ];

  it("vincula por motoristaId — o campo que o app realmente grava", () => {
    // Regressão do bug central: o filtro antigo era por motoristaUid,
    // que nunca existiu, e todo motorista recebia contexto vazio.
    const c = contextoMotorista(entregas, "uid-carlos", "Carlos Silva", AGORA);
    expect(c.totalAtribuidas).toBe(2);
    expect(c.codigosAtribuidos).toContain("ENT-ABC1");
    expect(c.codigosAtribuidos).not.toContain("ENT-OUT");
  });

  it("ordena a rota por ordemEntrega", () => {
    const c = contextoMotorista(entregas, "uid-carlos", "Carlos Silva", AGORA);
    expect(c.proximaEntrega.codigo).toBe("ENT-P2");
    expect(c.proximaEntrega.paradaNaRota).toBe(1);
  });

  it("cai para o nome quando a entrega não tem motoristaId", () => {
    const semId = [
      normalizar({id: "ENT-NOM", motorista: "Carlos Silva", status: "Pendente"}),
    ];
    const c = contextoMotorista(semId, "uid-carlos", "Carlos Silva", AGORA);
    expect(c.totalAtribuidas).toBe(1);
  });

  it("avisa quando não há nada atribuído", () => {
    const c = contextoMotorista(entregas, "uid-ninguem", "Ninguém", AGORA);
    expect(c.totalAtribuidas).toBe(0);
    expect(c.avisoVinculo).toBeTruthy();
  });
});

describe("contextoCliente", () => {
  const entregas = [normalizar(CRU_ADMIN), normalizar(CRU_CONTROLLER)];

  it("vincula por e-mail mesmo com o nome divergente", () => {
    const c = contextoCliente(
        entregas,
        "Padaria do Ze",
        "ze@padaria.com",
        AGORA,
    );
    expect(c.totalPedidos).toBe(1);
    expect(c.pedidos[0].codigo).toBe("ENT-ABC1");
  });

  it("vincula por clienteId, o slug do e-mail gravado pelo app", () => {
    const c = contextoCliente(entregas, "Outro Nome", "", AGORA);
    expect(c.totalPedidos).toBe(0);
    const porSlug = contextoCliente(
        entregas,
        "Outro Nome",
        "contato@mercado.com",
        AGORA,
    );
    expect(porSlug.totalPedidos).toBe(1);
  });

  it("ainda vincula por nome, ignorando acento e caixa", () => {
    const c = contextoCliente(entregas, "PADARIA DO ZÉ", "", AGORA);
    expect(c.totalPedidos).toBe(1);
  });
});

describe("extrairAlvos", () => {
  it("captura o código da entrega em qualquer caixa", () => {
    const a = extrairAlvos("onde está a ent-abc1?");
    expect([...a.codigos]).toEqual(["ENT-ABC1"]);
  });

  it("descarta palavras de ruído", () => {
    const a = extrairAlvos("quantas entregas estão na zona sul?");
    expect(a.termos.has("zona")).toBe(true);
    expect(a.termos.has("sul")).toBe(true);
    expect(a.termos.has("quantas")).toBe(false);
    expect(a.termos.has("entregas")).toBe(false);
  });
});

describe("selecionar", () => {
  // 80 entregas: mais do que cabe no contexto
  const muitas = Array.from({length: 80}, (_, i) =>
    normalizar({
      id: `ENT-${String(i).padStart(4, "0")}`,
      cliente: i === 70 ? "Farmácia Bem Estar" : `Cliente ${i}`,
      regiao: i % 2 === 0 ? "Zona Sul" : "Zona Norte",
      motorista: i === 65 ? "Marina Duarte" : "Outro",
      status: "Pendente",
      criadoEm: horasAtras(80 - i),
    }),
  );

  it("inclui a entrega citada mesmo fora da janela das mais recentes", () => {
    // Regressão do bug: ENT-0005 é antiga e nunca entraria no recorte.
    const {lista} = selecionar(muitas, "onde está a ENT-0005?", 60);
    expect(lista.map((e) => e.codigo)).toContain("ENT-0005");
    expect(lista[0].codigo).toBe("ENT-0005");
  });

  it("encontra por nome de cliente citado", () => {
    const {lista, relevantes} = selecionar(
        muitas,
        "como está a entrega da Farmácia Bem Estar?",
        60,
    );
    expect(relevantes).toBeGreaterThan(0);
    expect(lista[0].cliente).toBe("Farmácia Bem Estar");
  });

  it("encontra por nome de motorista citado", () => {
    const {lista} = selecionar(muitas, "o que a Marina Duarte tem hoje?", 60);
    expect(lista[0].motorista).toBe("Marina Duarte");
  });

  it("respeita o teto e não repete entrega", () => {
    const {lista} = selecionar(muitas, "ENT-0005 e ENT-0006", 60);
    expect(lista).toHaveLength(60);
    expect(new Set(lista.map((e) => e.codigo)).size).toBe(60);
  });

  it("sem termo útil, devolve as mais recentes", () => {
    const {lista, relevantes, criterio} = selecionar(
        muitas,
        "resumir operação",
        10,
    );
    expect(relevantes).toBe(0);
    expect(lista[0].codigo).toBe("ENT-0079");
    expect(criterio).toContain("mais recentes");
  });

  it("avisa quando nada foi omitido", () => {
    const {criterio} = selecionar(muitas.slice(0, 3), "qualquer coisa", 60);
    expect(criterio).toContain("Operação inteira");
  });
});

describe("codigosInexistentes", () => {
  it("distingue código inexistente de dado ausente", () => {
    const codigos = ["ENT-ABC1", "ENT-ZZZ9"];
    expect(codigosInexistentes(codigos, "cadê a ENT-NADA?")).toEqual([
      "ENT-NADA",
    ]);
    expect(codigosInexistentes(codigos, "cadê a ENT-ABC1?")).toEqual([]);
  });

  it("fica vazio quando a pergunta não cita código", () => {
    expect(codigosInexistentes(["ENT-ABC1"], "quantas faltam?")).toEqual([]);
  });
});

describe("maisRecentePrimeiro", () => {
  it("põe entregas sem data no fim", () => {
    const comData = normalizar({id: "A", criadoEm: horasAtras(10)});
    const semData = normalizar({id: "B"});
    expect([semData, comData].sort(maisRecentePrimeiro)[0].codigo).toBe("A");
  });
});

describe("foiEntregue", () => {
  it("aceita as variações de escrita da base", () => {
    expect(foiEntregue({status: "Entregue"})).toBe(true);
    expect(foiEntregue({status: "concluída"})).toBe(true);
    expect(foiEntregue({status: "Em Rota"})).toBe(false);
  });
});
