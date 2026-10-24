import 'dart:convert';
import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'api_service.dart';

String deliveryRequestId() =>
    base64UrlEncode(List<int>.generate(24, (_) => Random.secure().nextInt(256)))
        .replaceAll('=', '')
        .replaceAll('_', '-');

class DeliveryExperienceService {
  final http.Client? client;
  final Future<String?> Function()? tokenProvider;
  DeliveryExperienceService({this.client, this.tokenProvider});

  Future<dynamic> request(String method, String path,
      [Map<String, dynamic>? body]) async {
    final token = tokenProvider != null
        ? await tokenProvider!()
        : await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null || token.isEmpty) {
      throw Exception('Sessão expirada. Entre novamente.');
    }
    final transport = client ?? http.Client();
    try {
      final request =
          http.Request(method, Uri.parse('${ApiService.baseUrl}$path'))
            ..headers.addAll({
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json'
            });
      if (body != null) request.body = jsonEncode(body);
      final response = await transport
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 35));
      if (response.statusCode == 204) return null;
      final dynamic data = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(data is Map
            ? data['message'] ?? 'A central não confirmou a operação.'
            : 'A central não confirmou a operação.');
      }
      return data;
    } finally {
      if (client == null) transport.close();
    }
  }

  String _delivery(String id) => '/entregas/${Uri.encodeComponent(id)}';
  Future<dynamic> delivery(String id) => request('GET', _delivery(id));
  Future<dynamic> receipt(String id) =>
      request('GET', '${_delivery(id)}/comprovante');
  Future<dynamic> occurrences(String id) =>
      request('GET', '${_delivery(id)}/ocorrencias');
  Future<dynamic> occurrence(String id, String oid) => request(
      'GET', '${_delivery(id)}/ocorrencias/${Uri.encodeComponent(oid)}');
  Future<dynamic> confirm(String id, Map<String, dynamic> body) =>
      request('POST', '${_delivery(id)}/comprovante', body);
  Future<dynamic> report(String id, Map<String, dynamic> body) =>
      request('POST', '${_delivery(id)}/ocorrencias', body);
  Future<dynamic> share(String id) =>
      request('POST', '${_delivery(id)}/rastreamento', {});
}
