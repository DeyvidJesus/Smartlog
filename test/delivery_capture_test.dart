import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlife/theme/app_theme.dart';
import 'package:smartlife/widgets/confirm_delivery.dart';
import 'package:smartlife/widgets/delivery_capture.dart';

void main() {
  testWidgets('receiver signature can be drawn exported as PNG and cleared',
      (tester) async {
    final signature = GlobalKey<DeliverySignatureState>();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(
                child: SizedBox(
                    width: 300, child: DeliverySignature(key: signature))))));
    expect(signature.currentState!.hasSignature, false);
    final canvas = finderForCanvas();
    final start = tester.getTopLeft(canvas) + const Offset(20, 70);
    final gesture = await tester.startGesture(start);
    for (var i = 1; i < 15; i++) {
      await gesture.moveTo(start + Offset(i * 12.0, (i % 2) * 14.0));
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();
    expect(signature.currentState!.hasSignature, true);
    final png = await tester.runAsync(() => signature.currentState!.encode());
    expect(png, startsWith('data:image/png;base64,'));
    expect(deliveryImageBytes(png!).length, lessThanOrEqualTo(50000));
    await tester.tap(find.text('Limpar assinatura'));
    await tester.pump();
    expect(signature.currentState!.hasSignature, false);
  });
  for (final width in [320.0, 390.0, 768.0]) {
    testWidgets(
        'receipt form fits a $width px screen and blocks missing mandatory evidence',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 740);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
              body: Builder(
                  builder: (context) => TextButton(
                      onPressed: () =>
                          confirmDelivery(context, 'delivery-test'),
                      child: const Text('Abrir'))))));
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Quem recebeu? *'), 'Maria');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Total de volumes recebidos *'),
          '2');
      await tester.tap(find.text('Confirmar entrega'));
      await tester.pumpAndSettle();
      expect(find.text('Inclua foto, localização e assinatura do recebedor.'),
          findsOneWidget);
      expect(tester.takeException(), null);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.text('Comprovante de entrega'), findsNothing);
    });
  }
}

Finder finderForCanvas() => find
    .descendant(
        of: find.byType(DeliverySignature),
        matching: find.byType(GestureDetector))
    .first;
