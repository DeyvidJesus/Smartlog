import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import '../services/delivery_experience_service.dart';
import '../theme/app_theme.dart';
import 'delivery_capture.dart';

Future<bool> confirmDelivery(BuildContext context, String id) async =>
    await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ReceiptDialog(id: id)) ??
    false;

class _ReceiptDialog extends StatefulWidget {
  final String id;
  const _ReceiptDialog({required this.id});
  @override
  State<_ReceiptDialog> createState() => _ReceiptDialogState();
}

class _ReceiptDialogState extends State<_ReceiptDialog> {
  final _form = GlobalKey<FormState>();
  final _signature = GlobalKey<DeliverySignatureState>();
  final _name = TextEditingController(), _notes = TextEditingController();
  final _volumes = TextEditingController();
  final _requestId = deliveryRequestId();
  final _service = DeliveryExperienceService();
  final _photos = <String>[];
  Position? _position;
  bool _saving = false, _capturing = false;
  String? _error;
  Future<void> _photo(ImageSource source) async {
    setState(() {
      _capturing = true;
      _error = null;
    });
    try {
      final photo = await captureDeliveryPhoto(source);
      if (mounted && photo != null) setState(() => _photos.add(photo));
    } catch (_) {
      if (mounted)
        setState(() => _error =
            'Não foi possível capturar a foto. Confira a permissão da câmera ou selecione da galeria.');
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _location() async {
    setState(() {
      _capturing = true;
      _error = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled())
        throw Exception('Ative o GPS do aparelho.');
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied)
        permission = await Geolocator.requestPermission();
      if (![LocationPermission.always, LocationPermission.whileInUse]
          .contains(permission)) {
        throw Exception(
            'Autorize a localização nas configurações do aparelho.');
      }
      final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 25)));
      if (position.accuracy > 1000)
        throw Exception(
            'GPS impreciso. Aproxime-se de uma área aberta e tente novamente.');
      if (mounted) setState(() => _position = position);
    } catch (error) {
      if (mounted)
        setState(
            () => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _save() async {
    if (_saving || _capturing || !_form.currentState!.validate()) return;
    if (_photos.isEmpty ||
        _position == null ||
        !_signature.currentState!.hasSignature) {
      setState(
          () => _error = 'Inclua foto, localização e assinatura do recebedor.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final signature = await _signature.currentState!.encode();
      if (DateTime.now().difference(_position!.timestamp).inMinutes > 5)
        throw Exception('Atualize a localização antes de confirmar.');
      await _service.confirm(widget.id, {
        'requestId': _requestId,
        'recebedor': _name.text.trim(),
        'observacao': _notes.text.trim(),
        'fotos': _photos,
        'assinatura': signature,
        'volumesRecebidos': int.parse(_volumes.text),
        'latitude': _position!.latitude,
        'longitude': _position!.longitude,
        'precisao': _position!.accuracy,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted)
        setState(() {
          _error =
              '${e.toString().replaceFirst('Exception: ', '')} Nenhuma confirmação local foi criada; consulte a central antes de repetir.';
          _saving = false;
        });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    _volumes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_saving && !_capturing,
      child: AlertDialog(
        title: const Text('Comprovante de entrega'),
        content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
                child: Form(
                    key: _form,
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                              'Registre os itens recebidos. Se faltar algum volume, registre uma ocorrência de entrega parcial.'),
                          const SizedBox(height: 16),
                          TextFormField(
                              controller: _name,
                              enabled: !_saving,
                              maxLength: 120,
                              textCapitalization: TextCapitalization.words,
                              decoration: const InputDecoration(
                                  labelText: 'Quem recebeu? *'),
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? 'Informe o nome do recebedor.'
                                  : null),
                          TextFormField(
                              controller: _volumes,
                              enabled: !_saving,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                  labelText: 'Total de volumes recebidos *'),
                              validator: (v) => (int.tryParse(v ?? '') ?? 0) < 1
                                  ? 'Informe uma quantidade válida.'
                                  : null),
                          const SizedBox(height: 12),
                          TextFormField(
                              controller: _notes,
                              enabled: !_saving,
                              maxLength: 500,
                              maxLines: 2,
                              decoration: const InputDecoration(
                                  labelText: 'Observações (opcional)')),
                          if (_photos.length < 2)
                            Wrap(spacing: 8, children: [
                              OutlinedButton.icon(
                                  onPressed: _saving || _capturing
                                      ? null
                                      : () => _photo(ImageSource.camera),
                                  icon: const Icon(Icons.camera_alt_outlined),
                                  label: const Text('Fotografar')),
                              TextButton(
                                  onPressed: _saving || _capturing
                                      ? null
                                      : () => _photo(ImageSource.gallery),
                                  child: const Text('Galeria')),
                            ]),
                          ..._photos.indexed.map((entry) => Row(children: [
                                Image.memory(deliveryImageBytes(entry.$2),
                                    width: 100, height: 80, fit: BoxFit.cover),
                                IconButton(
                                    tooltip: 'Remover foto ${entry.$1 + 1}',
                                    onPressed: _saving || _capturing
                                        ? null
                                        : () => setState(
                                            () => _photos.removeAt(entry.$1)),
                                    icon: const Icon(Icons.delete_outline)),
                              ])),
                          OutlinedButton.icon(
                              onPressed:
                                  _saving || _capturing ? null : _location,
                              icon: const Icon(Icons.my_location),
                              label: Text(_position == null
                                  ? 'Capturar localização *'
                                  : 'Atualizar localização')),
                          if (_position != null)
                            Text(
                                'GPS registrado · precisão ${_position!.accuracy.round()} m',
                                style: const TextStyle(
                                    color: AppTheme.statusGreen)),
                          const SizedBox(height: 16),
                          AbsorbPointer(
                              absorbing: _saving,
                              child: DeliverySignature(key: _signature)),
                          const Text(
                              'Ao confirmar, foto, assinatura, horário do servidor e responsável serão vinculados à entrega.'),
                          if (_capturing) const LinearProgressIndicator(),
                          if (_error != null)
                            Semantics(
                                liveRegion: true,
                                child: Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: Text(_error!,
                                        style: const TextStyle(
                                            color: AppTheme.statusRed)))),
                        ])))),
        actions: [
          TextButton(
              onPressed: _saving || _capturing
                  ? null
                  : () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: _saving || _capturing ? null : _save,
              child:
                  Text(_saving ? 'Enviando à central…' : 'Confirmar entrega')),
        ],
      ));
}
