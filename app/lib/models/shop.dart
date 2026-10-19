class Shop {
  final String id;
  final String name;
  final String address;
  final String phone;
  final String footer;
  final String paperSize;
  final String ownerUid;
  final String joinCode;
  final DateTime createdAt;

  Shop({
    required this.id,
    required this.name,
    required this.address,
    required this.phone,
    required this.footer,
    required this.paperSize,
    required this.ownerUid,
    required this.joinCode,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'address': address,
      'phone': phone,
      'footer': footer,
      'paper_size': paperSize,
      'owner_uid': ownerUid,
      'join_code': joinCode,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Shop.fromMap(Map<String, dynamic> map, String id) {
    return Shop(
      id: id,
      name: map['name'] ?? '',
      address: map['address'] ?? '',
      phone: map['phone'] ?? '',
      footer: map['footer'] ?? '',
      paperSize: map['paper_size'] ?? '58mm',
      ownerUid: map['owner_uid'] ?? '',
      joinCode: map['join_code'] ?? '',
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'])
          : DateTime.now(),
    );
  }

  Shop copyWith({
    String? id,
    String? name,
    String? address,
    String? phone,
    String? footer,
    String? paperSize,
    String? ownerUid,
    String? joinCode,
    DateTime? createdAt,
  }) {
    return Shop(
      id: id ?? this.id,
      name: name ?? this.name,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      footer: footer ?? this.footer,
      paperSize: paperSize ?? this.paperSize,
      ownerUid: ownerUid ?? this.ownerUid,
      joinCode: joinCode ?? this.joinCode,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
