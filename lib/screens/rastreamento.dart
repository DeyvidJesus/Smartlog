import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class TelaRastreioPublica extends StatefulWidget {
  final String rotaId;

  const TelaRastreioPublica({super.key, required this.rotaId});

  @override
  State<TelaRastreioPublica> createState() => _TelaRastreioPublicaState();
}

class _TelaRastreioPublicaState extends State<TelaRastreioPublica> {
  GoogleMapController? _mapController;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("SmartLog • Acompanhar Entrega"),
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('rotas')
            .doc(widget.rotaId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(
              child: Text(
                "Informações de rastreio não encontradas.",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            );
          }

          var data = snapshot.data!.data() as Map<String, dynamic>?;
          var loc = data?['localizacaoAtual'];

          // Mensagem padrão caso o motorista ainda não tenha iniciado
          if (loc == null || loc['latitude'] == null || loc['longitude'] == null) {
            return Stack(
              children: [
                const Center(
                  child: Text(
                    "Aguardando o motorista iniciar o trajeto...",
                    style: TextStyle(fontSize: 15, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ),
                _buildInfoCard("Aguardando início da rota 📦", Colors.orange),
              ],
            );
          }

          double lat = loc['latitude'];
          double lng = loc['longitude'];
          LatLng posicaoMotorista = LatLng(lat, lng);

          _mapController?.animateCamera(
            CameraUpdate.newLatLng(posicaoMotorista),
          );

          return Stack(
            children: [
              GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: posicaoMotorista,
                  zoom: 16,
                ),
                onMapCreated: (controller) {
                  _mapController = controller;
                },
                markers: {
                  Marker(
                    markerId: const MarkerId('motorista_movimento'),
                    position: posicaoMotorista,
                    infoWindow: const InfoWindow(
                      title: 'Sua entrega está perto! 🚚',
                      snippet: 'Motorista em deslocamento',
                    ),
                  ),
                },
              ),
              // Card flutuante com a mensagem para o cliente
              _buildInfoCard("Sua entrega está perto! 🚚", Colors.green),
            ],
          );
        },
      ),
    );
  }

  // Widget auxiliar para estilizar o aviso no topo
  Widget _buildInfoCard(String mensagem, Color corStatus) {
    return Positioned(
      top: 16,
      left: 16,
      right: 16,
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: corStatus,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  mensagem,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}