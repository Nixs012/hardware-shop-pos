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
  final String? mpesaType; // 'paybill' or 'till'
  final String? mpesaNumber;
  final String? mpesaAccountNumber;

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
    this.mpesaType,
    this.mpesaNumber,
    this.mpesaAccountNumber,
  });

  /// Formatted instruction line for receipt printing.
  /// If none is configured or number is empty, returns null.
  String? get mpesaInstruction {
    final type = mpesaType?.toLowerCase().trim();
    final num = mpesaNumber?.trim();
    if (num == null || num.isEmpty) return null;
    if (type == 'paybill') {
      final acc = mpesaAccountNumber?.trim();
      if (acc != null && acc.isNotEmpty) {
        return 'Pay via M-Pesa: Paybill $num, Acc $acc';
      }
      return 'Pay via M-Pesa: Paybill $num';
    } else if (type == 'till') {
      return 'Pay via M-Pesa: Till $num';
    }
    return null;
  }

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
      if (mpesaType != null) 'mpesa_type': mpesaType,
      if (mpesaNumber != null) 'mpesa_number': mpesaNumber,
      if (mpesaAccountNumber != null) 'mpesa_account_number': mpesaAccountNumber,
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
      mpesaType: map['mpesa_type'] ?? map['mpesaType'],
      mpesaNumber: map['mpesa_number'] ?? map['mpesaNumber'],
      mpesaAccountNumber: map['mpesa_account_number'] ?? map['mpesaAccountNumber'],
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
    String? mpesaType,
    String? mpesaNumber,
    String? mpesaAccountNumber,
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
      mpesaType: mpesaType ?? this.mpesaType,
      mpesaNumber: mpesaNumber ?? this.mpesaNumber,
      mpesaAccountNumber: mpesaAccountNumber ?? this.mpesaAccountNumber,
    );
  }
}
