// lib/screens/cliente.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../controllers/dashboard_controller.dart';
import '../controllers/auth_controller.dart';
import 'chat_assistente.dart';
import 'login.dart';

class DashboardCliente extends StatefulWidget {
  const DashboardCliente({super.key});

  @override
  State<DashboardCliente> createState() => _DashboardClienteState();
}

class _DashboardClienteState extends State<DashboardCliente> {
  // 🔥 Trava para não buscar dados infinitamente
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
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final String? empresaId = authController.empresaIdLogada ?? FirebaseAuth.instance.currentUser?.uid;
        if (empresaId != null) {
          await controller.inicializarDados(empresaId);
        }
      });
    }

    // 👤 Obtenção 100% segura do nome sem depender de getters do AuthController
    final String nomeCliente = FirebaseAuth.instance.currentUser?.displayName ??
        FirebaseAuth.instance.currentUser?.email?.split('@').first ??
        "Cliente";
    final String userEmail = FirebaseAuth.instance.currentUser?.email ?? "";

    // 👥 Filtragem de entregas via controller
    final List<Map<String, dynamic>> minhasEntregas = controller.filtrarPorCliente(nomeCliente);

    // Prioridade de ordenação do status
    const Map<String, int> prioridadeStatus = {
      'Atrasada': 0,
      'Pendente': 1,
      'A Caminho': 2,
      'Em Rota': 2,
      'Entregue': 3,
    };

    minhasEntregas.sort((a, b) {
      final int pa = prioridadeStatus[a['status']] ?? 4;
      final int pb = prioridadeStatus[b['status']] ?? 4;
      if (pa != pb) return pa.compareTo(pb);
      return ((a['ordemEntrega'] ?? 0) as num).compareTo((b['ordemEntrega'] ?? 0) as num);
    });

    return Scaffold(
      backgroundColor: const Color(0xffF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xff0F172A),
        foregroundColor: Colors.white,
        title: const Text("SmartLog - Minhas Entregas"),
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
                    const Icon(Icons.business, size: 44, color: Colors.orange),
                    const SizedBox(height: 12),
                    const Text("SmartLog Cliente", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(
                      nomeCliente.isEmpty ? "Cliente Corporativo" : nomeCliente,
                      style: const TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      userEmail,
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
            const ListTile(
              leading: Icon(Icons.inventory_2, color: Colors.orange),
              title: Text("Minhas Entregas", style: TextStyle(fontWeight: FontWeight.bold)),
              selected: true,
            ),
            ListTile(
              leading: const Icon(Icons.support_agent, color: Colors.orange),
              title: const Text("Assistente IA", style: TextStyle(fontWeight: FontWeight.w500)),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ChatAssistenteScreen(
                    perfil: "CLIENTE",
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
                final NavigatorState navegador = Navigator.of(context);
                await authController.realizarLogout();
                if (!mounted) return;
                navegador.pushReplacement(MaterialPageRoute(builder: (_) => const TelaLogin()));
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Acompanhe seus Pedidos", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xff0F172A))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    minhasEntregas.length == 1 ? "1 entrega" : "${minhasEntregas.length} entregas",
                    style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                )
              ],
            ),
            const SizedBox(height: 16),

            Expanded(
              child: (controller.carregando && controller.entregas.isEmpty)
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                color: Colors.orange,
                onRefresh: () async {
                  final String? empresaId = authController.empresaIdLogada ?? FirebaseAuth.instance.currentUser?.uid;
                  if (empresaId != null) {
                    // inicializarDados é síncrono nesta versão do controller
                    controller.inicializarDados(empresaId);
                  }
                },
                child: minhasEntregas.isEmpty
                    ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(
                      height: 260,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey),
                            SizedBox(height: 8),
                            Text(
                              "Nenhuma entrega registrada.",
                              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500),
                            ),
                            SizedBox(height: 2),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 24),
                              child: Text(
                                "Assim que a transportadora registrar uma entrega para você, ela aparecerá aqui.",
                                style: TextStyle(color: Colors.grey, fontSize: 12),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
                    : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: minhasEntregas.length,
                  itemBuilder: (context, index) => _cardEntregaCliente(minhasEntregas[index]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardEntregaCliente(Map<String, dynamic> entrega) {
    final String status = (entrega['status'] ?? 'Pendente').toString();
    final Color corStatus = _corDoStatus(status);
    final String motorista = (entrega['motorista'] ?? '').toString().trim();
    final bool temMotorista = motorista.isNotEmpty && motorista != 'Sem motorista';

    return Card(
      color: Colors.white,
      elevation: 1,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    (entrega['id'] ?? 'Sem código').toString(),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xff0F172A), letterSpacing: 0.5),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: corStatus.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(color: corStatus, fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              (entrega['endereco'] ?? 'Endereço não informado').toString(),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xff334155)),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),

            if (temMotorista) ...[
              _linhaInfo(Icons.delivery_dining, "Motorista: $motorista"),
              const SizedBox(height: 4),
            ],
            _linhaInfo(Icons.place_outlined, "Região: ${entrega['regiao'] ?? 'Não definida'}"),

            const Divider(height: 22, thickness: 0.5),
            _timelineEntrega(status),
          ],
        ),
      ),
    );
  }

  Widget _timelineEntrega(String status) {
    const List<String> etapas = ["Pendente", "Em Rota", "Entregue"];

    final int posicao = etapas.indexOf(status == 'A Caminho' ? 'Em Rota' : status);
    final int etapaAtual = posicao < 0 ? 0 : posicao;

    return Column(
      children: [
        Row(
          children: [
            for (int i = 0; i < etapas.length; i++) ...[
              if (i > 0)
                Expanded(
                  child: Container(
                    height: 2,
                    color: (i <= etapaAtual) ? _corDoStatus(etapas[i]) : Colors.grey.shade300,
                  ),
                ),
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (i <= etapaAtual) ? _corDoStatus(etapas[i]) : Colors.transparent,
                  border: Border.all(
                    color: (i <= etapaAtual) ? _corDoStatus(etapas[i]) : Colors.grey.shade400,
                    width: 2,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (int i = 0; i < etapas.length; i++)
              Expanded(
                child: Text(
                  etapas[i],
                  textAlign: i == 0
                      ? TextAlign.start
                      : (i == etapas.length - 1 ? TextAlign.end : TextAlign.center),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: (i == etapaAtual) ? FontWeight.bold : FontWeight.normal,
                    color: (i <= etapaAtual) ? _corDoStatus(etapas[i]) : Colors.grey,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _linhaInfo(IconData icon, String texto) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            texto,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Color _corDoStatus(String status) {
    switch (status) {
      case 'Pendente':
        return Colors.orange;
      case 'A Caminho':
      case 'Em Rota':
        return Colors.blue;
      case 'Entregue':
        return Colors.green;
      case 'Atrasada':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}