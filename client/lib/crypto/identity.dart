import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'codec.dart';

/// EE2E uzun-ömürlü kimlik anahtarı.
///
/// Identity iki keypair tutar:
///   - dh   (X25519): X3DH'nin Diffie-Hellman tarafı
///   - sign (Ed25519): SPK signature ve gelecekte kimlik doğrulama
///
/// Private key'ler [SecureKeyStore] üzerinden cihazın güvenli alanına yazılır;
/// bu sınıf bellekte tutar ama disk'e kendisi yazmaz.
class Identity {
  Identity({
    required this.handle,
    required this.dhKeyPair,
    required this.signKeyPair,
  });

  final String handle;
  final SimpleKeyPair dhKeyPair;
  final SimpleKeyPair signKeyPair;

  static final _x25519 = Cryptography.instance.x25519();
  static final _ed25519 = Cryptography.instance.ed25519();

  /// Yeni bir kimlik üretir (cihaz ilk kez açıldığında).
  static Future<Identity> generate({required String handle}) async {
    final dh = await _x25519.newKeyPair();
    final sig = await _ed25519.newKeyPair();
    return Identity(handle: handle, dhKeyPair: dh, signKeyPair: sig);
  }

  Future<Uint8List> dhPublicBytes() async {
    final pk = await dhKeyPair.extractPublicKey();
    return Uint8List.fromList(pk.bytes);
  }

  Future<Uint8List> signPublicBytes() async {
    final pk = await signKeyPair.extractPublicKey();
    return Uint8List.fromList(pk.bytes);
  }
}

/// İmzalı ön-anahtar (Signed Pre-Key).
///
/// Periyodik olarak (haftalık) yenilenir, eski olan rotation sırasında
/// rotated_at'i ile birlikte arşivlenir (gelmiş ve henüz teslim edilmemiş
/// mesajlar için).
class SignedPreKey {
  SignedPreKey({
    required this.id,
    required this.keyPair,
    required this.signature,
  });

  final int id;
  final SimpleKeyPair keyPair;

  /// Ed25519 imzası — Identity.signKeyPair tarafından, public key bytes üzerine.
  final Uint8List signature;

  static final _x25519 = Cryptography.instance.x25519();
  static final _ed25519 = Cryptography.instance.ed25519();

  static Future<SignedPreKey> generate({
    required Identity identity,
    required int id,
  }) async {
    final kp = await _x25519.newKeyPair();
    final pub = await kp.extractPublicKey();
    final sig = await _ed25519.sign(pub.bytes, keyPair: identity.signKeyPair);
    return SignedPreKey(
      id: id,
      keyPair: kp,
      signature: Uint8List.fromList(sig.bytes),
    );
  }

  Future<Uint8List> publicBytes() async {
    final pk = await keyPair.extractPublicKey();
    return Uint8List.fromList(pk.bytes);
  }

  /// Verilen identity_sign_key public bytes ile imzayı doğrular.
  static Future<bool> verify({
    required List<int> spkPublic,
    required List<int> signature,
    required List<int> identitySignPublic,
  }) async {
    final sig = Signature(
      signature,
      publicKey: SimplePublicKey(identitySignPublic, type: KeyPairType.ed25519),
    );
    return _ed25519.verify(spkPublic, signature: sig);
  }
}

/// Tek kullanımlık ön-anahtar (One-Time Pre-Key).
class OneTimePreKey {
  OneTimePreKey({required this.id, required this.keyPair});

  final int id;
  final SimpleKeyPair keyPair;

  static final _x25519 = Cryptography.instance.x25519();

  static Future<OneTimePreKey> generate({required int id}) async {
    return OneTimePreKey(id: id, keyPair: await _x25519.newKeyPair());
  }

  static Future<List<OneTimePreKey>> generateBatch({
    required int count,
    int startId = 1,
  }) async {
    final result = <OneTimePreKey>[];
    for (var i = 0; i < count; i++) {
      result.add(await generate(id: startId + i));
    }
    return result;
  }

  Future<Uint8List> publicBytes() async {
    final pk = await keyPair.extractPublicKey();
    return Uint8List.fromList(pk.bytes);
  }
}

/// İstemcinin tutması gereken **public** bundle (server'a yüklenecek hali).
class PublicKeyBundle {
  PublicKeyBundle({
    required this.handle,
    required this.identityDhKey,
    required this.identitySignKey,
    required this.signedPreKeyId,
    required this.signedPreKey,
    required this.spkSignature,
    required this.oneTimePreKeys,
  });

  final String handle;
  final Uint8List identityDhKey;
  final Uint8List identitySignKey;
  final int signedPreKeyId;
  final Uint8List signedPreKey;
  final Uint8List spkSignature;
  final List<({int opkId, Uint8List publicKey})> oneTimePreKeys;

  static Future<PublicKeyBundle> from({
    required Identity identity,
    required SignedPreKey spk,
    required List<OneTimePreKey> opks,
  }) async {
    return PublicKeyBundle(
      handle: identity.handle,
      identityDhKey: await identity.dhPublicBytes(),
      identitySignKey: await identity.signPublicBytes(),
      signedPreKeyId: spk.id,
      signedPreKey: await spk.publicBytes(),
      spkSignature: spk.signature,
      oneTimePreKeys: [
        for (final o in opks) (opkId: o.id, publicKey: await o.publicBytes()),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
        'handle': handle,
        'identity_dh_key': B64u.encode(identityDhKey),
        'identity_sign_key': B64u.encode(identitySignKey),
        'signed_prekey_id': signedPreKeyId,
        'signed_prekey': B64u.encode(signedPreKey),
        'spk_signature': B64u.encode(spkSignature),
        'one_time_prekeys': [
          for (final o in oneTimePreKeys)
            {'opk_id': o.opkId, 'public_key': B64u.encode(o.publicKey)},
        ],
      };
}

/// Sunucudan çekilen başkasının bundle'ı (Faz 2B'de X3DH girdisi olur).
class FetchedBundle {
  FetchedBundle({
    required this.handle,
    required this.identityDhKey,
    required this.identitySignKey,
    required this.signedPreKeyId,
    required this.signedPreKey,
    required this.spkSignature,
    required this.oneTimePreKey,
  });

  final String handle;
  final Uint8List identityDhKey;
  final Uint8List identitySignKey;
  final int signedPreKeyId;
  final Uint8List signedPreKey;
  final Uint8List spkSignature;
  final ({int opkId, Uint8List publicKey})? oneTimePreKey;

  static FetchedBundle fromJson(Map<String, dynamic> json) {
    final opkRaw = json['one_time_prekey'];
    return FetchedBundle(
      handle: json['handle'] as String,
      identityDhKey: B64u.decode(json['identity_dh_key'] as String),
      identitySignKey: B64u.decode(json['identity_sign_key'] as String),
      signedPreKeyId: json['signed_prekey_id'] as int,
      signedPreKey: B64u.decode(json['signed_prekey'] as String),
      spkSignature: B64u.decode(json['spk_signature'] as String),
      oneTimePreKey: opkRaw is Map<String, dynamic>
          ? (
              opkId: opkRaw['opk_id'] as int,
              publicKey: B64u.decode(opkRaw['public_key'] as String),
            )
          : null,
    );
  }

  /// SPK signature'ı identity_sign_key ile doğrular.
  /// X3DH'ye girmeden önce ÇAĞRILMASI ZORUNLU.
  Future<bool> verifySpkSignature() {
    return SignedPreKey.verify(
      spkPublic: signedPreKey,
      signature: spkSignature,
      identitySignPublic: identitySignKey,
    );
  }
}
