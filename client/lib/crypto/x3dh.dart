import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'identity.dart';
import 'x3dh_header.dart';

/// X3DH (Extended Triple Diffie-Hellman) Protokolü Gerçeklemesi
class X3dh {
  static final _x25519 = Cryptography.instance.x25519();

  /// Alice (Initiator) Bob'un bundle'ını kullanarak X3DH yapar.
  /// Geriye türetilen [SecretKey] ve Bob'a gönderilecek [X3dhHeader] döner.
  static Future<({SecretKey sharedKey, X3dhHeader header})> deriveAsInitiator({
    required Identity myIdentity,
    required FetchedBundle peerBundle,
  }) async {
    // 1. SPK imzasını doğrula (Güvenlik Kalkanı)
    final isValid = await peerBundle.verifySpkSignature();
    if (!isValid) {
      throw Exception('X3DH: Peer SPK signature is invalid!');
    }

    // 2. Yeni bir Ephemeral Key (EK_A) üret
    final ekA = await _x25519.newKeyPair();
    final ekAPublic = await ekA.extractPublicKey();

    // Peer public key'lerini hazırla
    final spkB = SimplePublicKey(peerBundle.signedPreKey, type: KeyPairType.x25519);
    final ikB = SimplePublicKey(peerBundle.identityDhKey, type: KeyPairType.x25519);

    // 3. DH adımları
    // DH1 = DH(IK_A, SPK_B)
    final dh1 = await _x25519.sharedSecretKey(keyPair: myIdentity.dhKeyPair, remotePublicKey: spkB);
    // DH2 = DH(EK_A, IK_B)
    final dh2 = await _x25519.sharedSecretKey(keyPair: ekA, remotePublicKey: ikB);
    // DH3 = DH(EK_A, SPK_B)
    final dh3 = await _x25519.sharedSecretKey(keyPair: ekA, remotePublicKey: spkB);

    SecretKey? dh4;
    int? usedOpkId;
    if (peerBundle.oneTimePreKey != null) {
      final opkB = SimplePublicKey(peerBundle.oneTimePreKey!.publicKey, type: KeyPairType.x25519);
      // DH4 = DH(EK_A, OPK_B)
      dh4 = await _x25519.sharedSecretKey(keyPair: ekA, remotePublicKey: opkB);
      usedOpkId = peerBundle.oneTimePreKey!.opkId;
    }

    // 4. KDF ile SK türet
    final km = await _concatSharedSecrets(dh1, dh2, dh3, dh4: dh4);
    final sk = await _hkdf(km);

    // 5. Header'ı oluştur
    final header = X3dhHeader(
      senderIk: await myIdentity.dhPublicBytes(),
      senderEk: Uint8List.fromList(ekAPublic.bytes),
      recipientSpkId: peerBundle.signedPreKeyId,
      recipientOpkId: usedOpkId,
    );

    return (sharedKey: sk, header: header);
  }

  /// Bob (Responder) Alice'ten gelen header ve kendi anahtarlarıyla X3DH yapar.
  static Future<SecretKey> deriveAsResponder({
    required X3dhHeader header,
    required Identity myIdentity,
    required SimpleKeyPair mySignedPreKey,
    SimpleKeyPair? myOneTimePreKey,
  }) async {
    // Peer public key'lerini hazırla
    final ikA = SimplePublicKey(header.senderIk, type: KeyPairType.x25519);
    final ekA = SimplePublicKey(header.senderEk, type: KeyPairType.x25519);

    // 3. DH adımları (Bob'un perspektifi)
    // DH1 = DH(SPK_B, IK_A)
    final dh1 = await _x25519.sharedSecretKey(keyPair: mySignedPreKey, remotePublicKey: ikA);
    // DH2 = DH(IK_B, EK_A)
    final dh2 = await _x25519.sharedSecretKey(keyPair: myIdentity.dhKeyPair, remotePublicKey: ekA);
    // DH3 = DH(SPK_B, EK_A)
    final dh3 = await _x25519.sharedSecretKey(keyPair: mySignedPreKey, remotePublicKey: ekA);

    SecretKey? dh4;
    if (header.recipientOpkId != null) {
      if (myOneTimePreKey == null) {
        throw Exception('X3DH: Alice used an OPK, but Bob did not provide it!');
      }
      // DH4 = DH(OPK_B, EK_A)
      dh4 = await _x25519.sharedSecretKey(keyPair: myOneTimePreKey, remotePublicKey: ekA);
    }

    // 4. KDF ile SK türet
    final km = await _concatSharedSecrets(dh1, dh2, dh3, dh4: dh4);
    final sk = await _hkdf(km);

    return sk;
  }

  static Future<List<int>> _concatSharedSecrets(
    SecretKey dh1,
    SecretKey dh2,
    SecretKey dh3, {
    SecretKey? dh4,
  }) async {
    final b1 = await dh1.extractBytes();
    final b2 = await dh2.extractBytes();
    final b3 = await dh3.extractBytes();
    final b4 = dh4 != null ? await dh4.extractBytes() : <int>[];

    // Signal Spesifikasyonu: KM = F || DH1 || DH2 || DH3 || DH4
    // F = 32 bytes of 0xFF
    final f = List<int>.filled(32, 0xFF);

    return [...f, ...b1, ...b2, ...b3, ...b4];
  }

  static Future<SecretKey> _hkdf(List<int> inputKeyMaterial) async {
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    // Salt: 32 bytes of zeros
    final salt = List<int>.filled(32, 0);
    final info = utf8.encode('EE2E_X3DH');

    final sk = await hkdf.deriveKey(
      secretKey: SecretKey(inputKeyMaterial),
      nonce: salt,
      info: info,
    );
    return sk;
  }
}
