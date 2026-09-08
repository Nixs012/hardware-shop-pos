class Staff {
  final String id;
  final String name;
  final String role; // admin/cashier
  final String email;
  final bool active;
  final String? pin;
  final String? authUid;

  Staff({
    required this.id,
    required this.name,
    required this.role,
    required this.email,
    this.active = true,
    this.pin,
    this.authUid,
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
    };
  }

  factory Staff.fromMap(Map<String, dynamic> map, String id) {
    return Staff(
      id: id,
      name: map['name'] ?? '',
      role: map['role'] ?? 'cashier',
      email: map['email'] ?? '',
      active: map['active'] ?? true, // Default to true for existing docs
      pin: map['pin'],
      authUid: map['auth_uid'],
    );
  }
}
