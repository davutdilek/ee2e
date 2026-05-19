import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ee2e/crypto/tree_kem.dart';

void main() {
  group('TreeKEM', () {
    test('Tek üyeli grup oluşturulur ve group secret türetilir', () async {
      final tree = TreeKem();
      await tree.createGroup('alice');

      expect(tree.leafCount, 1);
      expect(tree.myLeafIndex, 0);

      final secret = await tree.deriveGroupSecret();
      expect(secret.length, 32);
    });

    test('Üye eklendikten sonra ağaç güncellenir', () async {
      final tree = TreeKem();
      await tree.createGroup('alice');

      final addResult = await tree.addMember('bob');
      expect(addResult['member_id'], 'bob');
      expect(tree.leafCount, 2);

      final secret = await tree.deriveGroupSecret();
      expect(secret.length, 32);
    });

    test('3 üyeli grupta tüm yollar güncellenir', () async {
      final tree = TreeKem();
      await tree.createGroup('alice');
      await tree.addMember('bob');
      await tree.addMember('charlie');

      expect(tree.leafCount, 3);

      final secret = await tree.deriveGroupSecret();
      expect(secret.length, 32);
    });

    test('Üye çıkarıldığında Forward Secrecy sağlanır', () async {
      final tree = TreeKem();
      await tree.createGroup('alice');
      await tree.addMember('bob');
      await tree.addMember('charlie');

      final secretBefore = await tree.deriveGroupSecret();

      // Bob'u çıkar (leaf index 1)
      final removeResult = await tree.removeMember(1);
      expect(removeResult['member_id'], 'bob');

      // Yeni sır farklı olmalı (Forward Secrecy)
      final secretAfter = await tree.deriveGroupSecret();
      expect(secretAfter, isNot(equals(secretBefore)));
    });

    test('Self-update Post-Compromise Security sağlar', () async {
      final tree = TreeKem();
      await tree.createGroup('alice');
      await tree.addMember('bob');

      final secretBefore = await tree.deriveGroupSecret();

      final updateResult = await tree.selfUpdate();
      expect(updateResult['type'], 'tree_kem_update');

      final secretAfter = await tree.deriveGroupSecret();
      expect(secretAfter, isNot(equals(secretBefore)));
    });

    test('4 üyeli grupta ağaç boyutu doğru', () async {
      final tree = TreeKem();
      await tree.createGroup('alice');
      await tree.addMember('bob');
      await tree.addMember('charlie');
      await tree.addMember('dave');

      expect(tree.leafCount, 4);

      final secret = await tree.deriveGroupSecret();
      expect(secret.length, 32);
    });
  });
}
