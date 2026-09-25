// lib/controllers/chat_controller.dart
//
// Estado da conversa do Assistente Logístico.
// Não conhece widgets e não fala com o Firestore: delega a rede ao ChatService.

import 'package:flutter/foundation.dart';

import '../models/chat_conversa.dart';
import '../models/chat_mensagem.dart';
import '../models/chat_resposta.dart';
import '../services/chat_service.dart';

class ChatController extends ChangeNotifier {
  final ChatService _service;
  final String uid;
  final String perfil;

  late final Conversa _conversa;

  bool _enviando = false;
  bool _descartado = false;

  /// Monta o contexto operacional no momento da pergunta. Fica como callback
  /// (e não como Map fixo) para que cada pergunta enxergue o estado atual.
  final Map<String, dynamic> Function()? contextoBuilder;

  ChatController({
    required this.uid,
    required this.perfil,
    ChatService? service,
    this.contextoBuilder,
  }) : _service = service ?? ChatService() {
    _conversa = Conversa(perfil: perfil);
  }

  List<Mensagem> get mensagens => _conversa.mensagens;
  bool get enviando => _enviando;
  bool get conversaVazia => _conversa.vazia;

  /// Sugestões fixas por perfil — cada uma é uma pergunta que a Cloud Function
  /// sabe responder com os dados daquele perfil.
  List<String> get sugestoesRapidas {
    switch (perfil.toUpperCase()) {
      case 'ADMINISTRADOR':
      case 'ADMIN':
        return const [
          'Resumir operação',
          'Existem atrasos?',
          'Motorista mais carregado',
          'Insights',
        ];
      case 'MOTORISTA':
        return const [
          'Minha próxima entrega',
          'Quantas faltam?',
          'Minha rota',
        ];
      case 'CLIENTE':
        return const [
          'Onde está meu pedido?',
          'Status da entrega',
        ];
      default:
        return const [];
    }
  }

  Future<void> enviar(String texto) async {
    final String pergunta = texto.trim();
    if (pergunta.isEmpty || _enviando) return;

    _conversa.adicionar(Mensagem.doUsuario(pergunta));
    _enviando = true;
    _notificar();

    // Histórico capturado ANTES da resposta, já sem a pergunta recém-adicionada
    final List<Map<String, String>> historico =
    _conversa.historicoRecente().where((m) => m['texto'] != pergunta).toList();

    // Chamada corrigida sem o parâmetro 'contexto' incompatível com o ChatService
    final Resposta resposta = await _service.perguntar(
      uid: uid,
      perfil: perfil,
      pergunta: pergunta,
      historico: historico,
    );

    _conversa.adicionar(
      Mensagem.doAssistente(resposta.texto, falhou: !resposta.sucesso),
    );

    _enviando = false;
    _notificar();
  }

  void limparConversa() {
    if (_enviando) return;
    _conversa.limpar();
    _notificar();
  }

  void _notificar() {
    if (_descartado) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _descartado = true;
    super.dispose();
  }
}