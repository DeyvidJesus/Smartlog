import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../theme/app_theme.dart';
import '../widgets/road_map.dart';

class MapScreen extends StatelessWidget {
  final Map<String, dynamic> rota;
  final String rotaId;
  final String motoristaNome;

  const MapScreen({
    super.key,
    required this.rota,
    required this.rotaId,
    required this.motoristaNome,
  });

  List<Map<String, dynamic>> _stops(Map<String, dynamic> route) {
    final raw = route['enderecos'];
    if (raw is! List) return const [];

    return raw.indexed.where((entry) => entry.$2 is Map).map((entry) {
      final stop = Map<String, dynamic>.from(entry.$2 as Map);
      return {
        ...stop,
        'docId': (stop['entregaId'] ?? stop['docId'] ?? 'parada-${entry.$1}')
            .toString(),
        'id': (stop['codigo'] ?? stop['entregaId'] ?? 'Parada ${entry.$1 + 1}')
            .toString(),
        'ordemEntrega': stop['ordemEntrega'] ?? entry.$1 + 1,
      };
    }).toList();
  }

  LatLng? _driverPosition(Map<String, dynamic> route) {
    final raw = route['localizacaoAtual'];
    if (raw is! Map || raw['latitude'] is! num || raw['longitude'] is! num) {
      return null;
    }
    final latitude = (raw['latitude'] as num).toDouble();
    final longitude = (raw['longitude'] as num).toDouble();
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        latitude.abs() > 90 ||
        longitude.abs() > 180) {
      return null;
    }
    return LatLng(latitude, longitude);
  }

  Future<void> _saveDistance(double meters, bool includesGps) {
    return FirebaseFirestore.instance.collection('rotas').doc(rotaId).update({
      'distanciaRestanteMetros': meters,
      'distanciaIncluiGps': includesGps,
      'distanciaCalculadaEm': FieldValue.serverTimestamp(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Acompanhar rota'),
            Text(
              motoristaNome,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFCBD5E1),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('rotas')
            .doc(rotaId)
            .snapshots(),
        builder: (context, snapshot) {
          final liveRoute = snapshot.data?.data();
          final route = liveRoute == null ? rota : {...rota, ...liveRoute};
          final stops = _stops(route);

          if (snapshot.hasError && stops.isEmpty) {
            return const _RouteMessage(
              icon: Icons.cloud_off_outlined,
              title: 'Não foi possível atualizar a rota',
              message: 'Confira sua conexão e tente novamente.',
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting &&
              stops.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (stops.isEmpty) {
            return const _RouteMessage(
              icon: Icons.route_outlined,
              title: 'Rota sem paradas',
              message: 'Adicione entregas à rota para visualizar o trajeto.',
            );
          }

          return RoadMap(
            stops: stops,
            driver: _driverPosition(route),
            onDistance: _saveDistance,
          );
        },
      ),
    );
  }
}

class _RouteMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _RouteMessage(
      {required this.icon, required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: AppTheme.accentOrangeLight,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: AppTheme.accentOrangeDark, size: 30),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textMuted, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
