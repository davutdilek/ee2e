import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ee2e/crypto/sender_key.dart';

void main() {
  group('Sender Key (Group Messaging)', () {
    test('Alice sends a message to Bob and Charlie', () async {
      final alice = GroupCipher(groupId: 'group1', myPeerId: 'alice');
      final bob = GroupCipher(groupId: 'group1', myPeerId: 'bob');
      final charlie = GroupCipher(groupId: 'group1', myPeerId: 'charlie');

      // 1. Alice creates her Sender Key for the group
      final aliceState = await alice.generateMySenderKey();

      // 2. Alice distributes her state to Bob and Charlie (simulated via JSON)
      final distributionPayload = aliceState.toDistributionJson();
      bob.processDistributionMessage('alice', distributionPayload);
      charlie.processDistributionMessage('alice', distributionPayload);

      // 3. Alice sends a group message
      final plaintext = 'Hello Group!';
      final message = await alice.encrypt(utf8.encode(plaintext));

      // 4. Bob receives and decrypts
      final bobDecrypted = await bob.decrypt('alice', message);
      expect(utf8.decode(bobDecrypted), plaintext);

      // 5. Charlie receives and decrypts
      final charlieDecrypted = await charlie.decrypt('alice', message);
      expect(utf8.decode(charlieDecrypted), plaintext);
      
      // 6. Alice sends another message
      final msg2 = await alice.encrypt(utf8.encode('Second message'));
      expect(utf8.decode(await bob.decrypt('alice', msg2)), 'Second message');
    });

    test('Handles out of order group messages', () async {
      final alice = GroupCipher(groupId: 'group1', myPeerId: 'alice');
      final bob = GroupCipher(groupId: 'group1', myPeerId: 'bob');

      final aliceState = await alice.generateMySenderKey();
      bob.processDistributionMessage('alice', aliceState.toDistributionJson());

      // Alice sends 3 messages
      final m1 = await alice.encrypt(utf8.encode('Msg 1'));
      final m2 = await alice.encrypt(utf8.encode('Msg 2'));
      final m3 = await alice.encrypt(utf8.encode('Msg 3'));

      // Bob receives them out of order: 3, 1, 2
      final dec3 = await bob.decrypt('alice', m3);
      expect(utf8.decode(dec3), 'Msg 3');

      final dec1 = await bob.decrypt('alice', m1);
      expect(utf8.decode(dec1), 'Msg 1');

      final dec2 = await bob.decrypt('alice', m2);
      expect(utf8.decode(dec2), 'Msg 2');
    });
  });
}
