import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartlife/services/delivery_experience_service.dart';

void main() {
  test(
      'proof sends images signature GPS quantity and stable retry identifier through authenticated API',
      () async {
    final payload = {
      'requestId': deliveryRequestId(),
      'recebedor': 'Maria',
      'fotos': ['photo-data'],
      'assinatura': 'signature-data',
      'latitude': -23.5,
      'longitude': -46.6,
      'precisao': 12,
      'volumesRecebidos': 2
    };
    var requests = 0;
    final service = DeliveryExperienceService(
        tokenProvider: () async => 'test-driver-token',
        client: MockClient((request) async {
          requests++;
          expect(request.method, 'POST');
          expect(request.url.path, '/api/v1/entregas/delivery-id/comprovante');
          expect(request.headers['Authorization'], 'Bearer test-driver-token');
          expect(jsonDecode(request.body), payload);
          return http.Response(
              jsonEncode({
                'id': 'delivery-id',
                'status': 'ENTREGUE',
                'comprovanteDisponivel': true
              }),
              200);
        }));
    final result = await service.confirm('delivery-id', payload);
    expect(result['comprovanteDisponivel'], true);
    await service.confirm('delivery-id', payload);
    expect(requests, 2);
  });
  test(
      'partial occurrence is sent to API and not converted into a delivered status',
      () async {
    final payload = {
      'requestId': deliveryRequestId(),
      'tipo': 'ENTREGA_PARCIAL',
      'descricao': 'Faltam dois volumes',
      'volumesRecebidos': 2
    };
    final service = DeliveryExperienceService(
        tokenProvider: () async => 'token',
        client: MockClient((request) async {
          expect(request.url.path, '/api/v1/entregas/id/ocorrencias');
          final body = jsonDecode(request.body) as Map;
          expect(body['tipo'], 'ENTREGA_PARCIAL');
          expect(body.containsKey('status'), false);
          return http.Response(
              jsonEncode({'docId': 'occurrence-id', 'status': 'ABERTA'}), 201);
        }));
    expect((await service.report('id', payload))['status'], 'ABERTA');
  });
  test(
      'server rejections and offline errors propagate without fabricated confirmation',
      () async {
    for (final transport in [
      MockClient((_) async => http.Response(
          jsonEncode({'message': 'Entrega fora do seu escopo.'}), 403)),
      MockClient((_) async => throw http.ClientException('offline'))
    ]) {
      final service = DeliveryExperienceService(
          client: transport, tokenProvider: () async => 'token');
      await expectLater(service.confirm('id', {}), throwsException);
    }
  });
  test('missing authentication blocks proof occurrence and tracking writes',
      () async {
    var called = false;
    final service = DeliveryExperienceService(
        tokenProvider: () async => null,
        client: MockClient((_) async {
          called = true;
          return http.Response('{}', 200);
        }));
    await expectLater(service.confirm('id', {}), throwsException);
    await expectLater(service.report('id', {}), throwsException);
    await expectLater(service.share('id'), throwsException);
    expect(called, false);
  });
}
