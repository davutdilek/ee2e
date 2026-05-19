import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../crypto/codec.dart';
import '../crypto/identity.dart';

/// Cihaz güvenli depolama wrapper'ı.
///
/// Plaintext private key bytes asla başka yere yazılmaz; sadece bu sınıf
/// üzerinden okunur/yazılır.
///
/// **Web uyarısı:** flutter_secure_storage web'de IndexedDB tabanlı çalışır,
/// gerçek bir keychain/keystore değildir. Web build "demo only" kabul edilir;
/// production cihazlar (iOS/Android/macOS) gerçek native secure store kullanır.
class SecureKeyStore {
  SecureKeyStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _kHandle = 'ee2e.handle';
  static const _kIdentityDhPriv = 'ee2e.identity.dh.priv';
  static const _kIdentityDhPub = 'ee2e.identity.dh.pub';
  static const _kIdentitySignPriv = 'ee2e.identity.sign.priv';
  static const _kIdentitySignPub = 'ee2e.identity.sign.pub';
  static const _kSpkBlob = 'ee2e.spk.blob';
  static const _kOpkBlob = 'ee2e.opk.blob';

  static final _x25519 = Cryptography.instance.x25519();
  static final _ed25519 = Cryptography.instance.ed25519();

  Future<String?> readHandle() => _storage.read(key: _kHandle);

  Future<bool> hasIdentity() async {
    final h = await readHandle();
    final dh = await _storage.read(key: _kIdentityDhPriv);
    return h != null && dh != null;
  }

  Future<void> saveIdentity(Identity identity) async {
    final dhPriv = await identity.dhKeyPair.extractPrivateKeyBytes();
    final dhPub = (await identity.dhKeyPair.extractPublicKey()).bytes;
    final sigPriv = await identity.signKeyPair.extractPrivateKeyBytes();
    final sigPub = (await identity.signKeyPair.extractPublicKey()).bytes;

    await Future.wait([
      _storage.write(key: _kHandle, value: identity.handle),
      _storage.write(key: _kIdentityDhPriv, value: B64u.encode(dhPriv)),
      _storage.write(key: _kIdentityDhPub, value: B64u.encode(dhPub)),
      _storage.write(key: _kIdentitySignPriv, value: B64u.encode(sigPriv)),
      _storage.write(key: _kIdentitySignPub, value: B64u.encode(sigPub)),
    ]);
  }

  Future<Identity?> loadIdentity() async {
    final handle = await _storage.read(key: _kHandle);
    final dhPrivB = await _storage.read(key: _kIdentityDhPriv);
    final dhPubB = await _storage.read(key: _kIdentityDhPub);
    final sigPrivB = await _storage.read(key: _kIdentitySignPriv);
    final sigPubB = await _storage.read(key: _kIdentitySignPub);
    if (handle == null ||
        dhPrivB == null ||
        dhPubB == null ||
        sigPrivB == null ||
        sigPubB == null) {
      return null;
    }
    final dhKp = await _x25519.newKeyPairFromSeed(B64u.decode(dhPrivB));
    final sigKp = await _ed25519.newKeyPairFromSeed(B64u.decode(sigPrivB));
    return Identity(handle: handle, dhKeyPair: dhKp, signKeyPair: sigKp);
  }

  /// SPK private key + ID + signature blob olarak saklanır.
  Future<void> saveSignedPreKey(SignedPreKey spk) async {
    final priv = await spk.keyPair.extractPrivateKeyBytes();
    final pub = (await spk.keyPair.extractPublicKey()).bytes;
    final blob = jsonEncode({
      'id': spk.id,
      'priv': B64u.encode(priv),
      'pub': B64u.encode(pub),
      'sig': B64u.encode(spk.signature),
    });
    await _storage.write(key: _kSpkBlob, value: blob);
  }

  Future<SignedPreKey?> loadSignedPreKey() async {
    final raw = await _storage.read(key: _kSpkBlob);
    if (raw == null) return null;
    final m = jsonDecode(raw) as Map<String, dynamic>;
    final kp = await _x25519.newKeyPairFromSeed(B64u.decode(m['priv'] as String));
    return SignedPreKey(
      id: m['id'] as int,
      keyPair: kp,
      signature: Uint8List.fromList(B64u.decode(m['sig'] as String)),
    );
  }

  /// OPK havuzu — id → priv map. Tüketilen id'ler `consumeOneTimePreKey` ile silinir.
  Future<void> saveOneTimePreKeys(List<OneTimePreKey> opks) async {
    final list = <Map<String, String>>[];
    for (final o in opks) {
      final priv = await o.keyPair.extractPrivateKeyBytes();
      list.add({'id': '${o.id}', 'priv': B64u.encode(priv)});
    }
    await _storage.write(key: _kOpkBlob, value: jsonEncode(list));
  }

  Future<List<OneTimePreKey>> loadOneTimePreKeys() async {
    final raw = await _storage.read(key: _kOpkBlob);
    if (raw == null) return const [];
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    final result = <OneTimePreKey>[];
    for (final m in list) {
      final kp = await _x25519.newKeyPairFromSeed(B64u.decode(m['priv'] as String));
      result.add(OneTimePreKey(id: int.parse(m['id'] as String), keyPair: kp));
    }
    return result;
  }

  /// Verilen id'li OPK'yı havuzdan kalıcı olarak siler.
  Future<OneTimePreKey?> consumeOneTimePreKey(int id) async {
    final raw = await _storage.read(key: _kOpkBlob);
    if (raw == null) return null;
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    Map<String, dynamic>? hit;
    final remaining = <Map<String, dynamic>>[];
    for (final m in list) {
      if (int.parse(m['id'] as String) == id && hit == null) {
        hit = m;
      } else {
        remaining.add(m);
      }
    }
    if (hit == null) return null;
    await _storage.write(key: _kOpkBlob, value: jsonEncode(remaining));
    final kp = await _x25519.newKeyPairFromSeed(B64u.decode(hit['priv'] as String));
    return OneTimePreKey(id: id, keyPair: kp);
  }

  Future<void> wipe() async {
    await Future.wait([
      _storage.delete(key: _kHandle),
      _storage.delete(key: _kIdentityDhPriv),
      _storage.delete(key: _kIdentityDhPub),
      _storage.delete(key: _kIdentitySignPriv),
      _storage.delete(key: _kIdentitySignPub),
      _storage.delete(key: _kSpkBlob),
      _storage.delete(key: _kOpkBlob),
    ]);
  }
}
