// lib/screens/dashboard_admin.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';

import '../controllers/dashboard_controller.dart';
import '../theme/app_theme.dart';
import 'chat_assistente.dart';
import '../services/maps_service.dart';

class DashboardAdmin extends StatefulWidget {
  const DashboardAdmin({super.key});

  @override
  State<DashboardAdmin> createState() => _DashboardAdminState();
}

class _DashboardAdminState extends State<DashboardAdmin> {
  int _indiceTabAtual = 0;
  String _zonaSelecionada = "TODAS";
  DateTime? _dataSelecionada;

  // Removidos: _promptController, _chatService, _respostaIA e _carregandoIA.
  // Sobras do painel "AI Insights", que saiu da tela. O assistente hoje vive
  // em ChatAssistenteScreen, que instancia o próprio ChatService.

  final List<String> _titulosAbas = [
    "Dashboard",
    "Entregas",
    "Rotas",
    "Motoristas",
    "Clientes",
    "Perfil"
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = context.read<DashboardController>();
      if (controller.empresaId != null) {
        controller.inicializarDados(controller.empresaId!);
      } else {
        controller.carregarEntregas();
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DashboardController>();
    final String abaAtual = _titulosAbas[_indiceTabAtual];

    return Scaffold(
      appBar: AppBar(
        title: Text("SmartLog • $abaAtual"),
        backgroundColor: AppTheme.primaryDark,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Recarregar Dados",
            onPressed: () {
              if (controller.empresaId != null) {
                controller.inicializarDados(controller.empresaId!);
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.support_agent),
            tooltip: "Assistente IA",
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ChatAssistenteScreen(
                  perfil: "ADMINISTRADOR",
                  uid: FirebaseAuth.instance.currentUser?.uid ?? "",
                ),
              ));
            },
          ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: _renderizarConteudo(controller),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _indiceTabAtual,
        onTap: (index) {
          setState(() {
            _indiceTabAtual = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppTheme.accentOrange,
        unselectedItemColor: AppTheme.statusGrey,
        selectedLabelStyle:
        const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        unselectedLabelStyle: const TextStyle(fontSize: 11),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            activeIcon: Icon(Icons.dashboard),
            label: "Painel",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.local_shipping_outlined),
            activeIcon: Icon(Icons.local_shipping),
            label: "Entregas",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map_outlined),
            activeIcon: Icon(Icons.map),
            label: "Rotas",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.badge_outlined),
            activeIcon: Icon(Icons.badge),
            label: "Motoristas",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.store_outlined),
            activeIcon: Icon(Icons.store),
            label: "Clientes",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: "Perfil",
          ),
        ],
      ),
    );
  }

  Widget _renderizarConteudo(DashboardController controller) {
    switch (_indiceTabAtual) {
      case 0:
        return _buildDashboardPrincipal(controller);
      case 1:
        return _buildAbaEntregas(controller);
      case 2:
        return _buildAbaRotas(controller);
      case 3:
        return _buildAbaMotoristas(controller);
      case 4:
        return _buildAbaClientes(controller);
      case 5:
        return _buildAbaPerfil(controller); // Corrigido para passar o controller
      default:
        return _buildDashboardPrincipal(controller);
    }
  }

  // 1. DASHBOARD PRINCIPAL
  Widget _buildDashboardPrincipal(DashboardController controller) {
    return SingleChildScrollView(
      key: const ValueKey("DashboardView"),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Visão Geral da Operação",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.primaryDark,
            ),
          ),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.4,
            children: [
              _CardDashboard("Total Entregas", controller.totalEntregas.toString(),
                  Icons.inventory_2_outlined, Colors.blue),
              _CardDashboard(
                  "Motoristas Ativos",
                  controller.totalMotoristasAtivos.toString(),
                  Icons.delivery_dining_outlined,
                  AppTheme.statusGreen),
              _CardDashboard(
                  "Clientes Parceiros",
                  controller.totalClientesCadastrados.toString(),
                  Icons.people_outline,
                  Colors.purple),
              _CardDashboard("Rotas Criadas", controller.rotas.length.toString(),
                  Icons.alt_route, AppTheme.accentOrange),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // 2. ENTREGAS (Admin)
  Widget _buildAbaEntregas(DashboardController controller) {
    final entregasFiltradas = controller.entregas.where((e) {
      final bool bateRegiao = _zonaSelecionada == "TODAS" ||
          (e['regiao'] ?? '').toString().toLowerCase() ==
              _zonaSelecionada.toLowerCase();

      bool bateData = true;
      if (_dataSelecionada != null) {
        final String dataFormatada =
            "${_dataSelecionada!.year}-${_dataSelecionada!.month.toString().padLeft(2, '0')}-${_dataSelecionada!.day.toString().padLeft(2, '0')}";
        bateData = e['data'] == dataFormatada;
      }

      return bateRegiao && bateData;
    }).toList();

    return Padding(
      key: const ValueKey("EntregasView"),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Gestão de Entregas",
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryDark),
              ),
              ElevatedButton.icon(
                onPressed: () => _modalCadastroEntrega(context, controller),
                icon: const Icon(Icons.add, size: 18),
                label: const Text("Cadastrar"),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.calendar_month,
                          size: 20, color: AppTheme.primaryDark),
                      const SizedBox(width: 8),
                      Text(
                        _dataSelecionada == null
                            ? "Todas as Datas"
                            : "Data: ${_dataSelecionada!.day.toString().padLeft(2, '0')}/${_dataSelecionada!.month.toString().padLeft(2, '0')}/${_dataSelecionada!.year}",
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryDark),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      if (_dataSelecionada != null)
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.red),
                          onPressed: () =>
                              setState(() => _dataSelecionada = null),
                        ),
                      ElevatedButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate:
                            _dataSelecionada ?? DateTime(2026, 9, 22),
                            firstDate: DateTime(2026, 1, 1),
                            lastDate: DateTime(2026, 12, 31),
                          );
                          if (picked != null) {
                            setState(() => _dataSelecionada = picked);
                          }
                        },
                        child: const Text("Filtrar Data"),
                      ),
                    ],
                  )
                ],
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ["TODAS", "Norte", "Sul", "Leste", "Oeste"].map((zona) {
                final isSelected = _zonaSelecionada == zona;
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ChoiceChip(
                    label: Text(zona),
                    selected: isSelected,
                    selectedColor: AppTheme.accentOrange,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : AppTheme.primaryDark,
                      fontWeight:
                      isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    onSelected: (selected) {
                      if (selected) setState(() => _zonaSelecionada = zona);
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            "Exibindo ${entregasFiltradas.length} entregas",
            style: const TextStyle(
                color: AppTheme.statusGrey,
                fontSize: 13,
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: entregasFiltradas.isEmpty
                ? const Center(child: Text("Nenhuma entrega encontrada."))
                : ListView.builder(
              itemCount: entregasFiltradas.length,
              itemBuilder: (context, index) {
                final entrega = entregasFiltradas[index];
                final status = entrega['status'] ?? 'Pendente';
                final motoristaNome = entrega['motoristaNome'] ?? entrega['motorista'] ?? 'Não atribuído';

                // Pegando o e-mail do cliente salvo na entrega (se houver)
                final emailCliente = entrega['emailCliente'] ?? entrega['email'] ?? 'Sem e-mail cadastrado';

                final Color statusColor = status == 'Entregue'
                    ? AppTheme.statusGreen
                    : status == 'Em Rota'
                    ? AppTheme.statusOrange
                    : AppTheme.statusGrey;

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    onTap: () {
                      _modalDetalhesEntrega(context, entrega);
                    },
                    leading: const CircleAvatar(
                      backgroundColor: AppTheme.backgroundLight,
                      child: Icon(Icons.local_shipping,
                          color: AppTheme.primaryDark),
                    ),
                    title: Text(
                      "${entrega['id'] ?? 'ENT'} • ${entrega['cliente'] ?? 'Cliente'}",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    // Adicionado o e-mail do cliente logo abaixo do endereço
                    subtitle: Text(
                        "${entrega['endereco'] ?? ''}\nE-mail: $emailCliente\nRegião: ${entrega['regiao']} | Motorista: $motoristaNome"),
                    isThreeLine: true,
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: statusColor, width: 1),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                            color: statusColor,
                            fontSize: 11,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _modalDetalhesEntrega(
      BuildContext context, Map<String, dynamic> entrega) {
    final status = entrega['status'] ?? 'Pendente';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Detalhes da ${entrega['id'] ?? 'Entrega'}",
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryDark),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 8),
              _buildDetalheLinha(Icons.store, "Cliente",
                  entrega['cliente'] ?? 'Não informado'),
              const SizedBox(height: 12),
              _buildDetalheLinha(Icons.location_on, "Endereço",
                  entrega['endereco'] ?? 'Não informado'),
              const SizedBox(height: 12),
              _buildDetalheLinha(
                  Icons.map, "Região", entrega['regiao'] ?? 'Não informada'),
              const SizedBox(height: 12),
              _buildDetalheLinha(Icons.calendar_today, "Data",
                  entrega['data'] ?? 'Não informada'),
              const SizedBox(height: 12),
              _buildDetalheLinha(Icons.badge, "Motorista",
                  entrega['motorista'] ?? 'Não atribuído'),
              const SizedBox(height: 12),
              _buildDetalheLinha(Icons.info_outline, "Status Atual", status),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("Fechar"),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetalheLinha(IconData icon, String titulo, String valor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppTheme.accentOrange),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo,
                  style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.statusGrey,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(valor,
                  style: const TextStyle(
                      fontSize: 15,
                      color: AppTheme.primaryDark,
                      fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ],
    );
  }

  void _modalCadastroEntrega(
      BuildContext context, DashboardController controller) {
    final clienteCtrl = TextEditingController();
    final emailCtrl = TextEditingController(); // <- Controlador para o e-mail do cliente
    final enderecoCtrl = TextEditingController();
    final dataCtrl = TextEditingController(text: "2026-09-22");
    String zonaSelecionadaModal = "Sul";

    String? motoristaResponsavelId = controller.motoristas.isNotEmpty
        ? controller.motoristas.first['id']
        : null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(modalContext).viewInsets.bottom + 16,
                top: 24,
                left: 16,
                right: 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "Cadastrar Nova Entrega",
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryDark),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: clienteCtrl,
                      decoration: const InputDecoration(
                          labelText: "Nome do Cliente",
                          border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    // <- Novo campo de E-mail do Cliente inserido aqui
                    TextField(
                      controller: emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                          labelText: "E-mail do Cliente (Para rastreio)",
                          hintText: "cliente@email.com",
                          border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: enderecoCtrl,
                      decoration: InputDecoration(
                        labelText: "Endereço ou CEP (Ex: Rua Augusta, 500)",
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.search,
                              color: AppTheme.primaryDark),
                          tooltip: "Buscar Região via Google Maps",
                          onPressed: () async {
                            if (enderecoCtrl.text.trim().isEmpty) return;

                            final resultado =
                            await MapsService.identificarRegiaoPorEndereco(
                                enderecoCtrl.text);

                            if (resultado != null) {
                              setModalState(() {
                                zonaSelecionadaModal = resultado['regiao'];
                                enderecoCtrl.text =
                                resultado['enderecoFormatado'];
                              });

                              if (modalContext.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text(
                                          "Região identificada: $zonaSelecionadaModal")),
                                );
                              }
                            } else {
                              if (modalContext.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          "Endereço não encontrado. Verifique os dados.")),
                                );
                              }
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: dataCtrl,
                      decoration: const InputDecoration(
                          labelText: "Data (AAAA-MM-DD)",
                          border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: zonaSelecionadaModal,
                      decoration: const InputDecoration(
                          labelText: "Região de SP",
                          border: OutlineInputBorder()),
                      items: ["Norte", "Sul", "Leste", "Oeste", "Centro"]
                          .map(
                              (z) => DropdownMenuItem(value: z, child: Text(z)))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setModalState(() => zonaSelecionadaModal = val);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: controller.motoristas
                          .any((m) => m['id'] == motoristaResponsavelId)
                          ? motoristaResponsavelId
                          : (controller.motoristas.isNotEmpty
                          ? controller.motoristas.first['id']
                          : null),
                      decoration: const InputDecoration(
                          labelText: "Motorista Responsável",
                          border: OutlineInputBorder()),
                      items: controller.motoristas.map((m) {
                        final idMotorista = m['id'] as String;
                        final nomeMotorista = m['nome'] ?? 'Motorista';
                        return DropdownMenuItem<String>(
                          value: idMotorista,
                          child: Text(nomeMotorista),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setModalState(() => motoristaResponsavelId = val);
                        }
                      },
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          if (clienteCtrl.text.isNotEmpty &&
                              enderecoCtrl.text.isNotEmpty) {
                            if (controller.empresaId != null) {
                              final motoristaSelecionadoObj =
                              controller.motoristas.firstWhere(
                                    (m) => m['id'] == motoristaResponsavelId,
                                orElse: () => {
                                  'id': '',
                                  'nome': 'Não atribuído'
                                },
                              );

                              final nomeMotoristaFinal =
                                  motoristaSelecionadoObj['nome'] ??
                                      'Não atribuído';
                              final idMotoristaFinal =
                                  motoristaSelecionadoObj['id'] ?? '';

                              final nomeCliente = clienteCtrl.text.trim();
                              final emailCliente = emailCtrl.text.trim();
                              final empresaId = controller.empresaId!;

                              // 1. Verificar se o cliente já existe na coleção 'clientes' da empresa
                              final clienteQuery = await FirebaseFirestore.instance
                                  .collection('clientes')
                                  .where('empresaId', isEqualTo: empresaId)
                                  .where('nome', isEqualTo: nomeCliente)
                                  .get();

                              if (clienteQuery.docs.isEmpty) {
                                // Se não existe, cadastra automaticamente na coleção 'clientes'
                                await FirebaseFirestore.instance.collection('clientes').add({
                                  'empresaId': empresaId,
                                  'nome': nomeCliente,
                                  'email': emailCliente.isNotEmpty ? emailCliente : 'E-mail não informado',
                                  'endereco': enderecoCtrl.text.trim(),
                                  'criadoEm': FieldValue.serverTimestamp(),
                                });
                              }

                              // 2. Salva a entrega normalmente
                              final docRef = await FirebaseFirestore.instance
                                  .collection('entregas')
                                  .add({
                                'empresaId': empresaId,
                                'cliente': nomeCliente,
                                'emailCliente': emailCliente,
                                'endereco': enderecoCtrl.text.trim(),
                                'data': dataCtrl.text.trim(),
                                'regiao': zonaSelecionadaModal,
                                'motorista': nomeMotoristaFinal,
                                'motoristaId': idMotoristaFinal,
                                'status': 'Pendente',
                                // Sem esta data não há como calcular atraso:
                                // o assistente respondia "0 atrasadas" sempre.
                                'criadoEm': FieldValue.serverTimestamp(),
                              });

                              await docRef
                                  .update({'id': codigoEntrega(docRef.id)});

                              // 3. Atualiza os dados no controller para refletir nas telas
                              await controller.carregarEntregas();
                            }
                            if (modalContext.mounted) {
                              Navigator.pop(modalContext);
                            }
                          }
                        },
                        child: const Text("Salvar Entrega"),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // 3. ROTAS
  Widget _buildAbaRotas(DashboardController controller) {
    return Padding(
      key: const ValueKey("RotasView"),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Gestão de Rotas",
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryDark),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  if (controller.motoristas.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text(
                              "Cadastre um motorista primeiro antes de gerar rotas.")),
                    );
                    return;
                  }

                  String regiaoEscolhida = "Sul";

                  await showDialog(
                    context: context,
                    builder: (dialogContext) {
                      return AlertDialog(
                        title: const Text("Gerar Rota por Região"),
                        content: StatefulBuilder(
                          builder: (context, setStateDialog) {
                            return DropdownButtonFormField<String>(
                              value: regiaoEscolhida,
                              decoration: const InputDecoration(
                                  labelText: "Selecione a Região",
                                  border: OutlineInputBorder()),
                              items: [
                                "Norte",
                                "Sul",
                                "Leste",
                                "Oeste",
                                "Centro"
                              ]
                                  .map((z) => DropdownMenuItem(
                                  value: z, child: Text(z)))
                                  .toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setStateDialog(() => regiaoEscolhida = val);
                                }
                              },
                            );
                          },
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            child: const Text("Cancelar"),
                          ),
                          ElevatedButton(
                            onPressed: () async {
                              Navigator.pop(dialogContext);

                              final motorista = controller.motoristas.first;
                              final motoristaId = motorista['id'];
                              final motoristaNome =
                                  motorista['nome'] ?? 'Motorista';

                              bool sucesso =
                              await controller.gerarRotaParaMotorista(
                                motoristaId: motoristaId,
                                motoristaNome: motoristaNome,
                                regiao: regiaoEscolhida,
                                nomeRota:
                                "Rota Zona $regiaoEscolhida - $motoristaNome",
                              );

                              if (context.mounted) {
                                if (sucesso) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text(
                                            "Rota da região $regiaoEscolhida gerada com sucesso!")),
                                  );
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text(
                                            "Nenhuma entrega 'Pendente' encontrada na região $regiaoEscolhida.")),
                                  );
                                }
                              }
                            },
                            child: const Text("Gerar"),
                          ),
                        ],
                      );
                    },
                  );
                },
                icon: const Icon(Icons.alt_route, size: 18),
                label: const Text("Gerar Rota"),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentOrange,
                    foregroundColor: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: controller.rotas.isEmpty
                ? const Center(child: Text("Nenhuma rota gerada no momento."))
                : ListView.builder(
              itemCount: controller.rotas.length,
              itemBuilder: (context, index) {
                final rota = controller.rotas[index];
                final status = rota['status'] ?? 'Pendente';
                final total = rota['totalEnderecos'] ??
                    (rota['enderecos'] as List?)?.length ??
                    0;
                final rotaId = rota['id'] ?? '';

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: AppTheme.backgroundLight,
                      child: Icon(Icons.alt_route,
                          color: AppTheme.accentOrange),
                    ),
                    title: Text(rota['nome'] ?? 'Rota',
                        style:
                        const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                        "Motorista: ${rota['motoristaNome']}\nRegião: ${rota['regiao']} • $total Endereços"),
                    isThreeLine: true,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.map,
                              color: AppTheme.primaryDark),
                          tooltip: "Rastrear ao Vivo",
                          onPressed: () {
                            if (rotaId.isNotEmpty) {
                              _abrirModalMapaAoVivo(context, rotaId,
                                  rota['nome'] ?? 'Rota');
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        "ID da rota inválido para monitoramento.")),
                              );
                            }
                          },
                        ),
                        Chip(
                          label: Text(status,
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold)),
                          backgroundColor: status == 'Em Andamento'
                              ? AppTheme.statusOrange.withOpacity(0.2)
                              : AppTheme.backgroundLight,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _abrirModalMapaAoVivo(
      BuildContext context, String rotaId, String nomeRota) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.75,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    nomeRota,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryDark),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 8),
              Expanded(
                child: StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('rotas')
                      .doc(rotaId)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (!snapshot.hasData || !snapshot.data!.exists) {
                      return const Center(
                          child: Text(
                              "Dados da rota não encontrados no Firestore."));
                    }

                    var data = snapshot.data!.data() as Map<String, dynamic>?;
                    var loc = data?['localizacaoAtual'];

                    if (loc == null) {
                      return const Center(
                        child: Text(
                          "Aguardando sinal de GPS do motorista...\n(O motorista precisa iniciar a rota no celular dele)",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppTheme.statusGrey),
                        ),
                      );
                    }

                    double lat = loc['latitude'];
                    double lng = loc['longitude'];
                    LatLng posicaoMotorista = LatLng(lat, lng);

                    return ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: posicaoMotorista,
                          zoom: 16,
                        ),
                        markers: {
                          Marker(
                            markerId: const MarkerId('motorista_ativo'),
                            position: posicaoMotorista,
                            infoWindow: InfoWindow(
                              title: 'Motorista em Movimento',
                              snippet: 'Lat: $lat, Lng: $lng',
                            ),
                          ),
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // 4. MOTORISTAS
  Widget _buildAbaMotoristas(DashboardController controller) {
    return Padding(
      key: const ValueKey("MotoristasView"),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Equipe de Motoristas",
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryDark),
              ),
              ElevatedButton.icon(
                onPressed: () => _modalCadastroMotorista(context, controller),
                icon: const Icon(Icons.add, size: 18),
                label: const Text("Cadastrar"),
              )
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: controller.motoristas.isEmpty
                ? const Center(child: Text("Nenhum motorista cadastrado."))
                : ListView.builder(
              itemCount: controller.motoristas.length,
              itemBuilder: (context, index) {
                final m = controller.motoristas[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: AppTheme.accentOrange,
                      child: Icon(Icons.person, color: Colors.white),
                    ),
                    title: Text(m['nome'] ?? 'Motorista',
                        style:
                        const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                        "${m['email']} • Região: ${m['regiaoDesignada'] ?? m['regiao'] ?? 'Geral'}"),
                  ),
                );
              },
            ),
          )
        ],
      ),
    );
  }

  void _modalCadastroMotorista(
      BuildContext context, DashboardController controller) {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    String zonaSelecionadaModal = "Sul";

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(modalContext).viewInsets.bottom + 16,
                top: 24,
                left: 16,
                right: 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "Cadastrar Novo Motorista",
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryDark),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                          labelText: "Nome Completo",
                          border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: emailCtrl,
                      decoration: const InputDecoration(
                          labelText: "E-mail de Acesso",
                          border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: zonaSelecionadaModal,
                      decoration: const InputDecoration(
                          labelText: "Região Designada",
                          border: OutlineInputBorder()),
                      items: ["Norte", "Sul", "Leste", "Oeste"]
                          .map(
                              (z) => DropdownMenuItem(value: z, child: Text(z)))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setModalState(() => zonaSelecionadaModal = val);
                        }
                      },
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          if (nameCtrl.text.isNotEmpty &&
                              emailCtrl.text.isNotEmpty) {
                            await controller.cadastrarNovoMotorista(
                              nome: nameCtrl.text.trim(),
                              email: emailCtrl.text.trim(),
                              regiao: zonaSelecionadaModal,
                            );
                            if (modalContext.mounted) {
                              Navigator.pop(modalContext);
                            }
                          }
                        },
                        child: const Text("Salvar Registro"),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // 5. CLIENTES
  Widget _buildAbaClientes(DashboardController controller) {
    return Padding(
      key: const ValueKey("ClientesView"),
      padding: const EdgeInsets.all(16),
      child: controller.clientes.isEmpty
          ? const Center(child: Text("Nenhum cliente cadastrado."))
          : ListView.builder(
        itemCount: controller.clientes.length,
        itemBuilder: (context, index) {
          final cliente = controller.clientes[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppTheme.backgroundLight,
                child: Icon(Icons.store, color: AppTheme.primaryDark),
              ),
              title: Text(cliente['nome'] ?? 'Cliente',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(cliente['email'] ?? 'E-mail não informado'),
            ),
          );
        },
      ),
    );
  }

  // 6. PERFIL (Com campos seguros e upload funcional)
  Widget _buildAbaPerfil(DashboardController controller) {
    final nomeEmpresaCtrl = TextEditingController(text: 'SmartLog Corp');
    final cnpjCtrl = TextEditingController(text: '00.000.000/0001-00');
    final enderecoEmpresaCtrl = TextEditingController(text: 'Av. Paulista, 1000 - São Paulo/SP');
    final telefoneCtrl = TextEditingController(text: '(11) 99999-9999');

    return StatefulBuilder(
      builder: (context, setPerfilState) {
        bool carregandoFoto = false;
        String? fotoUrlAtual = FirebaseAuth.instance.currentUser?.photoURL;

        return SingleChildScrollView(
          key: const ValueKey("PerfilView"),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Configurações da Empresa e Perfil",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryDark,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                "Gerencie as informações corporativas e sua foto de perfil.",
                style: TextStyle(fontSize: 13, color: AppTheme.statusGrey),
              ),
              const SizedBox(height: 20),

              // Card do Administrador com Foto Editável
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Stack(
                        children: [
                          CircleAvatar(
                            radius: 32,
                            backgroundColor: AppTheme.accentOrange,
                            backgroundImage: fotoUrlAtual != null && fotoUrlAtual.isNotEmpty
                                ? NetworkImage(fotoUrlAtual)
                                : null,
                            child: fotoUrlAtual == null || fotoUrlAtual.isEmpty
                                ? const Icon(Icons.admin_panel_settings, size: 32, color: Colors.white)
                                : null,
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: InkWell(
                              onTap: carregandoFoto ? null : () async {
                                final ImagePicker picker = ImagePicker();
                                final XFile? imagemSelecionada = await picker.pickImage(
                                  source: ImageSource.gallery,
                                  imageQuality: 80,
                                );

                                if (imagemSelecionada != null) {
                                  setPerfilState(() => carregandoFoto = true);
                                  try {
                                    final user = FirebaseAuth.instance.currentUser;
                                    if (user != null) {
                                      final bytes = await imagemSelecionada.readAsBytes();
                                      final storageRef = FirebaseStorage.instance
                                          .ref()
                                          .child('perfil_admin/${user.uid}.jpg');

                                      await storageRef.putData(bytes);
                                      String downloadUrl = await storageRef.getDownloadURL();

                                      await user.updatePhotoURL(downloadUrl);

                                      setPerfilState(() {
                                        fotoUrlAtual = downloadUrl;
                                        carregandoFoto = false;
                                      });

                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text("Foto de perfil atualizada com sucesso!")),
                                        );
                                      }
                                    }
                                  } catch (e) {
                                    setPerfilState(() => carregandoFoto = false);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text("Erro ao alterar foto: $e")),
                                      );
                                    }
                                  }
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: AppTheme.primaryDark,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.camera_alt,
                                  size: 14,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Administrador do Sistema",
                              style: TextStyle(fontSize: 12, color: AppTheme.statusGrey, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              FirebaseAuth.instance.currentUser?.email ?? "admin@smartlog.com",
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.primaryDark),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              "Perfil com acesso total (Master)",
                              style: TextStyle(fontSize: 12, color: AppTheme.statusGreen),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                "Dados Corporativos",
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.primaryDark),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nomeEmpresaCtrl,
                decoration: const InputDecoration(
                  labelText: "Nome da Empresa / Parceiro",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.store),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: cnpjCtrl,
                decoration: const InputDecoration(
                  labelText: "CNPJ",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: enderecoEmpresaCtrl,
                decoration: const InputDecoration(
                  labelText: "Endereço da Matriz / Centro de Distribuição",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.location_on_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: telefoneCtrl,
                decoration: const InputDecoration(
                  labelText: "Telefone de Contato / Suporte",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
              const SizedBox(height: 24),

              // Botão Salvar Dados Corporativos
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryDark,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.save),
                  label: const Text("Salvar Alterações Corporativas"),
                  onPressed: () async {
                    final idEmpresaParaSalvar = controller.empresaId ?? FirebaseAuth.instance.currentUser?.uid;

                    if (idEmpresaParaSalvar != null) {
                      await FirebaseFirestore.instance
                          .collection('empresas')
                          .doc(idEmpresaParaSalvar)
                          .set({
                        'nome': nomeEmpresaCtrl.text.trim(),
                        'cnpj': cnpjCtrl.text.trim(),
                        'endereco': enderecoEmpresaCtrl.text.trim(),
                        'telefone': telefoneCtrl.text.trim(),
                      }, SetOptions(merge: true));

                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Dados da empresa salvos com sucesso!")),
                        );
                      }
                    } else {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Erro: Nenhuma identificação de empresa encontrada.")),
                        );
                      }
                    }
                  },
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.logout),
                  label: const Text("Encerrar Sessão (Sair)"),
                  onPressed: () async {
                    await FirebaseAuth.instance.signOut();
                    if (context.mounted) {
                      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
                    }
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// Widget auxiliar renomeado para evitar conflito de escopo
class _CardDashboard extends StatelessWidget {
  final String titulo;
  final String valor;
  final IconData icone;
  final Color cor;

  const _CardDashboard(this.titulo, this.valor, this.icone, this.cor);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icone, color: cor, size: 26),
                Text(
                  valor,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              titulo,
              style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.statusGrey,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}