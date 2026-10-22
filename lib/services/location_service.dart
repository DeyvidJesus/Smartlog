
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

class LocationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  StreamSubscription<Position>? _subscription;

  Future<void> iniciarRastreamento({
    required String rotaId,
    required String motoristaId,
  }) async {
    // Verifica se o serviço de localização está ativo.
    final servicoAtivo = await Geolocator.isLocationServiceEnabled();

    if (!servicoAtivo) {
      throw Exception('Ative o GPS do celular.');
    }

    // Verifica e solicita permissão.
    LocationPermission permissao =
    await Geolocator.checkPermission();

    if (permissao == LocationPermission.denied) {
      permissao = await Geolocator.requestPermission();
    }

    if (permissao == LocationPermission.denied ||
        permissao == LocationPermission.deniedForever) {
      throw Exception(
        'Permissão de localização negada. '
            'Autorize o acesso à localização nas configurações.',
      );
    }

    // Envia uma atualização sempre que a posição mudar.
    const configuracao = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );

    await pararRastreamento();

    _subscription = Geolocator.getPositionStream(
      locationSettings: configuracao,
    ).listen(
          (posicao) async {
        try {
          await _firestore.collection('rotas').doc(rotaId).update({
            'localizacaoAtual': {
              'latitude': posicao.latitude,
              'longitude': posicao.longitude,
              'atualizadoEm': FieldValue.serverTimestamp(),
            },
            'motoristaId': motoristaId,
          });
        } catch (e) {
          // Não interrompe o stream por uma falha pontual.
          print('Erro ao salvar GPS no Firebase: $e');
        }
      },
      onError: (Object erro) {
        print('Erro no rastreamento GPS: $erro');
      },
    );
  }

  Future<void> pararRastreamento() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
