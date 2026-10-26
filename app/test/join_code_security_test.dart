import 'package:flutter_test/flutter_test.dart';
import 'package:app/models/shop.dart';
import 'package:app/models/user_lookup.dart';
import 'package:app/models/staff.dart';
import 'mock_firestore_service.dart';

void main() {
  group('Join Code Security & Multi-Shop Data Model Tests', () {
    test('Shop model correctly maps joinCode to join_code field', () {
      final now = DateTime.now();
      final shop = Shop(
        id: 'shop_123',
        name: 'Hardware Hub',
        address: 'Nairobi',
        phone: '0700000000',
        footer: 'Welcome',
        paperSize: '58mm',
        ownerUid: 'owner_abc',
        joinCode: 'ABC456',
        createdAt: now,
      );

      final map = shop.toMap();
      expect(map['join_code'], 'ABC456');
      expect(map['owner_uid'], 'owner_abc');
      expect(map['name'], 'Hardware Hub');

      final reconstructed = Shop.fromMap(map, 'shop_123');
      expect(reconstructed.joinCode, 'ABC456');
      expect(reconstructed.ownerUid, 'owner_abc');
    });

    test('UserLookup and Staff models preserve role constraints', () {
      final user = UserLookup(
        uid: 'user_1',
        shopId: 'shop_123',
        role: 'cashier',
        name: 'Jane Doe',
        email: 'jane@example.com',
      );

      final map = user.toMap();
      expect(map['role'], 'cashier');
      expect(map['shop_id'], 'shop_123');

      final staff = Staff(
        id: 'user_1',
        name: 'Jane Doe',
        role: 'cashier',
        email: 'jane@example.com',
        authUid: 'user_1',
        shopId: 'shop_123',
      );

      final staffMap = staff.toMap();
      expect(staffMap['role'], 'cashier');
      expect(staffMap['shop_id'], 'shop_123');
    });

    test('MockFirestoreService regenerateJoinCode generates valid 6-char alphanumeric code', () async {
      final mock = MockFirestoreService();
      final oldShop = await mock.getShop();
      final oldCode = oldShop?.joinCode;
      expect(oldCode, isNotNull);

      final newCode = await mock.regenerateJoinCode(oldCode);
      expect(newCode.length, 6);
      expect(RegExp(r'^[A-Z0-9]{6}$').hasMatch(newCode), isTrue);

      final updatedShop = await mock.getShop();
      expect(updatedShop?.joinCode, newCode);
    });
  });
}



