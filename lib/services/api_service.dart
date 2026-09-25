// lib/services/api_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../models/entrega.dart';

class ApiService {
  // Com o comando adb reverse ativo, o celular físico acessa seu PC via localhost
  static const String baseUrl = 'http://localhost:8080/api/v1';

  static Future<String?> _getToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      return await user.getIdToken();
    }
    return null;
  }

  // Novo método estático para cadastrar a entrega na API do Spring Boot
  static Future<bool> cadastrarEntregaNaApi(Map<String, dynamic> dadosEntrega) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final token = user != null ? await user.getIdToken() : null;
      final url = Uri.parse('$baseUrl/entregas');

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: json.encode(dadosEntrega),
      ).timeout(const Duration(seconds: 5));

      return response.statusCode == 200 || response.statusCode == 201;
    } on SocketException {
      throw Exception('Servidor Spring Boot inacessível na porta 8080.');
    } on http.ClientException {
      throw Exception('Falha de conexão com a API.');
    } catch (e) {
      print("Erro ao conectar com o Spring Boot: $e");
      return false;
    }
  }

  Future<List<Entrega>> buscarEntregas() async {
    try {
      final token = await _getToken();
      final url = Uri.parse('$baseUrl/entregas');

      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final List<dynamic> dados = jsonDecode(utf8.decode(response.bodyBytes));
        return dados.map((item) => Entrega.fromJson(item)).toList();
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw Exception('Autenticação necessária na API (HTTP ${response.statusCode}).');
      } else {
        throw Exception('Erro de resposta do servidor (HTTP ${response.statusCode}).');
      }
    } on SocketException {
      throw Exception('Servidor Spring Boot inacessível na porta 8080.');
    } on http.ClientException {
      throw Exception('Falha de conexão com a API.');
    } catch (e) {
      throw Exception(e.toString().replaceAll('Exception: ', ''));
    }
  }
}