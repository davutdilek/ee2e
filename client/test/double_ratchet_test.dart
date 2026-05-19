import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:ee2e/crypto/double_ratchet.dart';

void main() {
  group('Double Ratchet', () {
    test('Alice and Bob can exchange messages', () async {
      final x25519 = X25519();
      
      // Simulate X3DH outputs
      final sharedSecret = List<int>.generate(32, (i) => i); // Fake SK
      final bobSpk = await x25519.newKeyPair();
      final bobSpkPub = await bobSpk.extractPublicKey();

      // Initialization
      final alice = await DoubleRatchet.initAlice(sharedSecret, bobSpkPub);
      final bob = await DoubleRatchet.initBob(sharedSecret, bobSpk);

      // Alice sends to Bob
      final msg1Str = 'Hello Bob!';
      final msg1Payload = await alice.encryptMessage(utf8.encode(msg1Str));
      
      final decryptedMsg1Bytes = await bob.decryptMessage(msg1Payload);
      expect(utf8.decode(decryptedMsg1Bytes), msg1Str);

      // Bob replies to Alice
      final msg2Str = 'Hello Alice!';
      final msg2Payload = await bob.encryptMessage(utf8.encode(msg2Str));
      
      final decryptedMsg2Bytes = await alice.decryptMessage(msg2Payload);
      expect(utf8.decode(decryptedMsg2Bytes), msg2Str);

      // Alice sends another
      final msg3Str = 'How are you?';
      final msg3Payload = await alice.encryptMessage(utf8.encode(msg3Str));
      
      final decryptedMsg3Bytes = await bob.decryptMessage(msg3Payload);
      expect(utf8.decode(decryptedMsg3Bytes), msg3Str);
    });

    test('Handles out of order messages', () async {
      final x25519 = X25519();
      final sharedSecret = List<int>.generate(32, (i) => i + 1);
      final bobSpk = await x25519.newKeyPair();
      final bobSpkPub = await bobSpk.extractPublicKey();

      final alice = await DoubleRatchet.initAlice(sharedSecret, bobSpkPub);
      final bob = await DoubleRatchet.initBob(sharedSecret, bobSpk);

      // Alice encrypts 3 messages
      final m1 = await alice.encryptMessage(utf8.encode('Message 1'));
      final m2 = await alice.encryptMessage(utf8.encode('Message 2'));
      final m3 = await alice.encryptMessage(utf8.encode('Message 3'));

      // Bob receives them out of order: 3, 1, 2
      final dec3 = await bob.decryptMessage(m3);
      expect(utf8.decode(dec3), 'Message 3');

      final dec1 = await bob.decryptMessage(m1);
      expect(utf8.decode(dec1), 'Message 1');

      final dec2 = await bob.decryptMessage(m2);
      expect(utf8.decode(dec2), 'Message 2');

      // Bob replies
      final m4 = await bob.encryptMessage(utf8.encode('Reply'));
      final dec4 = await alice.decryptMessage(m4);
      expect(utf8.decode(dec4), 'Reply');
    });
  });
}
