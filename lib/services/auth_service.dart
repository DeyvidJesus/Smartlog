import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Stream para monitorar o estado da autenticação (logado ou não)
  Stream<User?> get usuarioStatus => _auth.authStateChanges();

  // Login com Email e Senha
  Future<UserCredential> loginComEmailESenha(String email, String senha) async {
    try {
      return await _auth.signInWithEmailAndPassword(email: email.trim().toLowerCase(), password: senha);
    } on FirebaseAuthException catch (e) {
      throw _tratarErroAuth(e);
    }
  }

  // Cadastro de Novo Usuário (Ajustado para a coleção unificada 'usuarios')
  Future<void> cadastrarUsuario({
    required String nome,
    required String email,
    required String senha,
    required String tipo,
    required String empresaId,
  }) async {
    try {
      // 1. Cria a credencial de acesso oficial no Firebase Authentication
      UserCredential cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim().toLowerCase(),
        password: senha,
      );

      // 2. Dispara o e-mail nativo de verificação
      await cred.user?.sendEmailVerification();

      // 3. Salva na coleção correta 'usuarios' para alinhar com o DashboardController (🔥 CORRIGIDO)
      await _db.collection('usuarios').doc(cred.user?.uid).set({
        'uid': cred.user?.uid,
        'nome': nome,
        'email': email.trim().toLowerCase(),
        'tipoUsuario': tipo.toUpperCase(), // 🔥 Padronizado para tipoUsuario
        'empresaId': (tipo.toUpperCase() == 'ADMINISTRADOR' || tipo.toUpperCase() == 'ADMIN') ? cred.user!.uid : empresaId,
        'statusAtivacao': 'PENDENTE',
        'dataCadastro': FieldValue.serverTimestamp(),
      });
    } on FirebaseAuthException catch (e) {
      throw _tratarErroAuth(e);
    }
  }

  // Buscar dados adicionais do usuário logado na coleção correta (🔥 CORRIGIDO)
  Future<DocumentSnapshot> buscarDadosUsuario(String uid) async {
    return await _db.collection('usuarios').doc(uid).get(); // 🔥 Mudado de 'users' para 'usuarios'
  }

  // Logout
  Future<void> deslogar() async {
    await _auth.signOut();
  }

  // Recuperação de Senha
  Future<void> resetarSenha(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      throw _tratarErroAuth(e);
    }
  }

  // Helper amigável para tratamento de erros em português
  String _tratarErroAuth(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'Nenhum usuário encontrado com este e-mail.';
      case 'wrong-password':
        return 'Senha incorreta. Tente novamente.';
      case 'email-already-in-use':
        return 'Este e-mail já está sendo utilizado.';
      case 'weak-password':
        return 'A senha digitada é muito fraca.';
      case 'invalid-email':
        return 'O formato do e-mail digitado é inválido.';
      default:
        return 'Ocorreu um erro inesperado: ${e.message}';
    }
  }
}
