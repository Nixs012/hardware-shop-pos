class Staff {
  final String id;
  final String name;
  final String role; // admin/cashier
  final String email;
  final bool active;
  final String? pin;
  final String? authUid;
  final String? shopId;

  Staff({
    required this.id,
    required this.name,
    required this.role,
    required this.email,
    this.active = true,
    this.pin,
    this.authUid,
    this.shopId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'role': role,
      'email': email,
      'active': active,
      'pin': pin,
      'auth_uid': authUid,
      'shop_id': shopId,
    };
  }

  factory Staff.fromMap(Map<String, dynamic> map, String id) {
    return Staff(
      id: id,
      name: map['name'] ?? '',
      role: map['role'] ?? 'cashier',
      email: map['email'] ?? '',
      active: map['active'] ?? true,
      pin: map['pin'],
      authUid: map['auth_uid'],
      shopId: map['shop_id'],
    );
  }
}



