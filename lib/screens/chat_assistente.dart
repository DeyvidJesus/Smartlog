// lib/screens/chat_assistente.dart
//
// Assistente Logístico — painel operacional de consulta em linguagem natural.
// A tela é só apresentação: todo o estado vive no ChatController, que é criado
// localmente aqui (o recurso não depende do MultiProvider do main.dart).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/chat_controller.dart';
import '../controllers/dashboard_controller.dart';
import '../models/chat_mensagem.dart';
import '../theme/app_theme.dart';
import '../widgets/voice_assistant.dart';

/// Resume a operação exibida na tela para enviar como contexto ao assistente.
/// Mantém o payload enxuto: agregados completos + amostra das entregas.
Map<String, dynamic> _montarContexto(DashboardController d, String perfil) {
  final entregas = d.entregas;

  final Map<String, int> porStatus = {};
  final Map<String, int> porRegiao = {};
  for (final e in entregas) {
    final s = (e['status'] ?? 'Pendente').toString();
    porStatus[s] = (porStatus[s] ?? 0) + 1;
    final r = (e['regiao'] ?? '').toString();
    if (r.isNotEmpty) porRegiao[r] = (porRegiao[r] ?? 0) + 1;
  }

  return {
    'perfil': perfil,
    'totalEntregas': d.totalEntregas,
    'totalMotoristasAtivos': d.totalMotoristasAtivos,
    'totalClientesCadastrados': d.totalClientesCadastrados,
    'distribuicaoPorStatus': porStatus,
    'distribuicaoPorRegiao': porRegiao,
    'motoristas': d.motoristas,
    // Amostra: o suficiente para citar entregas sem estourar tokens
    'entregas': entregas.take(40).toList(),
    'observacao': entregas.length > 40
        ? 'Lista truncada nas 40 primeiras; os totais acima consideram todas as ${entregas.length}.'
        : null,
  };
}

class ChatAssistenteScreen extends StatelessWidget {
  /// ADMINISTRADOR, MOTORISTA ou CLIENTE — define as sugestões e o escopo de dados.
  final String perfil;
  final String uid;

  const ChatAssistenteScreen(
      {super.key, required this.perfil, required this.uid});

  @override
  Widget build(BuildContext context) {
    // Captura o controller do painel para alimentar o assistente com os
    // mesmos dados que o usuário está vendo na tela.
    final DashboardController dashboard = context.read<DashboardController>();

    return ChangeNotifierProvider<ChatController>(
      create: (_) => ChatController(
        uid: uid,
        perfil: perfil,
        contextoBuilder: () => _montarContexto(dashboard, perfil),
      ),
      child: const _ChatAssistenteView(),
    );
  }
}

class _ChatAssistenteView extends StatefulWidget {
  const _ChatAssistenteView();

  @override
  State<_ChatAssistenteView> createState() => _ChatAssistenteViewState();
}

class _ChatAssistenteViewState extends State<_ChatAssistenteView> {
  final TextEditingController _campoCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _campoCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _rolarParaFim() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _enviar(ChatController controller, String texto) async {
    if (texto.trim().isEmpty || controller.enviando) return;
    _campoCtrl.clear();
    FocusScope.of(context).unfocus();
    _rolarParaFim();
    await controller.enviar(texto);
    _rolarParaFim();
  }

  @override
  Widget build(BuildContext context) {
    final ChatController controller = context.watch<ChatController>();

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryDark,
        foregroundColor: Colors.white,
        title: const Text("Assistente Logístico"),
        actions: [
          const VoiceAssistantButton(),
          if (!controller.conversaVazia)
            IconButton(
              tooltip: "Limpar conversa",
              icon: const Icon(Icons.delete_outline),
              onPressed: controller.enviando ? null : controller.limparConversa,
            ),
        ],
      ),
      body: Column(
        children: [
          _cabecalhoContexto(controller.perfil),
          Expanded(
            child: controller.conversaVazia
                ? _estadoInicial(controller)
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    itemCount: controller.mensagens.length +
                        (controller.enviando ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= controller.mensagens.length) {
                        return _indicadorConsultando();
                      }
                      return _bloco(controller.mensagens[index]);
                    },
                  ),
          ),
          if (!controller.conversaVazia) _faixaSugestoes(controller),
          _barraEnvio(controller),
        ],
      ),
    );
  }

  // ── Cabeçalho fixo: deixa explícito qual escopo de dados está sendo consultado ──
  Widget _cabecalhoContexto(String perfil) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      color: const Color(0xff0F172A),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child:
                const Icon(Icons.support_agent, color: Colors.orange, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Consultando dados de: ${_rotuloPerfil(perfil)}",
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                const Text(
                  "Respostas geradas a partir dos registros do SmartLog",
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _rotuloPerfil(String perfil) {
    switch (perfil.toUpperCase()) {
      case 'ADMINISTRADOR':
      case 'ADMIN':
        return "toda a operação";
      case 'MOTORISTA':
        return "suas rotas";
      case 'CLIENTE':
        return "seus pedidos";
      default:
        return "seu perfil";
    }
  }

  // ── Tela inicial: apresenta o que dá para perguntar, em vez de um chat em branco ──
  Widget _estadoInicial(ChatController controller) {
    final List<String> sugestoes = controller.sugestoesRapidas;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 8),
        Center(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child:
                    const Icon(Icons.insights, size: 36, color: Colors.orange),
              ),
              const SizedBox(height: 12),
              const Text(
                "Como posso ajudar na operação?",
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xff0F172A)),
              ),
              const SizedBox(height: 4),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  "Pergunte em linguagem natural. As respostas usam somente os dados registrados no sistema.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        if (sugestoes.isNotEmpty) ...[
          const Text(
            "Consultas rápidas",
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Color(0xff334155)),
          ),
          const SizedBox(height: 8),
          ...sugestoes.map(
            (s) => Card(
              color: Colors.white,
              elevation: 1,
              margin: const EdgeInsets.symmetric(vertical: 4),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                leading: const Icon(Icons.bolt, color: Colors.orange, size: 20),
                title: Text(s,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500)),
                trailing: const Icon(Icons.chevron_right,
                    size: 18, color: Colors.grey),
                onTap: () => _enviar(controller, s),
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ── Sugestões compactas depois que a conversa começou ──
  Widget _faixaSugestoes(ChatController controller) {
    final List<String> sugestoes = controller.sugestoesRapidas;
    if (sugestoes.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        itemCount: sugestoes.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final String s = sugestoes[index];
          return ActionChip(
            label: Text(s, style: const TextStyle(fontSize: 11)),
            avatar: const Icon(Icons.bolt, size: 14, color: Colors.orange),
            backgroundColor: Colors.white,
            side: const BorderSide(color: Color(0xffE2E8F0)),
            onPressed:
                controller.enviando ? null : () => _enviar(controller, s),
          );
        },
      ),
    );
  }

  // ── Mensagens: usuário como faixa navy à direita, assistente como ficha operacional ──
  Widget _bloco(Mensagem mensagem) {
    if (mensagem.ehDoUsuario) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12, left: 40),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xff0F172A),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            mensagem.texto,
            style: const TextStyle(
                color: Colors.white, fontSize: 13, height: 1.35),
          ),
        ),
      );
    }

    final bool erro = mensagem.falhou;
    final Color destaque = erro ? Colors.red : Colors.orange;

    return Container(
      margin: const EdgeInsets.only(bottom: 12, right: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: destaque, width: 4)),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 3)],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(erro ? Icons.error_outline : Icons.support_agent,
                  size: 15, color: destaque),
              const SizedBox(width: 6),
              Text(
                erro ? "Não foi possível responder" : "Assistente",
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.bold, color: destaque),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            mensagem.texto,
            style: const TextStyle(
                fontSize: 13, color: Color(0xff334155), height: 1.45),
          ),
        ],
      ),
    );
  }

  Widget _indicadorConsultando() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12, right: 24),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: const Border(left: BorderSide(color: Colors.orange, width: 4)),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 3)],
      ),
      child: const Row(
        children: [
          SizedBox(
            height: 14,
            width: 14,
            child:
                CircularProgressIndicator(strokeWidth: 2, color: Colors.orange),
          ),
          SizedBox(width: 10),
          Text(
            "Consultando os dados da operação...",
            style: TextStyle(
                fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  Widget _barraEnvio(ChatController controller) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xffE2E8F0))),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _campoCtrl,
                enabled: !controller.enviando,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (valor) => _enviar(controller, valor),
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: "Pergunte sobre a operação...",
                  hintStyle: const TextStyle(fontSize: 13, color: Colors.grey),
                  filled: true,
                  fillColor: const Color(0xffF5F7FA),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: controller.enviando
                  ? Colors.grey.shade400
                  : const Color(0xff0F172A),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: controller.enviando
                    ? null
                    : () => _enviar(controller, _campoCtrl.text),
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Icon(Icons.send, color: Colors.white, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
