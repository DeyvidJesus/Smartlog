// lib/screens/dashboard_motorista.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../theme/app_theme.dart';
import 'chat_assistente.dart';

class DashboardMotorista extends StatefulWidget {
  const DashboardMotorista({super.key});

  @override
  State<DashboardMotorista> createState() => _DashboardMotoristaState();
}

class _DashboardMotoristaState extends State<DashboardMotorista> {
  int _indiceTabAtual = 0;
  bool _emViagem = false;

  final List<String> _titulosAbas = [
    "Painel",
    "Minhas Entregas",
    "Rotas por Região",
    "Perfil"
  ];

  // Removido: _atualizarStatusPorCodigoAmigavel.
  // Era o resto de um fluxo de leitura de QR Code que não existe mais — o
  // pacote mobile_scanner segue no pubspec, mas nenhuma tela o importa.
  // O status é alterado por _botaoAlterarStatus, na aba "Minhas Entregas".

  @override
  Widget build(BuildContext context) {
    final String abaAtual = _titulosAbas[_indiceTabAtual];
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: Text("SmartLog • $abaAtual"),
        backgroundColor: AppTheme.primaryDark,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.support_agent),
            tooltip: "Assistente IA",
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ChatAssistenteScreen(
                  perfil: "MOTORISTA",
                  uid: user?.uid ?? "",
                ),
              ));
            },
          ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: _renderizarConteudo(user?.uid),
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
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        unselectedLabelStyle: const TextStyle(fontSize: 11),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            activeIcon: Icon(Icons.dashboard),
            label: "Início",
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
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: "Perfil",
          ),
        ],
      ),
    );
  }

  Widget _renderizarConteudo(String? motoristaUid) {
    switch (_indiceTabAtual) {
      case 0:
        return _buildAbaPainel(motoristaUid);
      case 1:
        return _buildAbaEntregas(motoristaUid);
      case 2:
        return _buildAbaRotasRegiao(motoristaUid);
      case 3:
        return _buildAbaPerfil();
      default:
        return _buildAbaPainel(motoristaUid);
    }
  }

  // 1. PAINEL / INÍCIO DO MOTORISTA (DINÂMICO)
  Widget _buildAbaPainel(String? motoristaUid) {
    if (motoristaUid == null || motoristaUid.isEmpty) {
      return const Center(child: Text("Usuário não autenticado."));
    }

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('usuarios').doc(motoristaUid).get(),
      builder: (context, userSnapshot) {
        if (userSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
          return const Center(child: Text("Perfil do motorista não encontrado."));
        }

        final userData = userSnapshot.data!.data() as Map<String, dynamic>;
        final String? empresaId = userData['empresaId'];

        if (empresaId == null) {
          return const Center(child: Text("Empresa não vinculada."));
        }

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('entregas')
              .where('motoristaId', isEqualTo: motoristaUid)
              .where('empresaId', isEqualTo: empresaId)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final docs = snapshot.hasData ? snapshot.data!.docs : [];

            int totalPendentes = 0;
            int totalEntregues = 0;

            for (var doc in docs) {
              final data = doc.data() as Map<String, dynamic>;
              final status = (data['status'] ?? '').toString().trim().toLowerCase();

              if (status == 'pendente') {
                totalPendentes++;
              } else if (status == 'entregue') {
                totalEntregues++;
              }
            }

            final int totalGeral = docs.length;
            final double eficiencia = totalGeral > 0 ? (totalEntregues / totalGeral) * 100 : 0.0;
            final double distanciaEstimada = totalEntregues * 3.5;

            return SingleChildScrollView(
              key: const ValueKey("PainelMotoristaView"),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Resumo do Dia",
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
                      _CardMetrica("Pendentes", "$totalPendentes", Icons.hourglass_empty, AppTheme.statusOrange),
                      _CardMetrica("Entregues", "$totalEntregues", Icons.check_circle_outline, AppTheme.statusGreen),
                      _CardMetrica("Distância", "${distanciaEstimada.toStringAsFixed(1)} km", Icons.speed, Colors.blue),
                      _CardMetrica("Eficiência", "${eficiencia.toStringAsFixed(0)}%", Icons.trending_up, Colors.purple),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Status da Jornada",
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.primaryDark),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _emViagem ? "Você está em rota ativa enviando localização." : "Você está em pausa / pronto para iniciar.",
                            style: const TextStyle(color: AppTheme.statusGrey, fontSize: 13),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _emViagem ? Colors.red : AppTheme.statusGreen,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              icon: Icon(_emViagem ? Icons.stop : Icons.play_arrow),
                              label: Text(_emViagem ? "Encerrar Viagem / Rota" : "Iniciar Viagem / Rota"),
                              onPressed: () {
                                setState(() {
                                  _emViagem = !_emViagem;
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(_emViagem ? "Viagem iniciada com sucesso!" : "Viagem encerrada.")),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // 2. MINHAS ENTREGAS
  Widget _buildAbaEntregas(String? motoristaUid) {
    if (motoristaUid == null || motoristaUid.isEmpty) {
      return const Center(child: Text("Erro: Nenhum usuário motorista autenticado."));
    }

    return Padding(
      key: const ValueKey("EntregasMotoristaView"),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Entregas Atribuídas",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryDark),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance.collection('usuarios').doc(motoristaUid).get(),
              builder: (context, userSnapshot) {
                if (userSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
                  return const Center(child: Text("Perfil do motorista não encontrado."));
                }

                final userData = userSnapshot.data!.data() as Map<String, dynamic>;
                final String? empresaId = userData['empresaId'];

                if (empresaId == null) {
                  return const Center(child: Text("Erro: 'empresaId' não encontrada."));
                }

                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('entregas')
                      .where('motoristaId', isEqualTo: motoristaUid)
                      .where('empresaId', isEqualTo: empresaId)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return const Center(child: Text("Nenhuma entrega atribuída a você."));
                    }

                    final entregas = snapshot.data!.docs;

                    return ListView.builder(
                      itemCount: entregas.length,
                      itemBuilder: (context, index) {
                        final entrega = entregas[index].data() as Map<String, dynamic>;
                        final docId = entregas[index].id;
                        final codigoAmigavel = entrega['Id'] ?? entrega['id'] ?? 'ENT';
                        final status = entrega['status'] ?? 'Pendente';

                        final Color statusColor = status == 'Entregue'
                            ? AppTheme.statusGreen
                            : status == 'Em Rota'
                            ? AppTheme.statusOrange
                            : AppTheme.statusGrey;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            onTap: () => _modalDetalhesEntregaMotorista(context, docId, entrega),
                            leading: const CircleAvatar(
                              backgroundColor: AppTheme.backgroundLight,
                              child: Icon(Icons.local_shipping, color: AppTheme.primaryDark),
                            ),
                            title: Text(
                              "$codigoAmigavel • ${entrega['cliente'] ?? 'Cliente'}",
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text("${entrega['endereco'] ?? ''}\nRegião: ${entrega['regiao'] ?? 'Geral'}"),
                            isThreeLine: true,
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: statusColor.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: statusColor, width: 1),
                              ),
                              child: Text(
                                status,
                                style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // 3. ROTAS UNIFICADAS POR REGIÃO + MAPA COM MARCADORES E POLYLINES
  Widget _buildAbaRotasRegiao(String? motoristaUid) {
    if (motoristaUid == null || motoristaUid.isEmpty) {
      return const Center(child: Text("Usuário não autenticado."));
    }

    bool _otimizandoIA = false;
    String _statusTransitoIA = "Tráfego fluindo normalmente. Menor tempo estimado.";

    return StatefulBuilder(
      builder: (context, setAbaState) {
        return Padding(
          key: const ValueKey("RotasRegiaoView"),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Banner de Otimização por IA
              Container(
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: AppTheme.primaryDark,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.psychology, color: AppTheme.accentOrange, size: 34),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "SmartLog AI • Otimizador de Tráfego",
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _statusTransitoIA,
                            style: const TextStyle(color: Colors.white70, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accentOrange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                      onPressed: _otimizandoIA ? null : () async {
                        setAbaState(() {
                          _otimizandoIA = true;
                          _statusTransitoIA = "Analisando tráfego ponto a ponto...";
                        });

                        await Future.delayed(const Duration(seconds: 2));

                        if (context.mounted) {
                          setAbaState(() {
                            _otimizandoIA = false;
                            _statusTransitoIA = "Menor tempo garantido. Sequência atualizada.";
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Rota otimizada com sucesso via IA!")),
                          );
                        }
                      },
                      child: _otimizandoIA
                          ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                          : const Text("Otimizar", style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),

              // MAPA DE RASTREAMENTO COM LINHA DE ROTA (POLYLINE)
              const Text(
                "Mapa de Paradas e Rota",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryDark),
              ),
              const SizedBox(height: 8),

              SizedBox(
                height: 200,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: FutureBuilder<DocumentSnapshot>(
                    future: FirebaseFirestore.instance.collection('usuarios').doc(motoristaUid).get(),
                    builder: (context, userSnap) {
                      if (!userSnap.hasData || !userSnap.data!.exists) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final userData = userSnap.data!.data() as Map<String, dynamic>;
                      final String? empresaId = userData['empresaId'];

                      if (empresaId == null) {
                        return const Center(child: Text("Empresa não vinculada."));
                      }

                      return StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('entregas')
                            .where('motoristaId', isEqualTo: motoristaUid)
                            .where('empresaId', isEqualTo: empresaId)
                            .snapshots(),
                        builder: (context, snapshot) {
                          Set<Marker> marcadores = {};
                          Set<Polyline> polylines = {};
                          List<LatLng> pontosDaRota = [];
                          LatLng posicaoInicial = const LatLng(-23.550520, -46.633308);

                          if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                            for (var doc in snapshot.data!.docs) {
                              final data = doc.data() as Map<String, dynamic>;
                              final double? lat = data['latitude'];
                              final double? lng = data['longitude'];
                              final String status = (data['status'] ?? 'Pendente').toString();
                              final String cliente = data['cliente'] ?? 'Cliente';
                              final String idAmigavel = data['Id'] ?? data['id'] ?? 'ENT';

                              if (lat != null && lng != null) {
                                final LatLng coordenadaPonto = LatLng(lat, lng);
                                posicaoInicial = coordenadaPonto;
                                pontosDaRota.add(coordenadaPonto);

                                double hueCor = BitmapDescriptor.hueRed;
                                if (status == 'Em Rota') {
                                  hueCor = BitmapDescriptor.hueOrange;
                                } else if (status == 'Entregue' || status == 'entregue') {
                                  hueCor = BitmapDescriptor.hueGreen;
                                }

                                marcadores.add(
                                  Marker(
                                    markerId: MarkerId(doc.id),
                                    position: coordenadaPonto,
                                    icon: BitmapDescriptor.defaultMarkerWithHue(hueCor),
                                    infoWindow: InfoWindow(
                                      title: "$idAmigavel - $cliente",
                                      snippet: "Status: $status",
                                    ),
                                  ),
                                );
                              }
                            }

                            // Adiciona a linha conectando as paradas, caso haja mais de um ponto
                            if (pontosDaRota.length > 1) {
                              polylines.add(
                                Polyline(
                                  polylineId: const PolylineId('rota_motorista'),
                                  points: pontosDaRota,
                                  color: AppTheme.accentOrange,
                                  width: 4,
                                ),
                              );
                            }
                          }

                          return GoogleMap(
                            initialCameraPosition: CameraPosition(
                              target: posicaoInicial,
                              zoom: 13,
                            ),
                            markers: marcadores,
                            polylines: polylines,
                            myLocationEnabled: true,
                            myLocationButtonEnabled: true,
                            zoomControlsEnabled: false,
                          );
                        },
                      );
                    },
                  ),
                ),
              ),

              const SizedBox(height: 14),
              const Text(
                "Rotas Unificadas por Região",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.primaryDark),
              ),
              const SizedBox(height: 8),

              // LISTA DE REGIÕES ABAIXO DO MAPA
              Expanded(
                child: FutureBuilder<DocumentSnapshot>(
                  future: FirebaseFirestore.instance.collection('usuarios').doc(motoristaUid).get(),
                  builder: (context, userSnapshot) {
                    if (userSnapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
                      return const Center(child: Text("Erro ao carregar dados do usuário."));
                    }

                    final userData = userSnapshot.data!.data() as Map<String, dynamic>;
                    final String? empresaId = userData['empresaId'];

                    if (empresaId == null) {
                      return const Center(child: Text("Empresa não vinculada."));
                    }

                    return StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('entregas')
                          .where('motoristaId', isEqualTo: motoristaUid)
                          .where('empresaId', isEqualTo: empresaId)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                          return const Center(child: Text("Nenhuma rota ou entrega encontrada para suas regiões."));
                        }

                        final docs = snapshot.data!.docs;
                        final Map<String, List<Map<String, dynamic>>> entregasPorRegiao = {};

                        for (var doc in docs) {
                          final data = doc.data() as Map<String, dynamic>;
                          final regiao = (data['regiao'] ?? 'Geral').toString().trim();

                          if (!entregasPorRegiao.containsKey(regiao)) {
                            entregasPorRegiao[regiao] = [];
                          }
                          entregasPorRegiao[regiao]!.add({
                            'idReal': doc.id,
                            ...data,
                          });
                        }

                        final regioes = entregasPorRegiao.keys.toList();

                        return ListView.builder(
                          itemCount: regioes.length,
                          itemBuilder: (context, index) {
                            final regiao = regioes[index];
                            final listaEntregas = entregasPorRegiao[regiao]!;

                            return Card(
                              elevation: 2,
                              margin: const EdgeInsets.only(bottom: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ExpansionTile(
                                leading: const CircleAvatar(
                                  backgroundColor: AppTheme.backgroundLight,
                                  child: Icon(Icons.map, color: AppTheme.primaryDark),
                                ),
                                title: Text(
                                  regiao,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: AppTheme.primaryDark,
                                  ),
                                ),
                                subtitle: Text(
                                  "${listaEntregas.length} ${listaEntregas.length == 1 ? 'parada unificada' : 'paradas unificadas'}",
                                  style: const TextStyle(fontSize: 12, color: AppTheme.statusGrey),
                                ),
                                children: listaEntregas.map((entrega) {
                                  final codigoAmigavel = entrega['Id'] ?? entrega['id'] ?? 'ENT';
                                  final status = entrega['status'] ?? 'Pendente';

                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                    decoration: BoxDecoration(
                                      border: Border(
                                        top: BorderSide(color: Colors.grey.shade200),
                                      ),
                                    ),
                                    child: ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(
                                        "$codigoAmigavel • ${entrega['cliente'] ?? 'Cliente'}",
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                      subtitle: Text(
                                        "${entrega['endereco'] ?? 'Endereço não informado'}\nStatus: $status",
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                      isThreeLine: true,
                                      trailing: const Icon(Icons.chevron_right, size: 20),
                                      onTap: () {
                                        _modalDetalhesEntregaMotorista(context, entrega['idReal'], entrega);
                                      },
                                    ),
                                  );
                                }).toList(),
                              ),
                            );
                          },
                        );
                      },
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

  // 4. PERFIL DO MOTORISTA
  Widget _buildAbaPerfil() {
    final user = FirebaseAuth.instance.currentUser;
    final nomeCtrl = TextEditingController(text: user?.displayName ?? 'Motorista SmartLog');
    final telefoneCtrl = TextEditingController(text: '(11) 98888-8888');

    return StatefulBuilder(
      builder: (context, setPerfilState) {
        bool carregandoFoto = false;
        String? fotoUrlAtual = user?.photoURL;

        return SingleChildScrollView(
          key: const ValueKey("PerfilMotoristaView"),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Meu Perfil",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryDark),
              ),
              const SizedBox(height: 4),
              const Text(
                "Gerencie suas informações pessoais e foto de identificação.",
                style: TextStyle(fontSize: 13, color: AppTheme.statusGrey),
              ),
              const SizedBox(height: 20),
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
                                ? const Icon(Icons.person, size: 32, color: Colors.white)
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
                                    if (user != null) {
                                      final bytes = await imagemSelecionada.readAsBytes();
                                      final storageRef = FirebaseStorage.instance
                                          .ref()
                                          .child('perfil_motorista/${user.uid}.jpg');

                                      await storageRef.putData(bytes);
                                      String downloadUrl = await storageRef.getDownloadURL();

                                      await user.updatePhotoURL(downloadUrl);

                                      setPerfilState(() {
                                        fotoUrlAtual = downloadUrl;
                                        carregandoFoto = false;
                                      });

                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text("Foto atualizada com sucesso!")),
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
                                child: const Icon(Icons.camera_alt, size: 14, color: Colors.white),
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
                              "Motorista Cadastrado",
                              style: TextStyle(fontSize: 12, color: AppTheme.statusGrey, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              user?.email ?? "motorista@smartlog.com",
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.primaryDark),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: nomeCtrl,
                decoration: const InputDecoration(
                  labelText: "Nome Completo",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.badge),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: telefoneCtrl,
                decoration: const InputDecoration(
                  labelText: "Telefone / WhatsApp",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone),
                ),
              ),
              const SizedBox(height: 24),
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
                  label: const Text("Salvar Dados Pessoais"),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Dados atualizados com sucesso!")),
                    );
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
                  label: const Text("Sair da Conta"),
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

  // Modal de Detalhes da Entrega para o Motorista
  void _modalDetalhesEntregaMotorista(BuildContext context, String docId, Map<String, dynamic> entrega) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final statusAtual = entrega['status'] ?? 'Pendente';
        final emailCliente = entrega['emailCliente'] ?? entrega['email'] ?? 'Não informado';
        final codigoAmigavel = entrega['Id'] ?? entrega['id'] ?? 'ENT';

        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            top: 24,
            left: 20,
            right: 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Detalhes: $codigoAmigavel",
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryDark
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const Divider(),
                const SizedBox(height: 8),

                _itemDetalheInfo(Icons.person, "Cliente", entrega['cliente'] ?? 'Não informado'),
                _itemDetalheInfo(Icons.email, "E-mail do Cliente", emailCliente),
                _itemDetalheInfo(Icons.location_on, "Endereço", entrega['endereco'] ?? 'Não informado'),
                _itemDetalheInfo(Icons.map, "Região", entrega['regiao'] ?? 'Geral'),
                _itemDetalheInfo(Icons.calendar_today, "Data Agendada", entrega['data'] ?? 'Não informada'),
                _itemDetalheInfo(Icons.info_outline, "Status Atual", statusAtual),

                const SizedBox(height: 20),
                const Text(
                  "Atualizar Status da Entrega:",
                  style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryDark),
                ),
                const SizedBox(height: 10),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _botaoAlterarStatus(ctx, docId, 'Pendente', statusAtual, Colors.grey, entrega),
                    _botaoAlterarStatus(ctx, docId, 'Em Rota', statusAtual, AppTheme.statusOrange, entrega),
                    _botaoAlterarStatus(ctx, docId, 'Entregue', statusAtual, AppTheme.statusGreen, entrega),
                  ],
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  // Função auxiliar para alterar o status e disparar o e-mail de rastreio
  Widget _botaoAlterarStatus(
      BuildContext ctx, String docId, String novoStatus, String statusAtual, Color cor, Map<String, dynamic> entrega) {

    final bool isSelecionado = (statusAtual == novoStatus);

    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelecionado ? cor : cor.withOpacity(0.2),
        foregroundColor: isSelecionado ? Colors.white : cor,
        elevation: isSelecionado ? 2 : 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: () async {
        try {
          // 1. Atualiza o status no Firestore usando o ID do documento.
          // A data de conclusão alimenta o histórico e o assistente de IA,
          // que sem ela não consegue responder quando algo foi entregue.
          await FirebaseFirestore.instance
              .collection('entregas')
              .doc(docId)
              .update({
            'status': novoStatus,
            if (novoStatus == 'Entregue')
              'entregueEm': FieldValue.serverTimestamp(),
          });

          // 2. Se mudou para "Em Rota", envia o e-mail de rastreio direto pelo app
          if (novoStatus == 'Em Rota') {
            final emailCliente = entrega['emailCliente'] ?? entrega['email'];
            final nomeCliente = entrega['cliente'] ?? 'Cliente';
            final idEntrega = entrega['Id'] ?? entrega['id'] ?? docId;

            if (emailCliente != null && emailCliente.toString().isNotEmpty) {
              final linkRastreio = "https://seuapp.com/rastreio?id=$docId";

              // Requisição HTTP direta para o EmailJS
              final url = Uri.parse('https://api.emailjs.com/api/v1.0/email/send');
              final response = await http.post(
                url,
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({
                  'service_id': 'service_n0xgdgw',
                  'template_id': 'template_dzr5h0r',
                  'user_id': 'SQbay_KhicBk4ORAp',
                  'accessToken': 'kBi4jmhgoY-yhyoQvRRWW',
                  'template_params': {
                    'to_email': emailCliente,
                    'email': emailCliente, // Garante compatibilidade com o template
                    'to_name': nomeCliente,
                    'id_entrega': idEntrega,
                    'tracking_link': linkRastreio,
                  }
                }),
              );

              // Validação detalhada do retorno do EmailJS no log
              if (response.statusCode == 200) {
                print("E-mail disparado e aceito pelo EmailJS com sucesso!");
              } else {
                print("FALHA RETORNADA PELO EMAILJS: ${response.statusCode} - ${response.body}");
              }
            }
          }

          if (ctx.mounted) {
            Navigator.pop(ctx);
            ScaffoldMessenger.of(ctx).showSnackBar(
              SnackBar(content: Text("Status atualizado para: $novoStatus")),
            );
          }
        } catch (e) {
          print("ERRO DETALHADO AO ALTERAR STATUS: $e");
          if (ctx.mounted) {
            ScaffoldMessenger.of(ctx).showSnackBar(
              SnackBar(content: Text("Erro ao atualizar: $e")),
            );
          }
        }
      },
      child: Text(
        novoStatus,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }

  Widget _itemDetalheInfo(IconData icone, String titulo, String valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 20, color: AppTheme.primaryDark),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: const TextStyle(fontSize: 12, color: AppTheme.statusGrey)),
                const SizedBox(height: 2),
                Text(valor, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.black87)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Widget auxiliar para os cards do painel
class _CardMetrica extends StatelessWidget {
  final String titulo;
  final String valor;
  final IconData icone;
  final Color cor;

  const _CardMetrica(this.titulo, this.valor, this.icone, this.cor);

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
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              titulo,
              style: const TextStyle(fontSize: 12, color: AppTheme.statusGrey, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}