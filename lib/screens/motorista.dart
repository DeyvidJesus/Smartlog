import '../widgets/driver_road_map.dart';
import '../widgets/confirm_delivery.dart';
import '../widgets/driver_distance_card.dart';
import '../widgets/voice_assistant.dart';
import '../services/api_service.dart';
// lib/screens/dashboard_motorista.dart
import 'dart:math' as math;

import '../services/location_service.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

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

  final LocationService _locationService = LocationService();

  String? _rotaAtivaId;
  bool _iniciandoViagem = false;
  bool _salvandoPerfil = false;
  bool _carregandoFoto = false;
  String? _fotoUrlAtual;
  late final TextEditingController _nomeCtrl;
  late final TextEditingController _telefoneCtrl;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _nomeCtrl = TextEditingController(text: user?.displayName ?? '');
    _telefoneCtrl = TextEditingController();
    _fotoUrlAtual = user?.photoURL;
    _carregarPerfil();
  }

  Future<void> _carregarPerfil() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('usuarios').doc(user.uid).get();
      if (!mounted || !doc.exists) return;
      final data = doc.data() ?? <String, dynamic>{};
      _nomeCtrl.text = (data['nome'] ?? user.displayName ?? '').toString();
      _telefoneCtrl.text = (data['telefone'] ?? '').toString();
      final foto = (data['fotoUrl'] ?? user.photoURL)?.toString();
      setState(() => _fotoUrlAtual = foto);
    } catch (e) {
      debugPrint('Não foi possível carregar o perfil: $e');
    }
  }

  Future<void> _salvarPerfil() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _mostrarMensagem('Usuário não autenticado.');
      return;
    }
    setState(() => _salvandoPerfil = true);
    try {
      await FirebaseFirestore.instance.collection('usuarios').doc(user.uid).set({
        'nome': _nomeCtrl.text.trim(),
        'telefone': _telefoneCtrl.text.trim(),
        'fotoUrl': _fotoUrlAtual,
        'email': user.email,
        'atualizadoEm': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) _mostrarMensagem('Dados pessoais salvos.');
    } catch (e) {
      if (mounted) _mostrarMensagem('Erro ao salvar perfil: $e');
    } finally {
      if (mounted) setState(() => _salvandoPerfil = false);
    }
  }

  void _mostrarMensagem(String mensagem) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensagem)));
  }

  @override
  void dispose() {
    _locationService.pararRastreamento();
    _nomeCtrl.dispose();
    _telefoneCtrl.dispose();
    super.dispose();
  }

  // Removido: _atualizarStatusPorCodigoAmigavel.
  // Era o resto de um fluxo de leitura de QR Code que não existe mais — o
  // pacote mobile_scanner segue no pubspec, mas nenhuma tela o importa.
  // O status é alterado por _botaoAlterarStatus, na aba "Minhas Entregas".


  Future<void> _alternarViagem(String? motoristaUid) async {
    if (motoristaUid == null || motoristaUid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Motorista não autenticado.')),
      );
      return;
    }

    if (_iniciandoViagem) return;

    setState(() => _iniciandoViagem = true);

    try {
      // Se já estiver em viagem, interrompe o GPS e pausa a rota.
      if (_emViagem) {
        await _locationService.pararRastreamento();

        final rotaId = _rotaAtivaId;
        if (rotaId != null) {
          await FirebaseFirestore.instance
              .collection('rotas')
              .doc(rotaId)
              .update({
            'status': 'Pausada',
            'pausadaEm': FieldValue.serverTimestamp(),
          });
        }

        if (!mounted) return;

        setState(() {
          _emViagem = false;
          _rotaAtivaId = null;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rastreamento GPS pausado.')),
        );
        return;
      }

      // Descobre a empresa à qual o motorista pertence.
      final usuario = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(motoristaUid)
          .get();

      final empresaId = usuario.data()?['empresaId']?.toString();

      if (empresaId == null || empresaId.isEmpty) {
        throw Exception('Empresa do motorista não encontrada.');
      }

      // Busca as rotas deste motorista nesta empresa.
      final resultado = await FirebaseFirestore.instance
          .collection('rotas')
          .where('motoristaId', isEqualTo: motoristaUid)
          .where('empresaId', isEqualTo: empresaId)
          .get();

      final rotasDisponiveis = resultado.docs.where((doc) {
        final status =
        (doc.data()['status'] ?? '').toString().trim().toLowerCase();

        return status == 'pendente' ||
            status == 'em rota' ||
            status == 'pausada';
      }).toList();

      if (rotasDisponiveis.isEmpty) {
        throw Exception(
          'Nenhuma rota pendente ou pausada foi encontrada para você.',
        );
      }

      // Prioriza uma rota que já esteja em andamento.
      final rotasEmAndamento = rotasDisponiveis.where((doc) {
        return (doc.data()['status'] ?? '')
            .toString()
            .toLowerCase() ==
            'em rota';
      }).toList();

      final List<QueryDocumentSnapshot<Map<String, dynamic>>> candidatas =
      rotasEmAndamento.isNotEmpty
          ? rotasEmAndamento
          : rotasDisponiveis;

      // Não inicia uma rota arbitrária se houver várias candidatas.
      if (candidatas.length != 1) {
        throw Exception(
          'Você possui mais de uma rota disponível. '
              'É necessário selecionar a rota antes de iniciar o GPS.',
        );
      }

      final rotaDoc = candidatas.first;
      final rotaId = rotaDoc.id;

      // Inicia o GPS. O serviço grava localizacaoAtual no documento.
      await _locationService.iniciarRastreamento(
        rotaId: rotaId,
        motoristaId: motoristaUid,
      );

      try {
        await rotaDoc.reference.update({
          'status': 'Em Rota',
          'iniciadaEm': FieldValue.serverTimestamp(),
        });
      } catch (_) {
        await _locationService.pararRastreamento();
        rethrow;
      }

      if (!mounted) {
        await _locationService.pararRastreamento();
        return;
      }

      setState(() {
        _emViagem = true;
        _rotaAtivaId = rotaId;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Viagem iniciada. Rastreamento GPS ativo.'),
        ),
      );
    } catch (e) {
      await _locationService.pararRastreamento();
      if (mounted) {
        setState(() {
          _emViagem = false;
          _rotaAtivaId = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível concluir a ação da viagem: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _iniciandoViagem = false);
      }
    }
  }


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
          const VoiceAssistantButton(),
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

  Future<void> _otimizarRotaPorProximidade(String motoristaUid) async {
    try {
      final usuario = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(motoristaUid)
          .get();
      final empresaId = usuario.data()?['empresaId']?.toString();
      if (empresaId == null || empresaId.isEmpty) {
        throw Exception('Empresa do motorista não encontrada.');
      }

      final rotasSnap = await FirebaseFirestore.instance
          .collection('rotas')
          .where('motoristaId', isEqualTo: motoristaUid)
          .where('empresaId', isEqualTo: empresaId)
          .get();
      final candidatas = rotasSnap.docs.where((doc) {
        final status = (doc.data()['status'] ?? '').toString().trim().toLowerCase();
        return status == 'pendente' || status == 'em rota' || status == 'pausada';
      }).toList();
      final emAndamento = candidatas.where((doc) =>
      (doc.data()['status'] ?? '').toString().trim().toLowerCase() == 'em rota').toList();
      final rotasParaUsar = emAndamento.isNotEmpty ? emAndamento : candidatas;
      if (rotasParaUsar.length != 1) {
        throw Exception(rotasParaUsar.isEmpty
            ? 'Nenhuma rota pendente, ativa ou pausada foi encontrada.'
            : 'Há mais de uma rota disponível. Selecione uma rota antes de otimizar.');
      }
      final rotaDoc = rotasParaUsar.first;

      final entregasSnap = await FirebaseFirestore.instance
          .collection('entregas')
          .where('motoristaId', isEqualTo: motoristaUid)
          .where('empresaId', isEqualTo: empresaId)
          .get();

      final idsDaRota = <String>{};
      final enderecosExistentes = rotaDoc.data()['enderecos'];
      if (enderecosExistentes is List) {
        for (final item in enderecosExistentes) {
          if (item is Map && item['entregaId'] != null) {
            idsDaRota.add(item['entregaId'].toString());
          }
        }
      }

      final idsDeDocumentos = entregasSnap.docs.map((doc) => doc.id).toSet();
      final idsDaRotaQueExistem = idsDaRota.intersection(idsDeDocumentos);
      final paradas = <Map<String, dynamic>>[];
      for (final doc in entregasSnap.docs) {
        // Só restringe à lista da rota quando entregaId realmente corresponde
        // a IDs de documentos do Firestore; alguns cadastros antigos usam código amigável.
        if (idsDaRotaQueExistem.isNotEmpty && !idsDaRotaQueExistem.contains(doc.id)) continue;
        final data = doc.data();
        final status = (data['status'] ?? 'Pendente').toString().trim().toLowerCase();
        if (status == 'entregue' || status == 'cancelada' || status == 'cancelado') continue;
        final latValue = data['latitude'];
        final lngValue = data['longitude'];
        if (latValue is! num || lngValue is! num) continue;
        final lat = latValue.toDouble();
        final lng = lngValue.toDouble();
        if (lat < -90 || lat > 90 || lng < -180 || lng > 180) continue;
        paradas.add({
          'docId': doc.id,
          'cliente': (data['cliente'] ?? 'Cliente').toString(),
          'endereco': (data['endereco'] ?? '').toString(),
          'latitude': lat,
          'longitude': lng,
          'status': (data['status'] ?? 'Pendente').toString(),
          'codigo': (data['Id'] ?? data['id'] ?? doc.id).toString(),
        });
      }
      if (paradas.isEmpty) {
        throw Exception('Nenhuma entrega tem latitude e longitude válidas. Geocodifique os endereços primeiro.');
      }

      final rotaData = rotaDoc.data();
      final localizacao = rotaData['localizacaoAtual'];
      double? latAtual;
      double? lngAtual;
      if (localizacao is Map) {
        final latValue = localizacao['latitude'];
        final lngValue = localizacao['longitude'];
        if (latValue is num && lngValue is num) {
          latAtual = latValue.toDouble();
          lngAtual = lngValue.toDouble();
        }
      }

      double distancia(double lat1, double lon1, double lat2, double lon2) {
        const raioTerraKm = 6371.0;
        final dLat = (lat2 - lat1) * math.pi / 180;
        final dLon = (lon2 - lon1) * math.pi / 180;
        final a = math.pow(math.sin(dLat / 2), 2) +
            math.cos(lat1 * math.pi / 180) *
                math.cos(lat2 * math.pi / 180) *
                math.pow(math.sin(dLon / 2), 2);
        final aSeguro = a.clamp(0.0, 1.0).toDouble();
        return raioTerraKm * 2 * math.atan2(math.sqrt(aSeguro), math.sqrt(1 - aSeguro));
      }

      // Heurística gulosa: escolhe a próxima parada mais próxima do ponto atual.
      // Não considera trânsito nem garante o menor percurso global.
      final restantes = List<Map<String, dynamic>>.from(paradas);
      final ordenadas = <Map<String, dynamic>>[];
      double? latReferencia = latAtual;
      double? lngReferencia = lngAtual;
      while (restantes.isNotEmpty) {
        int indiceEscolhido = 0;
        if (latReferencia != null && lngReferencia != null) {
          var menorDistancia = double.infinity;
          for (var i = 0; i < restantes.length; i++) {
            final parada = restantes[i];
            final d = distancia(latReferencia, lngReferencia,
                parada['latitude'] as double, parada['longitude'] as double);
            if (d < menorDistancia) {
              menorDistancia = d;
              indiceEscolhido = i;
            }
          }
        }
        final escolhida = restantes.removeAt(indiceEscolhido);
        ordenadas.add(escolhida);
        latReferencia = escolhida['latitude'] as double;
        lngReferencia = escolhida['longitude'] as double;
      }

      final enderecosOrdenados = ordenadas.map((parada) => <String, dynamic>{
        'cliente': parada['cliente'],
        'endereco': parada['endereco'],
        'entregaId': parada['docId'],
        'latitude': parada['latitude'],
        'longitude': parada['longitude'],
      }).toList();

      final batch = FirebaseFirestore.instance.batch();
      for (var i = 0; i < ordenadas.length; i++) {
        batch.update(
          FirebaseFirestore.instance.collection('entregas').doc(ordenadas[i]['docId'] as String),
          {'ordemEntrega': i + 1},
        );
      }
      batch.update(rotaDoc.reference, {
        'enderecos': enderecosOrdenados,
        'totalEnderecos': enderecosOrdenados.length,
        'criterioOrdenacao': 'proximidade_geografica',
        'otimizadaEm': FieldValue.serverTimestamp(),
      });
      await batch.commit();
      if (mounted) {
        _mostrarMensagem('Paradas reordenadas por proximidade geográfica. O cálculo não considera trânsito.');
      }
    } catch (e) {
      if (mounted) _mostrarMensagem('Não foi possível ordenar a rota: $e');
    }
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
      return const Center(
        child: Text('Usuário não autenticado.'),
      );
    }

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('usuarios')
          .doc(motoristaUid)
          .get(),
      builder: (context, userSnapshot) {
        if (userSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (userSnapshot.hasError) {
          return const Center(
            child: Text('Erro ao carregar o perfil do motorista.'),
          );
        }

        if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
          return const Center(
            child: Text('Perfil do motorista não encontrado.'),
          );
        }

        final userData = userSnapshot.data!.data();

        if (userData == null) {
          return const Center(
            child: Text('Não foi possível carregar os dados do motorista.'),
          );
        }

        final String empresaId =
        (userData['empresaId'] ?? '').toString().trim();

        if (empresaId.isEmpty) {
          return const Center(
            child: Text('Empresa não vinculada.'),
          );
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('entregas')
              .where('motoristaId', isEqualTo: motoristaUid)
              .where('empresaId', isEqualTo: empresaId)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return const Center(
                child: Text('Erro ao carregar as entregas.'),
              );
            }

            final docs = snapshot.data?.docs ?? [];

            int totalPendentes = 0;
            int totalEntregues = 0;

            for (final doc in docs) {
              final data = doc.data();
              final status = (data['status'] ?? '')
                  .toString()
                  .trim()
                  .toLowerCase();

              if (status == 'pendente') {
                totalPendentes++;
              } else if (status == 'entregue') {
                totalEntregues++;
              }
            }

            final int totalGeral = docs.length;
            final double eficiencia = totalGeral > 0
                ? (totalEntregues / totalGeral) * 100
                : 0.0;

            final bool telaAmpla =
                MediaQuery.of(context).size.width >= 600;

            return SingleChildScrollView(
              key: const ValueKey('PainelMotoristaView'),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryDark,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.local_shipping_rounded,
                          color: AppTheme.accentOrange,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Meu painel',
                              style: TextStyle(
                                fontSize: 23,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.primaryDark,
                              ),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'Acompanhe seu desempenho de entregas.',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.statusGrey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  GridView.count(
                    crossAxisCount: telaAmpla ? 4 : 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    childAspectRatio: telaAmpla ? 1.0 : 0.9,
                    children: [
                      _CardMetrica(
                        'Pendentes',
                        '$totalPendentes',
                        Icons.hourglass_empty_rounded,
                        AppTheme.statusOrange,
                      ),
                      _CardMetrica(
                        'Entregues',
                        '$totalEntregues',
                        Icons.check_circle_outline_rounded,
                        AppTheme.statusGreen,
                      ),
                      DriverDistanceCard(driverId: motoristaUid!, tenant: empresaId,
                        deliveries: docs.map((d) => {...d.data(), 'docId': d.id}).toList()),
                      _CardMetrica(
                        'Eficiência',
                        '${eficiencia.toStringAsFixed(0)}%',
                        Icons.trending_up_rounded,
                        Colors.purple,
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: Colors.grey.shade200,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.my_location_rounded,
                                color: AppTheme.primaryDark,
                                size: 22,
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Status da Jornada',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.primaryDark,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _emViagem
                                ? 'Você está em rota ativa enviando localização.'
                                : 'Você está em pausa ou pronto para iniciar.',
                            style: const TextStyle(
                              color: AppTheme.statusGrey,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _emViagem
                                    ? Colors.red
                                    : AppTheme.statusGreen,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              icon: _iniciandoViagem
                                  ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                                  : Icon(
                                _emViagem
                                    ? Icons.stop_rounded
                                    : Icons.play_arrow_rounded,
                              ),
                              label: Text(
                                _emViagem
                                    ? 'Pausar viagem e GPS'
                                    : 'Iniciar viagem e compartilhar GPS',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                              onPressed: _iniciandoViagem
                                  ? null
                                  : () => _alternarViagem(motoristaUid),
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
                final String? empresaId = userData['empresaId']?.toString();

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

    return StatefulBuilder(
      builder: (context, setAbaState) {
        return Padding(
          key: const ValueKey("RotasRegiaoView"),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: AppTheme.primaryDark,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.route, color: AppTheme.accentOrange, size: 30),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Ordena as paradas pela proximidade geográfica. Requer latitude e longitude nas entregas; não considera trânsito nem garante a menor rota global.',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accentOrange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                      onPressed: () => _otimizarRotaPorProximidade(motoristaUid),
                      child: const Text('Ordenar', style: TextStyle(fontSize: 12)),
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
                height: 360,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: FutureBuilder<DocumentSnapshot>(
                    future: FirebaseFirestore.instance.collection('usuarios').doc(motoristaUid).get(),
                    builder: (context, userSnap) {
                      if (!userSnap.hasData || !userSnap.data!.exists) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final userData = userSnap.data!.data() as Map<String, dynamic>;
                      final String? empresaId = userData['empresaId']?.toString();

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
                          if (snapshot.hasError) return const Center(child: Text('Não foi possível consultar as paradas.'));
                          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                          return DriverRoadMap(
                            driverId: motoristaUid,
                            tenant: empresaId,
                            deliveries: snapshot.data!.docs.map((doc) => {
                              ...doc.data() as Map<String,dynamic>, 'docId': doc.id,
                            }).toList(),
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
                    final String? empresaId = userData['empresaId']?.toString();

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

    return SingleChildScrollView(
      key: const ValueKey('PerfilMotoristaView'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Meu Perfil', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryDark)),
          const SizedBox(height: 4),
          const Text('Gerencie suas informações pessoais e foto de identificação.', style: TextStyle(fontSize: 13, color: AppTheme.statusGrey)),
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
                        backgroundImage: _fotoUrlAtual != null && _fotoUrlAtual!.isNotEmpty ? NetworkImage(_fotoUrlAtual!) : null,
                        child: _fotoUrlAtual == null || _fotoUrlAtual!.isEmpty ? const Icon(Icons.person, size: 32, color: Colors.white) : null,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: InkWell(
                          onTap: _carregandoFoto ? null : _selecionarFotoPerfil,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(color: AppTheme.primaryDark, shape: BoxShape.circle),
                            child: _carregandoFoto
                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.camera_alt, size: 14, color: Colors.white),
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
                        const Text('Motorista cadastrado', style: TextStyle(fontSize: 12, color: AppTheme.statusGrey, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(user?.email ?? 'E-mail não informado', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.primaryDark)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          TextField(controller: _nomeCtrl, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Nome completo', border: OutlineInputBorder(), prefixIcon: Icon(Icons.badge))),
          const SizedBox(height: 12),
          TextField(controller: _telefoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Telefone / WhatsApp', border: OutlineInputBorder(), prefixIcon: Icon(Icons.phone))),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryDark, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              icon: _salvandoPerfil ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save),
              label: Text(_salvandoPerfil ? 'Salvando...' : 'Salvar dados pessoais'),
              onPressed: _salvandoPerfil ? null : _salvarPerfil,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              icon: const Icon(Icons.logout),
              label: const Text('Sair da conta'),
              onPressed: () async {
                await _locationService.pararRastreamento();
                await FirebaseAuth.instance.signOut();
                if (mounted) Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _selecionarFotoPerfil() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _mostrarMensagem('Usuário não autenticado.');
      return;
    }
    try {
      setState(() => _carregandoFoto = true);
      final imagem = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
      if (imagem == null) return;
      final bytes = await imagem.readAsBytes();
      final ref = FirebaseStorage.instance.ref().child('perfil_motorista/${user.uid}.jpg');
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      final url = await ref.getDownloadURL();
      await user.updatePhotoURL(url);
      await FirebaseFirestore.instance.collection('usuarios').doc(user.uid).set({'fotoUrl': url}, SetOptions(merge: true));
      if (mounted) {
        setState(() => _fotoUrlAtual = url);
        _mostrarMensagem('Foto atualizada com sucesso.');
      }
    } catch (e) {
      if (mounted) _mostrarMensagem('Erro ao alterar foto: $e');
    } finally {
      if (mounted) setState(() => _carregandoFoto = false);
    }
  }

  // Modal de detalhes da entrega para o motorista
  void _modalDetalhesEntregaMotorista(BuildContext context, String docId, Map<String, dynamic> entrega) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final String statusAtual = (entrega['status'] ?? 'Pendente').toString();
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

  // Atualiza o status no Firestore. O envio de e-mail deve ser feito no backend
  // (por exemplo, Cloud Functions), nunca com credenciais embutidas no aplicativo.

  Widget _botaoAlterarStatus(
      BuildContext ctx,
      String docId,
      String novoStatus,
      String statusAtual,
      Color cor,
      Map<String, dynamic> entrega,
      ) {
    final selecionado = statusAtual.trim().toLowerCase() ==
        novoStatus.trim().toLowerCase();

    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: selecionado ? cor : cor.withOpacity(0.2),
        foregroundColor: selecionado ? Colors.white : cor,
        elevation: selecionado ? 2 : 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      onPressed: selecionado
          ? null
          : () async {
        debugPrint('--- ATUALIZAÇÃO DE STATUS ---');
        debugPrint('Documento: $docId');
        debugPrint('Status atual: $statusAtual');
        debugPrint('Novo status: $novoStatus');

        try {
          if (novoStatus == 'Entregue') {
            if (!await confirmDelivery(ctx, docId)) return;
          } else {
            await ApiService.atualizarStatusNoServidor(docId, novoStatus);
          }

          debugPrint('Status atualizado com sucesso.');

          if (!ctx.mounted) return;

          Navigator.of(ctx).pop();

          if (mounted) {
            _mostrarMensagem(
              'Status atualizado para: $novoStatus',
            );
          }
        } on FirebaseException catch (e, stackTrace) {
          debugPrint('ERRO FIREBASE: ${e.code}');
          debugPrint('MENSAGEM: ${e.message}');
          debugPrintStack(stackTrace: stackTrace);

          if (ctx.mounted) {
            ScaffoldMessenger.of(ctx).showSnackBar(
              SnackBar(
                content: Text(
                  'Erro Firebase (${e.code}): '
                      '${e.message ?? "Sem detalhes"}',
                ),
              ),
            );
          }
        } catch (e, stackTrace) {
          debugPrint('ERRO INESPERADO: $e');
          debugPrintStack(stackTrace: stackTrace);

          if (ctx.mounted) {
            ScaffoldMessenger.of(ctx).showSnackBar(
              SnackBar(
                content: Text('Erro ao atualizar status: $e'),
              ),
            );
          }
        }
      },
      child: Text(
        novoStatus,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
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

  const _CardMetrica(
      this.titulo,
      this.valor,
      this.icone,
      this.cor,
      );

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: cor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                icone,
                color: cor,
                size: 23,
              ),
            ),
            const SizedBox(height: 12),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                valor,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.primaryDark,
                ),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              titulo,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                height: 1.2,
                color: AppTheme.statusGrey,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
