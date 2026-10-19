class UserLookup {
  final String uid;
  final String shopId;
  final String role; // 'admin' or 'cashier'
  final String name;
  final String email;
  final bool active;

  UserLookup({
    required this.uid,
    required this.shopId,
    required this.role,
    required this.name,
    required this.email,
    this.active = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'shop_id': shopId,
      'role': role,
      'name': name,
      'email': email,
      'active': active,
    };
  }

  factory UserLookup.fromMap(Map<String, dynamic> map, String uid) {
    return UserLookup(
      uid: uid,
      shopId: map['shop_id'] ?? '',
      role: map['role'] ?? 'cashier',
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      active: map['active'] ?? true,
    );
  }
}
