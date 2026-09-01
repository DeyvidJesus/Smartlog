// lib/screens/motorista.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../controllers/dashboard_controller.dart';
import '../controllers/auth_controller.dart';
import 'chat_assistente.dart';
import 'login.dart';

class DashboardMotorista extends StatefulWidget {
  final String regiaoDesignada;

  const DashboardMotorista({super.key, this.regiaoDesignada = "Não Definida"});

  @override
  State<DashboardMotorista> createState() => _DashboardMotoristaState();
}

class _DashboardMotoristaState extends State<DashboardMotorista> {
  String _abaAtual = "Minha Rota";
  bool _dadosInicializados = false;

  @override
  Widget build(BuildContext context) {
    final DashboardController? controller = context.watch<DashboardController?>();
    final authController = context.read<AuthController>();

    if (controller == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_dadosInicializados && !controller.carregando) {
      _dadosInicializados = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        String? empresaId = authController.empresaIdLogada ?? FirebaseAuth.instance.currentUser?.uid;
        if (empresaId != null) {
          controller.inicializarDados(empresaId);
        }
      });
    }

    final String motoristaUid = FirebaseAuth.instance.currentUser?.uid ?? "";

    // Converte e filtra com tipagem estrita List<Map<String, dynamic>>
    final List<Map<String, dynamic>> rotasDoMotorista = controller.entregas
        .where((e) {
      final map = e is Map ? e : (e as dynamic).toJson();
      final uid = map['motoristaUid']?.toString() ?? '';
      final regiao = map['regiao']?.toString().toLowerCase() ?? '';
      return uid == motoristaUid ||
          (widget.regiaoDesignada != "Não Definida" && regiao.contains(widget.regiaoDesignada.toLowerCase()));
    })
        .map((e) => Map<String, dynamic>.from(e is Map ? e : (e as dynamic).toJson()))
        .toList();

    return Scaffold(
      backgroundColor: const Color(0xffF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xff0F172A),
        foregroundColor: Colors.white,
        title: Text("SmartLog - $_abaAtual"),
      ),
      drawer: Drawer(
        child: Column(
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(color: Color(0xff0F172A)),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.delivery_dining, size: 48, color: Colors.orange),
                    const SizedBox(height: 12),
                    const Text("SmartLog Driver", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    Text(FirebaseAuth.instance.currentUser?.email ?? "motorista@smartlog.com", style: const TextStyle(color: Colors.white70, fontSize: 12))
                  ],
                ),
              ),
            ),
            _itemMenu(Icons.alt_route, "Minha Rota"),
            _itemMenu(Icons.history, "Histórico de Viagens"),
            _itemMenu(Icons.person, "Meu Perfil"),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.support_agent, color: Colors.orange),
              title: const Text("Assistente IA", style: TextStyle(fontWeight: FontWeight.w500)),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ChatAssistenteScreen(
                    perfil: "MOTORISTA",
                    uid: FirebaseAuth.instance.currentUser?.uid ?? "",
                  ),
                ));
              },
            ),
            const Spacer(),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.redAccent),
              title: const Text("Deslogar", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
              onTap: () async {
                await authController.realizarLogout();
                if (mounted) {
                  Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const TelaLogin()));
                }
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
      floatingActionButton: _abaAtual == "Minha Rota"
          ? FloatingActionButton.extended(
        backgroundColor: const Color(0xff0F172A),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.qr_code_scanner, color: Colors.orange),
        label: const Text("Bipar Caixa", style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: () => _abrirCameraScanner(context, controller),
      )
          : null,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: _renderizarConteudo(_abaAtual, rotasDoMotorista, controller),
      ),
    );
  }

  Widget _itemMenu(IconData icon, String titulo) {
    bool selecionado = _abaAtual == titulo;
    return ListTile(
      leading: Icon(icon, color: selecionado ? Colors.orange : Colors.grey),
      title: Text(titulo, style: TextStyle(fontWeight: selecionado ? FontWeight.bold : FontWeight.normal)),
      selected: selecionado,
      onTap: () {
        setState(() => _abaAtual = titulo);
        Navigator.pop(context);
      },
    );
  }

  Widget _renderizarConteudo(String aba, List<Map<String, dynamic>> rotas, DashboardController controller) {
    switch (aba) {
      case "Minha Rota":
        return _buildMinhaRotaView(rotas, controller);
      case "Histórico de Viagens":
        return _buildHistoricoView(rotas);
      case "Meu Perfil":
        return _buildPerfilMotoristaView(controller);
      default:
        return _buildMinhaRotaView(rotas, controller);
    }
  }

  // 1. VISÃO DAS PARADAS ATIVAS
  Widget _buildMinhaRotaView(List<Map<String, dynamic>> rotas, DashboardController controller) {
    final paradasAtivas = rotas.where((e) => e['status'] != 'Entregue').toList();
    paradasAtivas.sort((a, b) => (a['ordemEntrega'] ?? 0).toString().compareTo((b['ordemEntrega'] ?? 0).toString()));

    return Padding(
      key: const ValueKey("MinhaRotaView"),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Paradas Sequenciadas", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xff0F172A))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text("${paradasAtivas.length} pendentes", style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 12)),
              )
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: paradasAtivas.isEmpty
                ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_outline, size: 56, color: Colors.green),
                  SizedBox(height: 12),
                  Text("Parabéns! Nenhuma entrega pendente.", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                ],
              ),
            )
                : ListView.builder(
              itemCount: paradasAtivas.length,
              itemBuilder: (context, index) {
                final parada = paradasAtivas[index];
                final status = parada['status']?.toString() ?? 'Pendente';

                return Card(
                  color: Colors.white,
                  elevation: 1,
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: status == 'Em Rota' || status == 'A Caminho'
                          ? Colors.blue.withOpacity(0.15)
                          : Colors.orange.withOpacity(0.15),
                      child: Text(
                        "${parada['ordemEntrega'] ?? (index + 1)}",
                        style: TextStyle(
                          color: status == 'Em Rota' || status == 'A Caminho' ? Colors.blue : Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    title: Text(parada['endereco']?.toString() ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text("Cliente: ${parada['cliente'] ?? 'Geral'}\nStatus: $status"),
                    ),
                    trailing: const Icon(Icons.qr_code, color: Colors.grey, size: 20),
                  ),
                );
              },
            ),
          )
        ],
      ),
    );
  }

  // 📷 MODAL INJETOR DO SCANNER DE CÂMERA EM TEMPO REAL
  void _abrirCameraScanner(BuildContext context, DashboardController controller) {
    bool processandoBip = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      builder: (context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: const Text("Aponte para o QR Code da Caixa", style: TextStyle(fontSize: 14)),
          leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        ),
        body: SafeArea(
          child: MobileScanner(
            onDetect: (capture) async {
              if (processandoBip) return;

              final List<Barcode> barcodes = capture.barcodes;

              if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
                processandoBip = true;

                final String linkCompleto = barcodes.first.rawValue!;
                String entregaIdDecodificado = linkCompleto;
                if (linkCompleto.contains('/')) {
                  entregaIdDecodificado = linkCompleto.split('/').last.trim();
                }

                Navigator.pop(context);

                String? resposta = await controller.registrarBipQRCode(entregaId: entregaIdDecodificado);

                if (!mounted) return;

                if (resposta != null && resposta.contains("Em Rota")) {
                  _mostrarSnackBar(context, "Pacote $entregaIdDecodificado bipado! Status alterado para: Em Rota 🚚", Colors.blue);
                } else if (resposta != null && (resposta.contains("concluída") || resposta.contains("recebedor"))) {
                  _modalColetaRecebedor(context, controller, entregaIdDecodificado);
                } else {
                  _mostrarSnackBar(context, resposta ?? "Código processado com sucesso.", Colors.orange);
                }
              }
            },
          ),
        ),
      ),
    );
  }

  // 📝 MODAL AUTOMÁTICO DE COLETA DE RECEBEDOR
  void _modalColetaRecebedor(BuildContext context, DashboardController controller, String entregaId) {
    final recebedorCtrl = TextEditingController();
    final popupKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.assignment_ind_outlined, color: Colors.green),
            const SizedBox(width: 8),
            Text("Protocolo $entregaId", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Form(
          key: popupKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Destinatário localizado! Informe o nome de quem está recebendo o pacote:", style: TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 16),
              TextFormField(
                controller: recebedorCtrl,
                autofocus: true,
                decoration: const InputDecoration(labelText: "Nome Completo do Recebedor", border: OutlineInputBorder()),
                validator: (v) => (v == null || v.trim().isEmpty) ? "Obrigatório identificar o recebedor" : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xff0F172A), foregroundColor: Colors.white),
            onPressed: () async {
              if (popupKey.currentState!.validate()) {
                Navigator.pop(context);

                String? fim = await controller.registrarBipQRCode(
                  entregaId: entregaId,
                  nomeRecebedor: recebedorCtrl.text.trim(),
                );

                if (context.mounted) {
                  _mostrarSnackBar(context, fim ?? "Entrega confirmada com sucesso!", Colors.green);
                }
              }
            },
            child: const Text("Confirmar Entrega"),
          ),
        ],
      ),
    );
  }

  void _mostrarSnackBar(BuildContext context, String txt, Color cor) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(txt), backgroundColor: cor));
  }

  // 2. ABA HISTÓRICO
  Widget _buildHistoricoView(List<Map<String, dynamic>> rotas) {
    final concluidas = rotas.where((e) => e['status'] == 'Entregue').toList();
    return Padding(
      key: const ValueKey("HistoricoView"),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Minhas Entregas Realizadas", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xff0F172A))),
          const SizedBox(height: 16),
          Expanded(
            child: concluidas.isEmpty
                ? const Center(child: Text("Nenhuma entrega finalizada no histórico recente.", style: TextStyle(color: Colors.grey)))
                : ListView.builder(
              itemCount: concluidas.length,
              itemBuilder: (context, index) {
                final item = concluidas[index];
                return Card(
                  color: Colors.white,
                  child: ListTile(
                    leading: const CircleAvatar(backgroundColor: Colors.green, child: Icon(Icons.check, color: Colors.white)),
                    title: Text(item['endereco']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text("Cliente: ${item['cliente'] ?? 'Geral'}\nRecebedor: ${item['recebedor'] ?? 'Não informado'}"),
                    trailing: const Text("Concluído", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                );
              },
            ),
          )
        ],
      ),
    );
  }

  // 3. ABA PERFIL
  Widget _buildPerfilMotoristaView(DashboardController controller) {
    final userEmail = FirebaseAuth.instance.currentUser?.email ?? "";
    return SingleChildScrollView(
      key: const ValueKey("PerfilMotoristaView"),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            color: const Color(0xff0F172A),
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  const CircleAvatar(radius: 32, backgroundColor: Colors.orange, child: Icon(Icons.person, size: 36, color: Colors.white)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Motorista Parceiro", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                        const SizedBox(height: 4),
                        Text("Setor Designado: ${widget.regiaoDesignada}", style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 4),
                        Text(userEmail, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                      ],
                    ),
                  )
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text("Configurações e Vínculos ERP", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xff0F172A))),
          const SizedBox(height: 12),
          Card(
            elevation: 1,
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  _infoFichaRow("Veículo de Operação", "Fiorino Furgão (Padrão Leroy Merlin)"),
                  _infoFichaRow("Status de Ativação", "Ativo na Frota"),
                  _infoFichaRow("Segurança Multi-Tenant", "Isolamento Ativo por ID da Empresa"),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _infoFichaRow(String label, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Flexible(child: Text(valor, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}