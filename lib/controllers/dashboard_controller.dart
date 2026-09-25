// lib/controllers/dashboard_controller.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

/// Código amigável da entrega, exibido ao usuário e lido pelo scanner de QR.
///
/// Derivado do ID do documento para nunca colidir. Único ponto que gera esse
/// formato — o assistente de IA cita a entrega por ele, então divergência
/// entre telas fazia o chat responder "sem código".
String codigoEntrega(String docId) {
  final base = docId.length >= 4 ? docId.substring(0, 4) : docId;
  return 'ENT-${base.toUpperCase()}';
}

class DashboardController extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? empresaId;
  bool _carregando = false;
  bool _descartado = false;
  String? _analiseIA;
  String? _erro;

  // Listas locais de dados
  List<Map<String, dynamic>> _entregas = [];
  List<Map<String, dynamic>> _motoristas = [];
  List<Map<String, dynamic>> _clientes = [];
  List<Map<String, dynamic>> _rotas = [];
  Map<String, dynamic> _dadosEmpresa = {};

  DashboardController({this.empresaId});

  @override
  void dispose() {
    _descartado = true;
    super.dispose();
  }

  // --- GETTERS DE ESTADO ---
  bool get carregando => _carregando;
  bool get isLoading => _carregando;
  String? get analiseIA => _analiseIA;
  String? get erro => _erro;

  // --- GETTERS EXPOSTOS DE LISTAS ---
  List<Map<String, dynamic>> get entregas => List.unmodifiable(_entregas);
  List<Map<String, dynamic>> get rotas => List.unmodifiable(_rotas);
  List<Map<String, dynamic>> get motoristas => List.unmodifiable(_motoristas);
  List<Map<String, dynamic>> get clientes => List.unmodifiable(_clientes);
  Map<String, dynamic> get dadosEmpresa => _dadosEmpresa;

  // --- CONTADORES PARA O DASHBOARD ---
  int get totalEntregas => _entregas.length;
  int get totalMotoristasAtivos => _motoristas.length;
  int get totalClientesCadastrados => _clientes.length;

  // --- INICIALIZAÇÃO DE DADOS ---
  Future<void> inicializarDados(String idEmpresa) async {
    empresaId = idEmpresa;
    _carregando = true;
    _erro = null;
    if (!_descartado) notifyListeners();

    try {
      await Future.wait([
        carregarEntregas(),
        carregarMotoristas(),
        carregarClientes(),
        carregarRotas(),
        carregarPerfilEmpresa(idEmpresa),
      ]);
    } catch (e) {
      _erro = e.toString();
    } finally {
      _carregando = false;
      if (!_descartado) notifyListeners();
    }
  }

  // --- MÉTODOS DE CARREGAMENTO (FIRESTORE) ---
  Future<void> carregarEntregas() async {
    try {
      if (empresaId == null) {
        debugPrint("DEBUG: carregarEntregas abortado pois empresaId é nulo.");
        return;
      }

      final snapshot = await _firestore
          .collection('entregas')
          .where('empresaId', isEqualTo: empresaId)
          .get();

      // 'id' é sempre o código amigável (ENT-XXXX). Entregas antigas não têm
      // esse campo gravado, então ele é derivado do ID do documento — a
      // mesma regra que o Worker do assistente aplica, para o código citado
      // no chat bater com o que aparece na tela.
      // 'docId' guarda o ID real, necessário para escrever no Firestore.
      _entregas = snapshot.docs
          .map((doc) => {
                'id': codigoEntrega(doc.id),
                ...doc.data(),
                'docId': doc.id,
              })
          .toList();
      debugPrint("DEBUG: Carregadas ${_entregas.length} entregas para a empresa $empresaId.");

      if (!_descartado) notifyListeners();
    } catch (e) {
      _erro = e.toString();
      debugPrint("ERRO em carregarEntregas: $e");
    }
  }

  Future<void> carregarMotoristas() async {
    try {
      if (empresaId == null) return;
      // Uma consulta só, filtrando o tipo em memória. O cadastro por
      // convite (auth_service) grava apenas 'tipoUsuario', enquanto
      // cadastrarNovoMotorista grava 'tipo' e 'tipoUsuario' — filtrar por
      // 'tipo' no Firestore escondia da lista todo motorista convidado,
      // e o admin não conseguia atribuir entregas a ele.
      final snapshot = await _firestore
          .collection('usuarios')
          .where('empresaId', isEqualTo: empresaId)
          .get();

      _motoristas = snapshot.docs
          .map((doc) => {'id': doc.id, ...doc.data()})
          .where((u) =>
              (u['tipoUsuario'] ?? u['tipo'] ?? '').toString().toUpperCase() ==
              'MOTORISTA')
          .toList();
      if (!_descartado) notifyListeners();
    } catch (e) {
      _erro = e.toString();
    }
  }

  Future<void> carregarClientes() async {
    try {
      if (empresaId == null) return;
      // Mesmo motivo de carregarMotoristas: 'tipo' só existe em parte dos
      // cadastros, então o filtro é feito em memória sobre os dois campos.
      final snapshot = await _firestore
          .collection('usuarios')
          .where('empresaId', isEqualTo: empresaId)
          .get();

      _clientes = snapshot.docs
          .map((doc) => {'id': doc.id, ...doc.data()})
          .where((u) =>
              (u['tipoUsuario'] ?? u['tipo'] ?? '').toString().toUpperCase() ==
              'CLIENTE')
          .toList();
      if (!_descartado) notifyListeners();
    } catch (e) {
      _erro = e.toString();
    }
  }

  Future<void> carregarRotas() async {
    try {
      if (empresaId == null) return;
      final snapshot = await _firestore
          .collection('rotas')
          .where('empresaId', isEqualTo: empresaId)
          .get();

      _rotas = snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
      if (!_descartado) notifyListeners();
    } catch (e) {
      _erro = e.toString();
    }
  }

  // --- MÉTODO DE CADASTRO DE ENTREGA COM SINCRONIZAÇÃO AUTOMÁTICA DE CLIENTE ---
  Future<bool> cadastrarEntregaESincronizarCliente({
    required String clienteNome,
    required String clienteEmail,
    required String clienteTelefone,
    required String endereco,
    required String regiao,
    String? motoristaId,
    String? dataAgendada,
  }) async {
    try {
      if (empresaId == null) {
        debugPrint("ERRO: empresaId nulo ao cadastrar entrega.");
        return false;
      }

      // 1. Gerar chave única para o documento do cliente na coleção 'usuarios'
      final clienteIdKey = clienteEmail.trim().isNotEmpty
          ? clienteEmail.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')
          : clienteNome.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');

      final clienteRef = _firestore.collection('usuarios').doc(clienteIdKey);
      final clienteSnapshot = await clienteRef.get();

      // 2. Cria ou atualiza o cliente na coleção 'usuarios'
      if (!clienteSnapshot.exists) {
        final novoClienteData = {
          'id': clienteIdKey,
          'empresaId': empresaId,
          'nome': clienteNome,
          'email': clienteEmail,
          'telefone': clienteTelefone,
          'enderecoPrincipal': endereco,
          'tipo': 'CLIENTE',
          'tipoUsuario': 'CLIENTE',
          'criadoEm': FieldValue.serverTimestamp(),
        };

        await clienteRef.set(novoClienteData);

        // Atualiza a lista local em memória
        _clientes.add({
          'id': clienteIdKey,
          ...novoClienteData,
        });
      } else {
        // Atualiza os dados de contato do cliente existente
        await clienteRef.update({
          'enderecoPrincipal': endereco,
          if (clienteTelefone.isNotEmpty) 'telefone': clienteTelefone,
        });
      }

      // 3. Cadastra a entrega vinculada ao cliente
      //
      // Nome do motorista além do ID: o assistente de IA e a lista do admin
      // exibem o nome, e buscá-lo em 'usuarios' a cada leitura sairia caro.
      String motoristaNome = '';
      if (motoristaId != null && motoristaId.isNotEmpty) {
        final m = _motoristas.firstWhere(
          (x) => x['id'] == motoristaId,
          orElse: () => <String, dynamic>{},
        );
        motoristaNome = (m['nome'] ?? '').toString();
      }

      final novaEntregaData = {
        'empresaId': empresaId,
        'cliente': clienteNome,
        'emailCliente': clienteEmail,
        'clienteId': clienteIdKey,
        'telefoneCliente': clienteTelefone,
        'endereco': endereco,
        'regiao': regiao,
        'status': 'Pendente',
        'motorista': motoristaNome,
        'motoristaId': motoristaId ?? '',
        'data': dataAgendada ?? '',
        'criadoEm': FieldValue.serverTimestamp(),
      };

      final docRef = await _firestore.collection('entregas').add(novaEntregaData);

      // O código só pode ser gerado depois que o Firestore atribui o ID.
      final codigo = codigoEntrega(docRef.id);
      await docRef.update({'id': codigo});

      // Adiciona na lista local de entregas
      _entregas.add({
        ...novaEntregaData,
        'id': codigo,
        'docId': docRef.id,
      });

      if (!_descartado) notifyListeners();
      debugPrint("Entrega cadastrada e cliente sincronizado com sucesso!");
      return true;
    } catch (e) {
      _erro = e.toString();
      debugPrint("ERRO ao cadastrar entrega e sincronizar cliente: $e");
      if (!_descartado) notifyListeners();
      return false;
    }
  }

  // --- CARREGAR PERFIL E DADOS DA EMPRESA ---
  Future<void> carregarPerfilEmpresa(String idEmpresa) async {
    try {
      DocumentSnapshot doc = await _firestore.collection('empresas').doc(idEmpresa).get();
      if (doc.exists) {
        _dadosEmpresa = doc.data() as Map<String, dynamic>? ?? {};
        if (!_descartado) notifyListeners();
      }
    } catch (e) {
      debugPrint("ERRO ao carregar perfil da empresa: $e");
    }
  }

  // --- ATUALIZAR E SALVAR PERFIL E DADOS DA EMPRESA ---
  Future<void> atualizarPerfilEmpresa({
    required String empresaId,
    required Map<String, dynamic> novosDados,
  }) async {
    try {
      if (empresaId.isEmpty) return;

      await _firestore.collection('empresas').doc(empresaId).set(novosDados, SetOptions(merge: true));

      _dadosEmpresa = novosDados;
      if (!_descartado) notifyListeners();
    } catch (e) {
      _erro = e.toString();
      debugPrint("ERRO ao atualizar perfil da empresa: $e");
      rethrow;
    }
  }

  // --- MÉTODOS DE FILTRAGEM REQUISITADOS PELAS TELAS ---
  List<Map<String, dynamic>> filtrarPorRegiao(String regiao) {
    if (regiao.toLowerCase() == "todas") return _entregas;
    return _entregas.where((e) {
      final regItem = (e['regiao'] ?? '').toString().toLowerCase();
      return regItem.contains(regiao.toLowerCase());
    }).toList();
  }

  List<Map<String, dynamic>> filtrarPorCliente(String nomeCliente) {
    if (nomeCliente.isEmpty) return _entregas;
    return _entregas.where((e) {
      final cliente = (e['cliente'] ?? '').toString().toLowerCase();
      return cliente.contains(nomeCliente.toLowerCase());
    }).toList();
  }

  // --- MÉTODO DE CADASTRO DE MOTORISTA COM INSTÂNCIA SECUNDÁRIA ---
  Future<bool> cadastrarNovoMotorista({
    required String nome,
    required String email,
    required String regiao,
  }) async {
    try {
      const senhaProvisoria = "SmartLog@2026";

      FirebaseApp appSecundario = await Firebase.initializeApp(
        name: 'RegistroMotorista',
        options: Firebase.app().options,
      );

      FirebaseAuth authSecundario = FirebaseAuth.instanceFor(app: appSecundario);

      UserCredential userCredential = await authSecundario.createUserWithEmailAndPassword(
        email: email,
        password: senhaProvisoria,
      );

      final uidMotorista = userCredential.user?.uid;
      if (uidMotorista == null) throw Exception("Erro ao gerar ID de autenticação.");

      await userCredential.user?.sendEmailVerification();
      await appSecundario.delete();

      final novoMotoristaData = {
        'nome': nome,
        'email': email,
        'regiaoDesignada': regiao,
        'tipo': 'MOTORISTA',
        'tipoUsuario': 'MOTORISTA',
        'status': 'Ativo',
        if (empresaId != null) 'empresaId': empresaId,
        'criadoEm': FieldValue.serverTimestamp(),
      };

      await _firestore.collection('usuarios').doc(uidMotorista).set(novoMotoristaData);

      _motoristas.add({
        'id': uidMotorista,
        ...novoMotoristaData,
      });

      if (!_descartado) notifyListeners();
      return true;
    } catch (e) {
      _erro = e.toString();
      if (!_descartado) notifyListeners();
      return false;
    }
  }

  // --- MÉTODO PARA GERAR ROTA AUTOMATICAMENTE COM LOGS DE DIAGNÓSTICO ---
  Future<bool> gerarRotaParaMotorista({
    required String motoristaId,
    required String motoristaNome,
    required String regiao,
    required String nomeRota,
  }) async {
    try {
      debugPrint("--- INÍCIO GERAR ROTA ---");
      debugPrint("EmpresaId atual: $empresaId");
      debugPrint("Região desejada: '$regiao'");

      if (empresaId == null) {
        debugPrint("ERRO: empresaId está nulo.");
        return false;
      }

      final snapshot = await _firestore
          .collection('entregas')
          .where('empresaId', isEqualTo: empresaId)
          .get();

      final entregasFiltradas = snapshot.docs.where((doc) {
        final data = doc.data();
        final statusDoc = (data['status'] ?? '').toString().trim().toLowerCase();
        final regiaoDoc = (data['regiao'] ?? '').toString().trim().toLowerCase();

        final bool ehPendente = statusDoc == 'pendente';
        final bool mesmaRegiao = regiaoDoc == regiao.trim().toLowerCase();

        return ehPendente && mesmaRegiao;
      }).toList();

      if (entregasFiltradas.isEmpty) return false;

      final paradas = entregasFiltradas.take(5).toList();

      List<Map<String, dynamic>> listaEnderecos = paradas.map((doc) {
        final data = doc.data();
        return {
          'entregaId': doc.id,
          'cliente': data['cliente'] ?? 'Cliente',
          'endereco': data['endereco'] ?? '',
        };
      }).toList();

      final novaRotaData = {
        'empresaId': empresaId,
        'motoristaId': motoristaId,
        'motoristaNome': motoristaNome,
        'nome': nomeRota,
        'regiao': regiao,
        'status': 'Pendente',
        'totalEnderecos': listaEnderecos.length,
        'enderecos': listaEnderecos,
        'criadoEm': FieldValue.serverTimestamp(),
      };

      await _firestore.collection('rotas').add(novaRotaData);

      // Carimba a atribuição nas próprias entregas. A coleção 'rotas' não é
      // lida pelo painel do motorista nem pelo assistente de IA: sem estes
      // campos, o motorista abre o app numa rota vazia e o assistente
      // responde que não há nada atribuído a ele.
      final lote = _firestore.batch();
      for (var i = 0; i < paradas.length; i++) {
        lote.update(paradas[i].reference, {
          'motoristaId': motoristaId,
          'motorista': motoristaNome,
          'ordemEntrega': i + 1,
        });
      }
      await lote.commit();

      await carregarRotas();
      await carregarEntregas();

      debugPrint("Rota gerada com sucesso!");
      return true;
    } catch (e) {
      _erro = e.toString();
      debugPrint("EXCEÇÃO em gerarRotaParaMotorista: $e");
      notifyListeners();
      return false;
    }
  }

  // --- MÉTODOS DE AÇÕES DO MOTORISTA ---
  /// Avança o status da entrega a partir da leitura do QR Code.
  ///
  /// Persiste no Firestore, não só na lista em memória: antes o bip do
  /// motorista sumia ao fechar o app, e o admin (e o assistente de IA)
  /// continuavam vendo a entrega como Pendente para sempre.
  Future<String?> registrarBipQRCode({
    required String entregaId,
    String? nomeRecebedor,
  }) async {
    try {
      if (empresaId == null) return "Empresa não identificada.";

      final index = _entregas.indexWhere((e) => e['id'] == entregaId);
      if (index == -1) return "Entrega não encontrada.";

      final entrega = _entregas[index];

      // A entrega precisa ser da empresa do usuário logado. Sem esta
      // checagem, um motorista dava baixa em entrega de outra empresa só
      // sabendo o código — e as regras do Firestore recusariam a escrita.
      if (entrega['empresaId'] != empresaId) return "Entrega não encontrada.";

      final docId = (entrega['docId'] ?? '').toString();
      if (docId.isEmpty) return "Entrega sem referência no banco de dados.";

      final statusAtual = (entrega['status'] ?? 'Pendente').toString();
      final Map<String, dynamic> alteracoes = {};
      final String mensagem;

      if (statusAtual == 'Pendente') {
        alteracoes['status'] = 'Em Rota';
        alteracoes['saiuParaEntregaEm'] = FieldValue.serverTimestamp();
        mensagem = "Status alterado para: Em Rota";
      } else if (statusAtual == 'Em Rota' || statusAtual == 'A Caminho') {
        alteracoes['status'] = 'Entregue';
        alteracoes['entregueEm'] = FieldValue.serverTimestamp();
        if (nomeRecebedor != null && nomeRecebedor.isNotEmpty) {
          alteracoes['recebedor'] = nomeRecebedor;
        }
        mensagem = "Entrega concluída com sucesso!";
      } else {
        return "Esta entrega já foi finalizada.";
      }

      await _firestore.collection('entregas').doc(docId).update(alteracoes);

      // Espelha localmente só depois de o Firestore confirmar. O
      // serverTimestamp não tem valor no cliente, por isso não é copiado.
      alteracoes.remove('saiuParaEntregaEm');
      alteracoes.remove('entregueEm');
      _entregas[index] = {...entrega, ...alteracoes};

      if (!_descartado) notifyListeners();
      return mensagem;
    } catch (e) {
      debugPrint("ERRO em registrarBipQRCode: $e");
      return "Erro ao processar o QR Code.";
    }
  }
}