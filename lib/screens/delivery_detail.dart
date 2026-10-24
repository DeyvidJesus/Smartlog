import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/delivery_experience_service.dart';
import '../theme/app_theme.dart';
import '../widgets/delivery_capture.dart';
import '../widgets/report_occurrence.dart';

class DeliveryDetailScreen extends StatefulWidget {
  final String deliveryId;
  final bool canShare;
  const DeliveryDetailScreen(
      {super.key, required this.deliveryId, this.canShare = false});
  @override
  State<DeliveryDetailScreen> createState() => _DeliveryDetailScreenState();
}

class _DeliveryDetailScreenState extends State<DeliveryDetailScreen> {
  final _service = DeliveryExperienceService();
  Map<String, dynamic>? _delivery, _receipt;
  List<dynamic> _occurrences = [];
  bool _loading = true, _sharing = false;
  String? _error, _link;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data =
          await _service.delivery(widget.deliveryId) as Map<String, dynamic>;
      final occurrences = await _service.occurrences(widget.deliveryId) as List;
      final receipt = data['comprovanteDisponivel'] == true
          ? await _service.receipt(widget.deliveryId) as Map<String, dynamic>
          : null;
      if (mounted)
        setState(() {
          _delivery = data;
          _occurrences = occurrences;
          _receipt = receipt;
        });
    } catch (e) {
      if (mounted)
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      final data = await _service.share(widget.deliveryId) as Map;
      final link = 'https://smartlog-next-2026.netlify.app${data['caminho']}';
      if (!mounted) return;
      setState(() => _link = link);
      await Clipboard.setData(ClipboardData(text: link));
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Link copiado. Válido por 7 dias; o link anterior foi invalidado.')));
    } catch (e) {
      if (mounted)
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Acompanhar entrega'), actions: [
          IconButton(
              tooltip: 'Atualizar',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh))
        ]),
        body: SafeArea(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(20),
                        children: [
                          if (_error != null)
                            Semantics(
                                liveRegion: true,
                                child: Text(_error!,
                                    style: const TextStyle(
                                        color: AppTheme.statusRed))),
                          if (_delivery != null) ...[
                            Text(_delivery!['codigo']?.toString() ?? '',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800, fontSize: 24)),
                            const SizedBox(height: 8),
                            Text('Status: ${_delivery!['status']}'),
                            Text('Destino: ${_delivery!['destino']}'),
                            Text(
                                'Janela: ${_delivery!['janelaEntrega'] ?? 'Não cadastrada'}'),
                            const SizedBox(height: 20),
                            if (widget.canShare) ...[
                              OutlinedButton.icon(
                                  onPressed: _sharing ? null : _share,
                                  icon: const Icon(Icons.share_outlined),
                                  label: Text(_sharing
                                      ? 'Gerando…'
                                      : 'Gerar link de acompanhamento')),
                              if (_link != null) SelectableText(_link!),
                              const Text(
                                  'Compartilhe somente com pessoas que podem acompanhar esta entrega.'),
                            ],
                          ],
                          const SizedBox(height: 20),
                          const Text('Ocorrências',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 19)),
                          if (_occurrences.isEmpty)
                            const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Text('Nenhuma ocorrência registrada.')),
                          ..._occurrences.map((dynamic item) => Card(
                              child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                            occurrenceLabels[item['tipo']] ??
                                                item['tipo'].toString(),
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w800)),
                                        const SizedBox(height: 8),
                                        Text(
                                            item['status'] == 'RESOLVIDA'
                                                ? 'Resolvida'
                                                : 'Em atendimento',
                                            style: const TextStyle(
                                                color:
                                                    AppTheme.accentOrangeDark)),
                                        Text((widget.canShare
                                                    ? item['mensagemCliente']
                                                    : item['descricao'])
                                                ?.toString() ??
                                            'A equipe está acompanhando esta ocorrência.'),
                                        if (item['volumesRecebidos'] != null)
                                          Text(
                                              'Volumes recebidos nesta tentativa: ${item['volumesRecebidos']}'),
                                        if (!widget.canShare &&
                                            item['resolucao'] != null)
                                          Text(
                                              'Resolução: ${item['resolucao']}'),
                                      ])))),
                          const SizedBox(height: 20),
                          const Text('Comprovante',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 19)),
                          if (_receipt == null)
                            const Text(
                                'O comprovante completo ainda não está disponível.'),
                          if (_receipt != null) ...[
                            Text('Recebido por ${_receipt!['recebedor']}'),
                            Text(
                                '${_receipt!['volumesRecebidos']} volumes · ${_receipt!['em']}'),
                            ...(_receipt!['fotos'] as List).map((photo) =>
                                Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 8),
                                    child: Image.memory(
                                        deliveryImageBytes(photo as String),
                                        height: 240,
                                        fit: BoxFit.contain))),
                            const Text('Assinatura do recebedor'),
                            Image.memory(
                                deliveryImageBytes(
                                    _receipt!['assinatura'] as String),
                                height: 150,
                                fit: BoxFit.contain),
                          ],
                        ]),
                  )),
      );
}
