import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:ee2e/crypto/sealed_sender.dart';

void main() {
  group('Sealed Sender', () {
    test('Alice seals her sender_id and Bob unseals it', () async {
      final x25519 = Cryptography.instance.x25519();
      
      // Bob generates his Identity KeyPair
      final bobIdentityKp = await x25519.newKeyPair();
      final bobIdentityPub = await bobIdentityKp.extractPublicKey();

      final senderId = 'alice_in_wonderland';

      // Alice seals her ID using Bob's public Identity Key
      final sealedEnvelope = await SealedSender.seal(
        senderId: senderId,
        recipientIdentityPublicKey: bobIdentityPub,
      );

      // Bob unseals it using his private Identity Key
      final unsealedSenderId = await SealedSender.unseal(
        sealedEnvelope: sealedEnvelope,
        myIdentityKeyPair: bobIdentityKp,
      );

      expect(unsealedSenderId, senderId);
    });

    test('Fails to unseal with wrong key', () async {
      final x25519 = Cryptography.instance.x25519();
      
      final bobIdentityKp = await x25519.newKeyPair();
      final bobIdentityPub = await bobIdentityKp.extractPublicKey();

      final charlieIdentityKp = await x25519.newKeyPair();

      final senderId = 'alice_in_wonderland';

      final sealedEnvelope = await SealedSender.seal(
        senderId: senderId,
        recipientIdentityPublicKey: bobIdentityPub,
      );

      // Charlie tries to unseal Alice's envelope meant for Bob
      expect(
        () async => await SealedSender.unseal(
          sealedEnvelope: sealedEnvelope,
          myIdentityKeyPair: charlieIdentityKp, // Wrong key!
        ),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });
  });
}
