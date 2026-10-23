import 'package:flutter/material.dart';
import '../services/api_service.dart';

Future<bool> confirmDelivery(BuildContext context, String id) async =>
    await showDialog<bool>(context: context, barrierDismissible: false,
      builder: (_) => _ReceiptDialog(id: id)) ?? false;

class _ReceiptDialog extends StatefulWidget {
  final String id;
  const _ReceiptDialog({required this.id});
  @override
  State<_ReceiptDialog> createState() => _ReceiptDialogState();
}
class _ReceiptDialogState extends State<_ReceiptDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(), _notes = TextEditingController();
  bool _saving = false;
  String? _error;
  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() { _saving = true; _error = null; });
    try {
      await ApiService.atualizarStatusNoServidor(widget.id, 'Entregue',
        recebedor: _name.text.trim(), observacaoEntrega: _notes.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _saving = false; });
    }
  }
  @override
  void dispose() { _name.dispose(); _notes.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => PopScope(canPop: !_saving, child: AlertDialog(
    title: const Text('Confirmar recebimento'),
    content: SingleChildScrollView(child: Form(key: _form, child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextFormField(controller: _name, enabled: !_saving, maxLength: 120,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Quem recebeu? *'),
        validator: (v) => v == null || v.trim().isEmpty ? 'Informe o nome do recebedor.' : null),
      TextFormField(controller: _notes, enabled: !_saving, maxLength: 500, maxLines: 3,
        decoration: const InputDecoration(labelText: 'Observações (opcional)', hintText: 'Ex.: recebido na portaria')),
      const Text('Horário e responsável pela confirmação serão registrados automaticamente.'),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: Colors.red))),
    ]))),
    actions: [
      TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancelar')),
      FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Salvando…' : 'Confirmar entrega')),
    ],
  ));
}
