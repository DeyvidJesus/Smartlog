import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartlife/services/chat_service.dart';
import 'support/chat_auth.dart';

void main() {
  test(
      'chat uses the shared authenticated API and preserves Portuguese without trusting caller identity',
      () async {
    final service = ChatService(
        auth: ChatTestAuth('verified-token'),
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/v1/chat');
          expect(request.headers['Authorization'], 'Bearer verified-token');
          expect(jsonDecode(request.body), {
            'pergunta': 'Há avarias na operação?',
            'historico': [
              {'autor': 'usuario', 'texto': 'E minha entrega?'}
            ],
          });
          return http.Response.bytes(
              utf8.encode(jsonEncode({
                'resposta': 'Atenção: há uma ocorrência de avaria.',
                'provedor': 'gemini',
              })),
              200);
        }));
    final answer = await service.perguntar(
        uid: 'spoofed-user',
        perfil: 'ADMIN',
        pergunta: 'Há avarias na operação?',
        historico: [
          {'autor': 'usuario', 'texto': 'E minha entrega?'}
        ]);
    expect(answer.sucesso, true);
    expect(answer.texto, 'Atenção: há uma ocorrência de avaria.');
  });

  test('chat does not send anonymous requests or treat HTML as an AI answer',
      () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response('<app-root></app-root>', 200);
    });
    final anonymous =
        await ChatService(auth: ChatTestAuth(null), client: client)
            .perguntar(uid: 'x', perfil: 'CLIENTE', pergunta: 'Status?');
    expect(anonymous.sucesso, false);
    expect(calls, 0);
    final missingApi =
        await ChatService(auth: ChatTestAuth('token'), client: client)
            .perguntar(uid: 'x', perfil: 'CLIENTE', pergunta: 'Status?');
    expect(missingApi.sucesso, false);
    expect(missingApi.codigoErro, 'formato-invalido');
  });

  test(
      'chat reports provider quota errors from the API without inventing a response',
      () async {
    final client = MockClient((_) async => http.Response.bytes(
        utf8.encode(jsonEncode({
          'message': 'Quota do assistente atingida. Tente mais tarde.',
        })),
        429));
    final answer =
        await ChatService(auth: ChatTestAuth('token'), client: client)
            .perguntar(uid: 'x', perfil: 'MOTORISTA', pergunta: 'Status?');
    expect(answer.sucesso, false);
    expect(answer.codigoErro, 'http-429');
    expect(answer.texto, contains('Quota'));
  });
}
