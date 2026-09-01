// lib/models/cliente_model.dart
class ClienteModel {
  final String id;
  final String nome;
  final String telefone;
  final String email;
  final String endereco;
  final String cidade;
  final String cep;
  final DateTime dataCadastro;

  ClienteModel({
    required this.id,
    required this.nome,
    required this.telefone,
    required this.email,
    required this.endereco,
    required this.cidade,
    required this.cep,
    required this.dataCadastro,
  });

  factory ClienteModel.fromJson(Map<String, dynamic> json) {
    return ClienteModel(
      id: json['id'] ?? '',
      nome: json['nome'] ?? '',
      telefone: json['telefone'] ?? '',
      email: json['email'] ?? '',
      endereco: json['endereco'] ?? '',
      cidade: json['cidade'] ?? '',
      cep: json['cep'] ?? '',
      dataCadastro: json['dataCadastro'] != null
          ? DateTime.parse(json['dataCadastro'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nome': nome,
      'telefone': telefone,
      'email': email,
      'endereco': endereco,
      'cidade': cidade,
      'cep': cep,
      'dataCadastro': dataCadastro.toIso8601String(),
    };
  }

  ClienteModel copyWith({
    String? id,
    String? nome,
    String? telefone,
    String? email,
    String? endereco,
    String? cidade,
    String? cep,
    DateTime? dataCadastro,
  }) {
    return ClienteModel(
      id: id ?? this.id,
      nome: nome ?? this.nome,
      telefone: telefone ?? this.telefone,
      email: email ?? this.email,
      endereco: endereco ?? this.endereco,
      cidade: cidade ?? this.cidade,
      cep: cep ?? this.cep,
      dataCadastro: dataCadastro ?? this.dataCadastro,
    );
  }
}