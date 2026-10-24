import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:smartlife/services/delivery_experience_service.dart';
import 'package:smartlife/services/api_service.dart';

void main() {
  test(
      'Flutter -> real HTTP API -> administrator and public tracking share persisted receipt and occurrence',
      () async {
    final driver = DeliveryExperienceService(
        tokenProvider: () async => 'integration-driver');
    final admin = DeliveryExperienceService(
        tokenProvider: () async => 'integration-admin');
    final client = DeliveryExperienceService(
        tokenProvider: () async => 'integration-client');
    final occurrence = await driver.report('delivery-e2e', {
      'requestId': deliveryRequestId(),
      'tipo': 'AVARIA',
      'descricao': 'Embalagem externa avariada. Itens conferidos pelo cliente.',
      'mensagemCliente': 'A equipe está verificando a embalagem.'
    });
    final rows = await admin.occurrences('delivery-e2e') as List;
    expect(rows.any((row) => row['docId'] == occurrence['docId']), true);
    const photo =
        'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==';
    await driver.confirm('delivery-e2e', {
      'requestId': deliveryRequestId(),
      'recebedor': 'Maria Teste',
      'fotos': [photo],
      'assinatura': photo,
      'latitude': -23.55,
      'longitude': -46.63,
      'precisao': 10,
      'volumesRecebidos': 2
    });
    expect(
        (await admin.delivery('delivery-e2e'))['comprovanteDisponivel'], true);
    expect((await client.receipt('delivery-e2e'))['recebedor'], 'Maria Teste');
    final share = await admin.share('delivery-e2e');
    final token = share['caminho'].toString().split('/').last;
    final response =
        await http.get(Uri.parse('${ApiService.baseUrl}/rastreamento/$token'));
    expect(response.statusCode, 200);
    final public = jsonDecode(response.body) as Map;
    expect(public['status'], 'ENTREGUE');
    expect(public['comprovante']['recebedor'], 'Maria Teste');
    expect(public.containsKey('empresaId'), false);
    expect(public.containsKey('latitude'), false);
  }, skip: !const bool.fromEnvironment('SMARTLOG_INTEGRATION'));
}
