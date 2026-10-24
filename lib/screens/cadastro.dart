import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/auth_controller.dart';
import '../theme/app_theme.dart';

class CadastroScreen extends StatefulWidget {
  const CadastroScreen({super.key});

  @override
  State<CadastroScreen> createState() => _CadastroScreenState();
}

class _CadastroScreenState extends State<CadastroScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nomeController = TextEditingController();
  final _emailController = TextEditingController();
  final _senhaController = TextEditingController();

  // Perfil padrão selecionado
  String _perfilSelecionado = 'Administrador';

  @override
  void dispose() {
    _nomeController.dispose();
    _emailController.dispose();
    _senhaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authController = Provider.of<AuthController>(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Criar conta')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 560),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.border),
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Comece no SmartLog',
                      style:
                          TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Crie seu acesso e escolha o perfil da sua operação.',
                      style: TextStyle(color: AppTheme.textMuted, height: 1.4),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),

                    // Campo Nome
                    TextFormField(
                      controller: _nomeController,
                      decoration: const InputDecoration(
                        labelText: 'Nome Completo',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person),
                      ),
                      validator: (value) =>
                          value!.isEmpty ? 'Insira seu nome' : null,
                    ),
                    const SizedBox(height: 16),

                    // Campo E-mail
                    TextFormField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'E-mail',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.email),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) =>
                          value!.isEmpty ? 'Insira seu e-mail' : null,
                    ),
                    const SizedBox(height: 16),

                    // Campo Senha
                    TextFormField(
                      controller: _senhaController,
                      decoration: const InputDecoration(
                        labelText: 'Senha',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.lock),
                      ),
                      obscureText: true,
                      validator: (value) => value!.length < 6
                          ? 'A senha deve ter pelo menos 6 caracteres'
                          : null,
                    ),
                    const SizedBox(height: 16),

                    // Seleção do Tipo de Usuário (Perfil)
                    DropdownButtonFormField<String>(
                      initialValue: _perfilSelecionado,
                      decoration: const InputDecoration(
                        labelText: 'Tipo de Usuário',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.assignment_ind),
                      ),
                      items: const [
                        DropdownMenuItem(
                            value: 'Administrador',
                            child: Text('Administrador')),
                        DropdownMenuItem(
                            value: 'Motorista', child: Text('Motorista')),
                        DropdownMenuItem(
                            value: 'Cliente', child: Text('Cliente')),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _perfilSelecionado = value!;
                        });
                      },
                    ),
                    const SizedBox(height: 24),

                    // Botão de Cadastrar
                    ElevatedButton(
                      onPressed: authController.carregando // <-- Ajustado aqui
                          ? null
                          : () async {
                              if (_formKey.currentState!.validate()) {
                                final messenger = ScaffoldMessenger.of(context);
                                final navigator = Navigator.of(context);
                                bool sucesso =
                                    await authController.registrarUsuario(
                                  nome: _nomeController.text.trim(),
                                  email: _emailController.text.trim(),
                                  senha: _senhaController.text.trim(),
                                  tipo: _perfilSelecionado,
                                );

                                if (sucesso && mounted) {
                                  messenger.showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'Usuário cadastrado com sucesso!')),
                                  );
                                  navigator.pop();
                                } else if (mounted) {
                                  messenger.showSnackBar(
                                    SnackBar(
                                        content: Text(authController
                                                .erroMensagem ??
                                            'Erro ao cadastrar')), // <-- Ajustado aqui
                                  );
                                }
                              }
                            },
                      style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16)),
                      child: authController.carregando // <-- Ajustado aqui
                          ? const SizedBox.square(
                              dimension: 22,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2.4),
                            )
                          : const Text('Cadastrar',
                              style: TextStyle(fontSize: 16)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
