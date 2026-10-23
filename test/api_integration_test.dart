import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartlife/services/api_service.dart';

void main() {
  test(
      'sends authenticated status to the exact delivery and returns the server result',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'PATCH');
      expect(request.url.path, '/api/v1/entregas/delivery-123/status');
      expect(request.headers['Authorization'], 'Bearer verified-test-token');
      expect(jsonDecode(request.body), {'status': 'ENTREGUE'});
      return http.Response(
          jsonEncode({'id': 'delivery-123', 'status': 'ENTREGUE'}), 200);
    });
    final result = await ApiService.atualizarStatusNoServidor(
        'delivery-123', 'Entregue',
        client: client, tokenProvider: () async => 'verified-test-token');
    expect(result['id'], 'delivery-123');
    expect(result['status'], 'ENTREGUE');
  });
  test('does not invent success when the API rejects the update', () async {
    final client = MockClient((_) async =>
        http.Response(jsonEncode({'message': 'Acesso não permitido'}), 403));
    expect(
        ApiService.atualizarStatusNoServidor('delivery-123', 'Entregue',
            client: client, tokenProvider: () async => 'token'),
        throwsException);
  });
  test('does not fall back to Firestore or a local delivery when offline',
      () async {
    final client =
        MockClient((_) async => throw http.ClientException('offline'));
    expect(
        ApiService.atualizarStatusNoServidor('delivery-123', 'Entregue',
            client: client, tokenProvider: () async => 'token'),
        throwsException);
  });
  test('does not send an unauthenticated mutation', () async {
    var called = false;
    final client = MockClient((_) async {
      called = true;
      return http.Response('{}', 200);
    });
    await expectLater(
        ApiService.atualizarStatusNoServidor('delivery-123', 'Entregue',
            client: client, tokenProvider: () async => null),
        throwsException);
    expect(called, false);
  });
}
