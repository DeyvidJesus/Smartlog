import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/delivery_experience_service.dart';
import '../theme/app_theme.dart';
import 'delivery_capture.dart';

const occurrenceLabels = {
  'AUSENTE': 'Destinatário ausente',
  'AVARIA': 'Avaria',
  'ENDERECO_INCORRETO': 'Endereço incorreto',
  'RECUSA': 'Recusa',
  'ENTREGA_PARCIAL': 'Entrega parcial',
  'OUTRO': 'Outro motivo',
};

Future<bool> reportDeliveryOccurrence(BuildContext context, String id) async =>
    await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _OccurrenceDialog(id: id)) ??
    false;

class _OccurrenceDialog extends StatefulWidget {
  final String id;
  const _OccurrenceDialog({required this.id});
  @override
  State<_OccurrenceDialog> createState() => _OccurrenceDialogState();
}

class _OccurrenceDialogState extends State<_OccurrenceDialog> {
  final _form = GlobalKey<FormState>();
  final _description = TextEditingController(),
      _message = TextEditingController(),
      _volumes = TextEditingController();
  final _requestId = deliveryRequestId();
  String _type = 'AUSENTE';
  String? _photo, _error;
  bool _saving = false;
  Future<void> _capture() async {
    setState(() => _saving = true);
    try {
      final photo = await captureDeliveryPhoto(ImageSource.camera);
      if (mounted) setState(() => _photo = photo ?? _photo);
    } catch (_) {
      if (mounted) setState(() => _error = 'Não foi possível capturar a foto.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await DeliveryExperienceService().report(widget.id, {
        'requestId': _requestId,
        'tipo': _type,
        'descricao': _description.text.trim(),
        'mensagemCliente': _message.text.trim(),
        if (_photo != null) 'foto': _photo,
        if (_type == 'ENTREGA_PARCIAL')
          'volumesRecebidos': int.parse(_volumes.text),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _saving = false;
        });
    }
  }

  @override
  void dispose() {
    _description.dispose();
    _message.dispose();
    _volumes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: const Text('Registrar ocorrência'),
        content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
                child: Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DropdownButtonFormField<String>(
                            initialValue: _type,
                            isExpanded: true,
                            decoration:
                                const InputDecoration(labelText: 'Motivo'),
                            items: occurrenceLabels.entries
                                .map((entry) => DropdownMenuItem(
                                    value: entry.key, child: Text(entry.value)))
                                .toList(),
                            onChanged: _saving
                                ? null
                                : (value) => setState(() => _type = value!)),
                        const SizedBox(height: 16),
                        TextFormField(
                            controller: _description,
                            enabled: !_saving,
                            maxLength: 1500,
                            maxLines: 3,
                            decoration: const InputDecoration(
                                labelText: 'O que aconteceu? *'),
                            validator: (v) => v == null || v.trim().isEmpty
                                ? 'Descreva a ocorrência.'
                                : null),
                        TextFormField(
                            controller: _message,
                            enabled: !_saving,
                            maxLength: 300,
                            maxLines: 2,
                            decoration: const InputDecoration(
                                labelText: 'Mensagem ao cliente (opcional)')),
                        if (_type == 'ENTREGA_PARCIAL')
                          TextFormField(
                              controller: _volumes,
                              enabled: !_saving,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                  labelText:
                                      'Volumes recebidos nesta tentativa *'),
                              validator: (v) => (int.tryParse(v ?? '') ?? 0) < 1
                                  ? 'Informe os volumes recebidos.'
                                  : null),
                        OutlinedButton.icon(
                            onPressed: _saving ? null : _capture,
                            icon: const Icon(Icons.camera_alt_outlined),
                            label: const Text('Anexar foto (opcional)')),
                        if (_photo != null)
                          Image.memory(deliveryImageBytes(_photo!),
                              height: 120, fit: BoxFit.contain),
                        const Text(
                            'A ocorrência será enviada ao gestor. O pedido permanece no status atual até a resolução e a entrega completa.'),
                        if (_error != null)
                          Semantics(
                              liveRegion: true,
                              child: Text(_error!,
                                  style: const TextStyle(
                                      color: AppTheme.statusRed))),
                      ],
                    )))),
        actions: [
          TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Enviando…' : 'Registrar na central'))
        ],
      ));
}
