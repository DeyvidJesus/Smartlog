import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smartlife/screens/cadastro.dart';

import '../controllers/auth_controller.dart';
import '../theme/app_theme.dart';
import 'cliente.dart';
import 'dashboard_admin.dart';
import 'motorista.dart';

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

  Future<void> _executarLogin() async {
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    final authCtrl = context.read<AuthController>();
    final tipoUsuario = await authCtrl.realizarLogin(
      _emailController.text.trim().toLowerCase(),
      _senhaController.text.trim(),
    );

    if (!mounted) return;

    if (tipoUsuario != null) {
      final tipoTratado = tipoUsuario.toUpperCase();
      Widget? destino;
      if (tipoTratado == 'ADMINISTRADOR' || tipoTratado == 'ADMIN') {
        destino = const DashboardAdmin();
      } else if (tipoTratado == 'MOTORISTA') {
        destino = const DashboardMotorista();
      } else if (tipoTratado == 'CLIENTE') {
        destino = const DashboardCliente();
      }

      if (destino != null) {
        await Navigator.of(context)
            .pushReplacement(MaterialPageRoute(builder: (_) => destino!));
        return;
      }

      _mostrarMensagem(
        'Perfil de usuário não reconhecido. Contate o administrador.',
      );
      return;
    }

    _mostrarMensagem(
      authCtrl.erroMensagem ??
          'Falha na autenticação. Verifique suas credenciais.',
      erro: true,
    );
  }

  Future<void> _recuperarSenha() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _mostrarMensagem(
        'Digite seu e-mail no campo acima para recuperar a senha.',
      );
      return;
    }

    final authCtrl = context.read<AuthController>();
    final enviado = await authCtrl.recuperarSenhaPorEmail(email);
    if (!mounted) return;

    _mostrarMensagem(
      enviado
          ? 'E-mail de recuperação enviado para $email.'
          : authCtrl.erroMensagem ??
              'Não foi possível enviar o e-mail de redefinição.',
      erro: !enviado,
    );
  }

  void _mostrarMensagem(String mensagem, {bool erro = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(mensagem),
          backgroundColor: erro ? AppTheme.statusRed : AppTheme.primaryDark,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final authController = context.watch<AuthController>();

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 860;
            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: constraints.maxWidth < 480 ? 20 : 32,
                vertical: 24,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 48,
                ),
                child: Center(
                  child: Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxWidth: 1120),
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(isWide ? 24 : 18),
                      border: Border.all(color: AppTheme.border),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primaryDark.withValues(alpha: 0.09),
                          blurRadius: 36,
                          offset: const Offset(0, 18),
                        ),
                      ],
                    ),
                    child: isWide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Expanded(flex: 11, child: _BrandPanel()),
                              Expanded(
                                flex: 10,
                                child: _buildForm(authController, wide: true),
                              ),
                            ],
                          )
                        : _buildForm(authController, wide: false),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildForm(AuthController authController, {required bool wide}) {
    return AutofillGroup(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: wide ? 56 : 24,
          vertical: wide ? 64 : 34,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!wide) ...[
                  const _CompactBrand(),
                  const SizedBox(height: 34),
                ],
                const Text(
                  'Acesse sua operação',
                  style: TextStyle(
                    color: AppTheme.primaryDark,
                    fontSize: 27,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.7,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Entre para acompanhar entregas, rotas e sua equipe.',
                  style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 30),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [
                    AutofillHints.username,
                    AutofillHints.email,
                  ],
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'E-mail',
                    prefixIcon: Icon(Icons.mail_outline_rounded),
                  ),
                  validator: (value) => value == null || !value.contains('@')
                      ? 'Insira um e-mail válido'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _senhaController,
                  obscureText: _senhaOculta,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  onFieldSubmitted: (_) {
                    if (!authController.carregando) _executarLogin();
                  },
                  decoration: InputDecoration(
                    labelText: 'Senha',
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      tooltip: _senhaOculta ? 'Mostrar senha' : 'Ocultar senha',
                      icon: Icon(
                        _senhaOculta
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () =>
                          setState(() => _senhaOculta = !_senhaOculta),
                    ),
                  ),
                  validator: (value) => value == null || value.length < 6
                      ? 'A senha deve ter pelo menos 6 caracteres'
                      : null,
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed:
                        authController.carregando ? null : _recuperarSenha,
                    child: const Text('Esqueci minha senha'),
                  ),
                ),
                const SizedBox(height: 16),
                Semantics(
                  button: true,
                  label: authController.carregando ? 'Entrando' : 'Entrar',
                  child: ElevatedButton(
                    onPressed:
                        authController.carregando ? null : _executarLogin,
                    child: authController.carregando
                        ? const SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('Entrar'),
                              SizedBox(width: 10),
                              Icon(Icons.arrow_forward_rounded, size: 19),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 18),
                TextButton(
                  onPressed: authController.carregando
                      ? null
                      : () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const CadastroScreen(),
                            ),
                          ),
                  child: const Text('Ainda não tem conta? Cadastre-se'),
                ),
                if (authController.erroMensagem != null) ...[
                  const SizedBox(height: 12),
                  Semantics(
                    liveRegion: true,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFEDEA),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        authController.erroMensagem!,
                        style: const TextStyle(
                          color: AppTheme.statusRed,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactBrand extends StatelessWidget {
  const _CompactBrand();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _BrandMark(size: 46),
        SizedBox(width: 12),
        Text(
          'SmartLog',
          style: TextStyle(
            color: AppTheme.primaryDark,
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
          ),
        ),
      ],
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 650),
      padding: const EdgeInsets.all(56),
      color: AppTheme.primaryDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              _BrandMark(size: 48),
              SizedBox(width: 13),
              Text(
                'SmartLog',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                ),
              ),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: AppTheme.accentOrange.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppTheme.accentOrange.withValues(alpha: 0.36),
              ),
            ),
            child: const Text(
              'LOGÍSTICA CONECTADA',
              style: TextStyle(
                color: Color(0xFFFFB082),
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            'Sua operação\nna direção certa.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 40,
              height: 1.12,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.5,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Painel, equipe e entregas trabalhando com a mesma informação, do planejamento à confirmação.',
            style: TextStyle(
              color: Color(0xFFCBD5E1),
              fontSize: 15,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 34),
          const Wrap(
            spacing: 22,
            runSpacing: 14,
            children: [
              _BrandBenefit(
                icon: Icons.route_outlined,
                label: 'Rotas organizadas',
              ),
              _BrandBenefit(
                icon: Icons.location_on_outlined,
                label: 'Operação acompanhada',
              ),
            ],
          ),
          const Spacer(),
          const Text(
            'Acesso seguro para administradores, motoristas e clientes.',
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  final double size;

  const _BrandMark({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppTheme.accentOrange,
        borderRadius: BorderRadius.circular(size * 0.24),
      ),
      child: Icon(
        Icons.local_shipping_rounded,
        color: Colors.white,
        size: size * 0.58,
      ),
    );
  }
}

class _BrandBenefit extends StatelessWidget {
  final IconData icon;
  final String label;

  const _BrandBenefit({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: AppTheme.accentOrange, size: 19),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFFE2E8F0),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
