import 'dart:convert';
import 'package:http/http.dart' as http;

class MapsService {
  static Future<Map<String, dynamic>?> identificarRegiaoPorEndereco(String enderecoCompleto) async {
    String queryLimpa = enderecoCompleto.replaceAll(RegExp(r'[^0-9]'), '');

    try {
      // 1. Se for CEP de 8 dígitos, consulta o ViaCEP para pegar a rua real
      if (queryLimpa.length == 8) {
        final url = Uri.parse('https://viacep.com.br/ws/$queryLimpa/json/');
        final response = await http.get(url);

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['erro'] == null) {
            final String logradouro = data['logradouro'] ?? '';
            final String bairro = data['bairro'] ?? '';
            final String localidade = data['localidade'] ?? '';
            final String uf = data['uf'] ?? '';

            // Monta o endereço formatado com a rua correta
            String enderecoFormatado = logradouro.isNotEmpty
                ? "$logradouro, $bairro - $localidade, $uf"
                : "CEP $enderecoCompleto, $localidade - $uf";

            // Define a região (forçando Oeste se for a faixa de Osasco ou pelo bairro)
            String regiao;
            if (queryLimpa.startsWith('062') || queryLimpa.startsWith('060') || queryLimpa.startsWith('061') || queryLimpa.startsWith('063')) {
              regiao = 'Oeste';
            } else {
              regiao = bairro.isNotEmpty ? _classificarZonaPorBairro(bairro) : _classificarZonaPorBairro("$logradouro $localidade");
            }

            return {
              'lat': 0.0,
              'lng': 0.0,
              'regiao': regiao,
              'enderecoFormatado': enderecoFormatado,
            };
          }
        }
      }

      // 2. Busca por texto livre
      String regiao = _classificarZonaPorBairro(enderecoCompleto);

      return {
        'lat': 0.0,
        'lng': 0.0,
        'regiao': regiao,
        'enderecoFormatado': enderecoCompleto,
      };

    } catch (e) {
      print("Erro ao consultar serviço de endereço: $e");
    }
    return null;
  }

  static String _classificarZonaPorBairro(String texto) {
    String t = texto.toLowerCase();

    if (t.contains('osasco') || t.contains('carapicuíba') || t.contains('barueri') || t.contains('cotia')) {
      return "Oeste";
    }
    else if (t.contains('centro') || t.contains('republica') || t.contains('sé') || t.contains('liberdade') || t.contains('consolação') || t.contains('santa cecília')) {
      return "Centro";
    }
    else if (t.contains('santana') || t.contains('tucuruvi') || t.contains('casa verde') || t.contains('freguesia') || t.contains('pirituba') || t.contains('limão') || t.contains('brasilândia') || t.contains('jaçanã')) {
      return "Norte";
    }
    else if (t.contains('morumbi') || t.contains('pinheiros') || t.contains('lapa') || t.contains('perdizes') || t.contains('butantã') || t.contains('jaguaré') || t.contains('itaim bibi')) {
      return "Oeste";
    }
    else if (t.contains('tatuapé') || t.contains('mooca') || t.contains('penha') || t.contains('itaquera') || t.contains('são mateus') || t.contains('cidade tiradentes') || t.contains('guaianases')) {
      return "Leste";
    }
    else {
      return "Sul";
    }
  }
}