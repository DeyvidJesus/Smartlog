class Entrega {
  final String id;
  final String clienteId;
  final String motoristaId;
  final String origem;
  final String destino;
  final String status;
  final String eta; // Estimated Time of Arrival
  final String rotaId;
  final DateTime dataCriacao;
  final DateTime? dataEntrega;

  Entrega({
    required this.id,
    required this.clienteId,
    required this.motoristaId,
    required this.origem,
    required this.destino,
    required this.status,
    required this.eta,
    required this.rotaId,
    required this.dataCriacao,
    this.dataEntrega,
  });

  factory Entrega.fromJson(Map<String, dynamic> json) {
    return Entrega(
      id: json['id'] ?? '',
      clienteId: json['clienteId'] ?? '',
      motoristaId: json['motoristaId'] ?? '',
      origem: json['origem'] ?? '',
      destino: json['destino'] ?? '',
      status: json['status'] ?? 'Pendente',
      eta: json['ETA'] ?? '',
      rotaId: json['rotaId'] ?? '',
      dataCriacao: (json['criadaEm'] ?? json['dataCriacao']) != null
          ? DateTime.parse(json['criadaEm'] ?? json['dataCriacao'])
          : DateTime.now(),
      dataEntrega: (json['entregueEm'] ?? json['dataEntrega']) != null
          ? DateTime.parse(json['entregueEm'] ?? json['dataEntrega'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'clienteId': clienteId,
      'motoristaId': motoristaId,
      'origem': origem,
      'destino': destino,
      'status': status,
      'ETA': eta,
      'rotaId': rotaId,
      'dataCriacao': dataCriacao.toIso8601String(),
      'dataEntrega': dataEntrega?.toIso8601String(),
    };
  }

  Entrega copyWith({
    String? id,
    String? clienteId,
    String? motoristaId,
    String? origem,
    String? destino,
    String? status,
    String? eta,
    String? rotaId,
    DateTime? dataCriacao,
    DateTime? dataEntrega,
  }) {
    return Entrega(
      id: id ?? this.id,
      clienteId: clienteId ?? this.clienteId,
      motoristaId: motoristaId ?? this.motoristaId,
      origem: origem ?? this.origem,
      destino: destino ?? this.destino,
      status: status ?? this.status,
      eta: eta ?? this.eta,
      rotaId: rotaId ?? this.rotaId,
      dataCriacao: dataCriacao ?? this.dataCriacao,
      dataEntrega: dataEntrega ?? this.dataEntrega,
    );
  }
}
