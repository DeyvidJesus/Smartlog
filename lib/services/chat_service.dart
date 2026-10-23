// Assistente compartilhado com o dashboard. Identidade validada pela API; chave de IA somente no servidor.
import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../models/chat_resposta.dart';

class ChatService {
  static const String baseUrl = String.fromEnvironment('CHAT_BASE_URL',
      defaultValue: String.fromEnvironment('API_BASE_URL',
          defaultValue: 'https://smartlog-next-2026.netlify.app/api/v1'));

  /// Endpoint do assistente — o nome da função exportada em functions/.
  static const String caminhoChat = '/chat';

  /// Mesmo teto que o backend aplica por requisição.
  static const Duration tempoLimite = Duration(seconds: 35);

  final http.Client _client;
  final FirebaseAuth _auth;

  ChatService({http.Client? client, FirebaseAuth? auth})
      : _client = client ?? http.Client(),
        _auth = auth ?? FirebaseAuth.instance;

  Future<Resposta> perguntar({
    // Mantidos para não alterar a chamada existente no ChatController.
    // Nenhum dos dois é enviado ao servidor: a identidade e o perfil passaram
    // a ser derivados do ID Token verificado e do Firestore, no Worker.
    required String uid,
    required String perfil,
    required String pergunta,
    List<Map<String, String>> historico = const [],
  }) async {
    try {
      // ── Autenticação: sem usuário logado, nem sai do app ──────────
      final User? usuario = _auth.currentUser;
      if (usuario == null) {
        return Resposta.falha(
          'Entre na sua conta para usar o assistente.',
          codigo: 'nao-autenticado',
        );
      }

      final String? idToken = await usuario.getIdToken();
      if (idToken == null || idToken.isEmpty) {
        return Resposta.falha(
          'Sua sessão expirou. Entre novamente para usar o assistente.',
          codigo: 'token-indisponivel',
        );
      }

      final Uri url = Uri.parse('$baseUrl$caminhoChat');

      final http.Response resposta = await _client
          .post(
            url,
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
              'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode({
              'pergunta': pergunta,
              'historico': historico,
            }),
          )
          .timeout(tempoLimite);

      // bodyBytes + utf8 é obrigatório: usar resposta.body corromperia
      // os acentos do português devolvido pelo assistente.
      final String corpo = utf8.decode(resposta.bodyBytes);

      Map<String, dynamic>? json;
      try {
        final dynamic decodificado = jsonDecode(corpo);
        if (decodificado is Map<String, dynamic>) json = decodificado;
      } catch (_) {
        json = null;
      }

      if (resposta.statusCode == 200) {
        if (json == null) {
          return Resposta.falha(
            'O assistente devolveu um formato inesperado.',
            codigo: 'formato-invalido',
          );
        }
        return Resposta.fromMap(json);
      }

      return Resposta.falha(
        _mensagemAmigavel(resposta.statusCode, json),
        codigo: 'http-${resposta.statusCode}',
      );
    } on TimeoutException {
      return Resposta.falha(
        'O assistente demorou demais para responder. Tente uma pergunta mais direta.',
        codigo: 'deadline-exceeded',
      );
    } on FirebaseAuthException {
      return Resposta.falha(
        'Sua sessão expirou. Entre novamente para usar o assistente.',
        codigo: 'auth',
      );
    } on http.ClientException {
      return Resposta.falha(
        'Não foi possível falar com o assistente agora. Verifique sua conexão e tente novamente.',
        codigo: 'conexao',
      );
    } catch (e) {
      return Resposta.falha(
        'Não foi possível falar com o assistente agora. Verifique sua conexão e tente novamente.',
        codigo: 'desconhecido',
      );
    }
  }

  String _mensagemAmigavel(int status, Map<String, dynamic>? json) {
    // Erros de validação (400) já vêm com texto preciso e acionável do Worker
    final String? doServidor = (json?['message'] ?? json?['erro'])?.toString();
    if ((status == 400 || status == 429 || status == 503) &&
        doServidor != null &&
        doServidor.isNotEmpty) {
      return doServidor;
    }

    switch (status) {
      case 400:
        return 'A pergunta enviada é inválida. Tente reformulá-la.';
      case 401:
        return 'Sua sessão expirou. Entre novamente para usar o assistente.';
      case 403:
        return 'Seu perfil não tem acesso ao assistente.';
      case 404:
        return 'O assistente ainda não foi publicado. Faça o deploy do Worker para ativá-lo.';
      case 405:
        return 'O assistente recusou o formato da requisição.';
      case 413:
        return 'A conversa ficou grande demais. Limpe o histórico e tente novamente.';
      case 429:
        return 'Limite de uso do assistente atingido. Tente novamente mais tarde.';
      case 503:
        return 'O assistente ainda precisa ser configurado no servidor.';
      case 502:
        return 'O assistente não conseguiu responder agora. Tente novamente.';
      default:
        return 'O assistente não conseguiu responder agora (HTTP $status).';
    }
  }
}
