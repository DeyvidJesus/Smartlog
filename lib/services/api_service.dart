// API compartilhada por Flutter, Control Tower e assistente.
// Credenciais do provedor de IA nunca são incluídas no aplicativo.
import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../models/entrega.dart';

class ApiService {
  static const String baseUrl = String.fromEnvironment('API_BASE_URL',
      defaultValue: 'https://smartlog-next-2026.netlify.app/api/v1');
  static Future<Map<String, dynamic>> atualizarStatusNoServidor(
      String id, String status,
      {String? recebedor, String? observacaoEntrega, http.Client? client, Future<String?> Function()? tokenProvider}) async {
    final token = tokenProvider != null
        ? await tokenProvider()
        : await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null || token.isEmpty) {
      throw Exception('Sessão expirada. Entre novamente.');
    }
    const statuses = {
      'Pendente': 'PENDENTE',
      'Em Rota': 'EM_ROTA',
      'A Caminho': 'EM_ROTA',
      'Entregue': 'ENTREGUE',
      'Cancelada': 'CANCELADA',
      'Atrasada': 'ATRASADA'
    };
    final transport = client ?? http.Client();
    try {
      final response = await transport
          .patch(
              Uri.parse('$baseUrl/entregas/${Uri.encodeComponent(id)}/status'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token'
              },
              body: jsonEncode({'status': statuses[status] ?? status, if (recebedor != null) 'recebedor': recebedor, if (observacaoEntrega != null) 'observacaoEntrega': observacaoEntrega}))
          .timeout(const Duration(seconds: 15));
      final dynamic data = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode != 200 || data is! Map<String, dynamic>) {
        throw Exception(data is Map
            ? data['message'] ?? 'A alteração não foi confirmada no servidor.'
            : 'A alteração não foi confirmada.');
      }
      return data;
    } on TimeoutException {
      throw Exception(
          'O servidor não confirmou a alteração a tempo. Consulte o status antes de repetir.');
    } on http.ClientException {
      throw Exception(
          'Sem conexão com a central. A alteração não foi confirmada.');
    } on FormatException {
      throw Exception(
          'A central retornou uma resposta inesperada. A alteração não foi confirmada.');
    } finally {
      if (client == null) transport.close();
    }
  }

  static Future<bool> cadastrarEntregaNaApi(Map<String, dynamic> dados) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null) { throw Exception('Autenticação necessária.'); }
    final response = await http
        .post(Uri.parse('$baseUrl/entregas'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token'
            },
            body: jsonEncode(dados))
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 201) {
      throw Exception('A entrega não foi confirmada pela API.');
    }
    return true;
  }

  Future<List<Entrega>> buscarEntregas() async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null) { throw Exception('Autenticação necessária.'); }
    final response = await http.get(Uri.parse('$baseUrl/entregas'), headers: {
      'Authorization': 'Bearer $token'
    }).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('Não foi possível consultar as entregas.');
    }
    final data =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    return (data['data'] as List)
        .map((e) => Entrega.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
