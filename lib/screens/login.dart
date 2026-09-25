// lib/screens/login.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smartlife/screens/cadastro.dart';
import '../controllers/auth_controller.dart';
import 'dashboard_admin.dart';
import 'motorista.dart';
import 'cliente.dart';

class TelaLogin extends StatefulWidget {
  const TelaLogin({super.key});

  @override
  State<TelaLogin> createState() => _TelaLoginState();
}

class _TelaLoginState extends State<TelaLogin> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _senhaController = TextEditingController();
  bool _senhaOculta = true;

  @override
  void dispose() {
    _emailController.dispose();
    _senhaController.dispose();
    super.dispose();
  }

  void _executarLogin() async {
    if (!_formKey.currentState!.validate()) return;

    final authCtrl = context.read<AuthController>();

    // 🔥 BLINDAGEM OPERACIONAL: Força o e-mail a ficar limpo e minúsculo
    final emailTratado = _emailController.text.trim().toLowerCase();
    final senhaTratada = _senhaController.text.trim();

    String? tipoUsuario = await authCtrl.realizarLogin(
      emailTratado,
      senhaTratada,
    );

    if (tipoUsuario != null && mounted) {
      final tipoTratado = tipoUsuario.toUpperCase();

      if (tipoTratado == 'ADMINISTRADOR' || tipoTratado == 'ADMIN') {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const DashboardAdmin()),
        );
      } else if (tipoTratado == 'MOTORISTA') {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const DashboardMotorista()),
        );
      } else if (tipoTratado == 'CLIENTE') {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const DashboardCliente()),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Perfil de usuário não reconhecido. Contate o administrador.'), backgroundColor: Colors.orangeAccent),
        );
      }
    } else if (mounted) {
      // 🔥 EXIBIÇÃO DO ERRO REAL: Agora exibe a mensagem retornada pelo Firebase AuthService
      final msgErro = authCtrl.erroMensagem ?? 'Falha na autenticação. Verifique suas credenciais.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msgErro),
          backgroundColor: Colors.redAccent,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  void _recuperarSenha() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Digite seu e-mail no campo acima para recuperá-lo.'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    final authCtrl = context.read<AuthController>();

    bool enviado = await authCtrl.recuperarSenhaPorEmail(email);

    if (enviado && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('E-mail de recuperação enviado para $email! Verifique sua caixa de entrada.'),
          backgroundColor: Colors.green,
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(authCtrl.erroMensagem ?? 'Erro ao enviar e-mail de redefinição.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authController = context.watch<AuthController>();

    return Scaffold(
      backgroundColor: const Color(0xff0F172A),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.local_shipping, size: 80, color: Colors.blueAccent),
                const SizedBox(height: 16),
                const Text(
                  "SmartLog",
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Faça login para acessar sua rota ou painel",
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 32),

                // Campo de E-mail
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'E-mail',
                    labelStyle: TextStyle(color: Colors.grey),
                    prefixIcon: Icon(Icons.email, color: Colors.blueAccent),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.blueAccent)),
                  ),
                  validator: (value) => (value == null || !value.contains('@')) ? 'Insira um e-mail válido' : null,
                ),
                const SizedBox(height: 16),

                // Campo de Senha com o "Olhinho"
                TextFormField(
                  controller: _senhaController,
                  obscureText: _senhaOculta,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Senha',
                    labelStyle: const TextStyle(color: Colors.grey),
                    prefixIcon: const Icon(Icons.lock, color: Colors.blueAccent),
                    suffixIcon: IconButton(
                      icon: Icon(_senhaOculta ? Icons.visibility_off : Icons.visibility, color: Colors.grey),
                      onPressed: () => setState(() => _senhaOculta = !_senhaOculta),
                    ),
                    enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                    focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.blueAccent)),
                  ),
                  validator: (value) => (value == null || value.length < 6) ? 'A senha deve ter pelo menos 6 caracteres' : null,
                ),

                // Botão Esqueci Minha Senha
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _recuperarSenha,
                    child: const Text('Esqueci minha senha', style: TextStyle(color: Colors.blueAccent)),
                  ),
                ),
                const SizedBox(height: 24),

                // Botão de Login
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: authController.carregando ? null : _executarLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: authController.carregando
                        ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Entrar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 16),

                // Botão de Cadastro
                TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const CadastroScreen()),
                    );
                  },
                  child: const Text('Não tem uma conta? Cadastre-se', style: TextStyle(color: Colors.grey)),
                ),

                if (authController.erroMensagem != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    authController.erroMensagem!,
                    style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ]
              ],
            ),
          ),
        ),
      ),
    );
  }
}