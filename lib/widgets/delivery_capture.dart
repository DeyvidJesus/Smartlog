import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as image;
import '../theme/app_theme.dart';

Future<String?> captureDeliveryPhoto(ImageSource source) async {
  final photo = await ImagePicker().pickImage(
      source: source, maxWidth: 1000, maxHeight: 1000, imageQuality: 70);
  if (photo == null) return null;
  final decoded = image.decodeImage(await photo.readAsBytes());
  if (decoded == null) throw Exception('Não foi possível ler a foto.');
  final resized = decoded.width > 800 || decoded.height > 800
      ? image.copyResize(decoded,
          width: decoded.width >= decoded.height ? 800 : null,
          height: decoded.height > decoded.width ? 800 : null)
      : decoded;
  for (final quality in [70, 55, 40, 25]) {
    final bytes = image.encodeJpg(resized, quality: quality);
    if (bytes.length <= 150000)
      return 'data:image/jpeg;base64,${base64Encode(bytes)}';
  }
  throw Exception('Foto muito grande. Aproxime-se do item e tente novamente.');
}

Uint8List deliveryImageBytes(String source) =>
    base64Decode(source.split(',').last);

class DeliverySignature extends StatefulWidget {
  const DeliverySignature({super.key});
  @override
  State<DeliverySignature> createState() => DeliverySignatureState();
}

class DeliverySignatureState extends State<DeliverySignature> {
  final List<Offset?> _points = [];
  bool get hasSignature => _points.whereType<Offset>().length >= 8;
  Future<String> encode() async {
    if (!hasSignature) throw Exception('Peça ao recebedor para assinar.');
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final painter = _SignaturePainter(List.of(_points));
    painter.paint(canvas, const Size(600, 320));
    final picture = recorder.endRecording();
    final bitmap = await picture.toImage(600, 320);
    final bytes = await bitmap.toByteData(format: ui.ImageByteFormat.png);
    bitmap.dispose();
    picture.dispose();
    if (bytes == null)
      throw Exception('Não foi possível capturar a assinatura.');
    return 'data:image/png;base64,${base64Encode(bytes.buffer.asUint8List())}';
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Assinatura do recebedor *',
            style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Semantics(
            label: 'Área para desenhar a assinatura do recebedor com o dedo',
            child: Container(
              height: 160,
              decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: AppTheme.border),
                  borderRadius: BorderRadius.circular(10)),
              child: LayoutBuilder(
                  builder: (context, constraints) => GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (event) => setState(() => _points.add(
                            Offset(
                                event.localPosition.dx / constraints.maxWidth,
                                event.localPosition.dy / 160))),
                        onPanUpdate: (event) => setState(() => _points.add(
                            Offset(
                                (event.localPosition.dx / constraints.maxWidth)
                                    .clamp(0, 1),
                                (event.localPosition.dy / 160).clamp(0, 1)))),
                        onPanEnd: (_) => setState(() => _points.add(null)),
                        child: CustomPaint(painter: _SignaturePainter(_points)),
                      )),
            )),
        Align(
            alignment: Alignment.centerRight,
            child: TextButton(
                onPressed: () => setState(_points.clear),
                child: const Text('Limpar assinatura'))),
      ]);
}

class _SignaturePainter extends CustomPainter {
  final List<Offset?> points;
  _SignaturePainter(this.points);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final paint = Paint()
      ..color = AppTheme.primaryDark
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    for (var i = 1; i < points.length; i++) {
      if (points[i - 1] != null && points[i] != null) {
        canvas.drawLine(
            Offset(points[i - 1]!.dx * size.width,
                points[i - 1]!.dy * size.height),
            Offset(points[i]!.dx * size.width, points[i]!.dy * size.height),
            paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}
