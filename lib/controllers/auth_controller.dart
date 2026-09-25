// lib/controllers/auth_controller.dart
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthController extends ChangeNotifier {
  final AuthService _authService = AuthService();
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  bool _carregando = false;
  bool get carregando => _carregando;

  String? _erroMensagem;
  String? get erroMensagem => _erroMensagem;

  // Propriedade para guardar o ID da empresa do usuário logado na sessão
  String? _empresaIdLogada;
  String? get empresaIdLogada => _empresaIdLogada;

  // Nome cadastral do usuário logado
  String? _nomeUsuarioLogado;
  String? get nomeUsuarioLogado => _nomeUsuarioLogado;

  // Tipo do usuário logado (ADMINISTRADOR, MOTORISTA, CLIENTE)
  String? _tipoUsuarioLogado;
  String? get tipoUsuarioLogado => _tipoUsuarioLogado;

  void _setCarregando(bool valor) {
    _carregando = valor;
    notifyListeners();
  }

  // Realiza o fluxo de Login completo, resgatando o tipo e o empresaId do Firestore
  Future<String?> realizarLogin(String email, String senha) async {
    _setCarregando(true);
    _erroMensagem = null;

    try {
      UserCredential? creds = await _authService.loginComEmailESenha(email.trim(), senha);

      if (creds != null && creds.user != null) {
        var doc = await _authService.buscarDadosUsuario(creds.user!.uid);
        if (doc.exists && doc.data() != null) {
          Map<String, dynamic> dados = doc.data() as Map<String, dynamic>;

          // Captura e salva o ID da empresa e o nome
          _empresaIdLogada = dados['empresaId'];
          _nomeUsuarioLogado = dados['nome'];

          String tipo = (dados['tipoUsuario'] ?? dados['tipo'] ?? 'MOTORISTA').toString().toUpperCase();
          _tipoUsuarioLogado = tipo;

          _setCarregando(false);
          return tipo;
        }
      }

      _erroMensagem = "Usuário não encontrado ou dados inválidos.";
      _setCarregando(false);
      return null;
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'user-not-found':
          _erroMensagem = "Nenhum usuário encontrado com este e-mail.";
          break;
        case 'wrong-password':
          _erroMensagem = "Senha incorreta. Tente novamente.";
          break;
        case 'invalid-credential':
          _erroMensagem = "Credenciais inválidas. Verifique e-mail e senha.";
          break;
        case 'invalid-email':
          _erroMensagem = "O formato do e-mail é inválido.";
          break;
        default:
          _erroMensagem = "Erro de autenticação: ${e.message}";
          break;
      }
      _setCarregando(false);
      return null;
    } catch (e) {
      _erroMensagem = "Erro inesperado: $e";
      _setCarregando(false);
      return null;
    }
  }

  // Dispara o link oficial do Firebase para redefinição de senha
  Future<bool> recuperarSenhaPorEmail(String email) async {
    _setCarregando(true);
    _erroMensagem = null;

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: email.trim().toLowerCase(),
      );
      _setCarregando(false);
      return true;
    } catch (e) {
      _erroMensagem = "Erro ao enviar e-mail de recuperação: $e";
      _setCarregando(false);
      return false;
    }
  }

  // Realiza o cadastro do usuário e injeta o tenant/empresaId de forma automatizada
  Future<bool> registrarUsuario({
    required String nome,
    required String email,
    required String senha,
    required String tipo,
    String? nomeDaEmpresa,
  }) async {
    _setCarregando(true);
    _erroMensagem = null;

    try {
      String empresaIdVinculada;
      final bool ehAdminNovo = tipo.toUpperCase() == 'ADMINISTRADOR';

      if (ehAdminNovo) {
        empresaIdVinculada = _db.collection('empresas').doc().id;
      } else {
        if (_empresaIdLogada == null) {
          throw Exception("Ação não autorizada: Admin não está logado para vincular a empresa.");
        }
        empresaIdVinculada = _empresaIdLogada!;
      }

      await _authService.cadastrarUsuario(
        nome: nome,
        email: email,
        senha: senha,
        tipo: tipo,
        empresaId: empresaIdVinculada,
      );

      if (ehAdminNovo) {
        await _db.collection('empresas').doc(empresaIdVinculada).set({
          'id': empresaIdVinculada,
          'nomeFantasia': nomeDaEmpresa ?? "Nova Empresa Logística",
          'dataCriacao': FieldValue.serverTimestamp(),
        });
      }

      _setCarregando(false);
      return true;
    } catch (e) {
      _erroMensagem = e.toString();
      _setCarregando(false);
      return false;
    }
  }

  // Executa o logout limpando o estado da sessão
  Future<void> realizarLogout() async {
    await _authService.deslogar();
    _empresaIdLogada = null;
    _nomeUsuarioLogado = null;
    _tipoUsuarioLogado = null;
    notifyListeners();
  }
}