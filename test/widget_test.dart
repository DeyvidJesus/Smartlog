// Testes do código amigável da entrega (ENT-XXXX).
//
// Este formato é um contrato entre o app e o Assistente Logístico: a Cloud
// Function deriva o mesmo código em functions/contexto.js (codigoDerivado)
// para as entregas antigas, que não têm o campo 'id' gravado. Se as duas
// implementações divergirem, o assistente cita um código que o usuário não
// encontra na tela.
//
// O arquivo anterior era o template do contador do Flutter e referenciava
// uma classe 'MyApp' inexistente, então `flutter test` nem compilava.

import 'package:flutter_test/flutter_test.dart';

import 'package:smartlife/controllers/dashboard_controller.dart';

void main() {
  group('codigoEntrega', () {
    test('usa os 4 primeiros caracteres do ID, em maiúsculas', () {
      expect(codigoEntrega('aBcD1234567890123456'), 'ENT-ABCD');
    });

    test('é estável: o mesmo ID gera sempre o mesmo código', () {
      const id = 'xY9z0000000000000000';
      expect(codigoEntrega(id), codigoEntrega(id));
    });

    test('não quebra com ID mais curto que 4 caracteres', () {
      expect(codigoEntrega('ab'), 'ENT-AB');
      expect(codigoEntrega(''), 'ENT-');
    });

    test('bate com o codigoDerivado de functions/contexto.js', () {
      // Mesmos exemplos usados em smartlog-ai/test/index.spec.js
      expect(codigoEntrega('def456uvw'), 'ENT-DEF4');
      expect(codigoEntrega('iJkL1234567890123456'), 'ENT-IJKL');
    });
  });
}
