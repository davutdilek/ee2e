import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:ee2e/crypto/codec.dart';
import 'package:ee2e/crypto/identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('B64u', () {
    test('roundtrip without padding', () {
      final bytes = List<int>.generate(32, (i) => i);
      final encoded = B64u.encode(bytes);
      expect(encoded.contains('='), isFalse);
      expect(B64u.decode(encoded), bytes);
    });

    test('decode tolerates missing padding', () {
      final bytes = [1, 2, 3];
      final stripped = B64u.encode(bytes);
      expect(B64u.decode(stripped), bytes);
    });
  });

  group('Identity', () {
    test('generate produces 32-byte X25519 + Ed25519 publics', () async {
      final id = await Identity.generate(handle: 'ali');
      expect(id.handle, 'ali');
      expect((await id.dhPublicBytes()).length, 32);
      expect((await id.signPublicBytes()).length, 32);
    });

    test('two generations produce different keys', () async {
      final a = await Identity.generate(handle: 'ali');
      final b = await Identity.generate(handle: 'ali');
      expect(await a.dhPublicBytes(), isNot(await b.dhPublicBytes()));
      expect(await a.signPublicBytes(), isNot(await b.signPublicBytes()));
    });
  });

  group('SignedPreKey', () {
    test('sign + verify roundtrip succeeds', () async {
      final id = await Identity.generate(handle: 'ali');
      final spk = await SignedPreKey.generate(identity: id, id: 1);
      final ok = await SignedPreKey.verify(
        spkPublic: await spk.publicBytes(),
        signature: spk.signature,
        identitySignPublic: await id.signPublicBytes(),
      );
      expect(ok, isTrue);
    });

    test('verify fails with wrong identity sign key', () async {
      final ali = await Identity.generate(handle: 'ali');
      final eve = await Identity.generate(handle: 'eve');
      final spk = await SignedPreKey.generate(identity: ali, id: 1);
      final ok = await SignedPreKey.verify(
        spkPublic: await spk.publicBytes(),
        signature: spk.signature,
        identitySignPublic: await eve.signPublicBytes(),
      );
      expect(ok, isFalse);
    });

    test('verify fails when SPK bytes tampered', () async {
      final ali = await Identity.generate(handle: 'ali');
      final spk = await SignedPreKey.generate(identity: ali, id: 1);
      final tampered = List<int>.from(await spk.publicBytes());
      tampered[0] ^= 0xff;
      final ok = await SignedPreKey.verify(
        spkPublic: tampered,
        signature: spk.signature,
        identitySignPublic: await ali.signPublicBytes(),
      );
      expect(ok, isFalse);
    });
  });

  group('OneTimePreKey batch', () {
    test('100 unique keys', () async {
      final batch = await OneTimePreKey.generateBatch(count: 100);
      expect(batch.length, 100);
      expect(batch.first.id, 1);
      expect(batch.last.id, 100);
      final pubs = <String>{};
      for (final o in batch) {
        pubs.add(B64u.encode(await o.publicBytes()));
      }
      expect(pubs.length, 100);
    });
  });

  group('PublicKeyBundle JSON', () {
    test('matches server schema fields', () async {
      final id = await Identity.generate(handle: 'ali');
      final spk = await SignedPreKey.generate(identity: id, id: 7);
      final opks = await OneTimePreKey.generateBatch(count: 3);
      final bundle =
          await PublicKeyBundle.from(identity: id, spk: spk, opks: opks);
      final j = bundle.toJson();
      expect(j.keys.toSet(), {
        'handle',
        'identity_dh_key',
        'identity_sign_key',
        'signed_prekey_id',
        'signed_prekey',
        'spk_signature',
        'one_time_prekeys',
      });
      expect(j['handle'], 'ali');
      expect(j['signed_prekey_id'], 7);
      final opksJson = j['one_time_prekeys'] as List;
      expect(opksJson.length, 3);
      expect((opksJson.first as Map)['opk_id'], 1);

      // base64url roundtrip via jsonEncode (must not throw, must be ascii).
      final encoded = jsonEncode(j);
      expect(encoded.contains('"handle":"ali"'), isTrue);
    });
  });

  group('FetchedBundle parsing', () {
    test('parses with OPK', () async {
      final id = await Identity.generate(handle: 'ayse');
      final spk = await SignedPreKey.generate(identity: id, id: 4);
      final opk = await OneTimePreKey.generate(id: 42);
      final j = {
        'handle': 'ayse',
        'identity_dh_key': B64u.encode(await id.dhPublicBytes()),
        'identity_sign_key': B64u.encode(await id.signPublicBytes()),
        'signed_prekey_id': 4,
        'signed_prekey': B64u.encode(await spk.publicBytes()),
        'spk_signature': B64u.encode(spk.signature),
        'one_time_prekey': {
          'opk_id': 42,
          'public_key': B64u.encode(await opk.publicBytes()),
        },
      };
      final fetched = FetchedBundle.fromJson(j);
      expect(fetched.handle, 'ayse');
      expect(fetched.signedPreKeyId, 4);
      expect(fetched.oneTimePreKey?.opkId, 42);
      expect(await fetched.verifySpkSignature(), isTrue);
    });

    test('parses with null OPK (SPK-only fallback)', () async {
      final id = await Identity.generate(handle: 'ayse');
      final spk = await SignedPreKey.generate(identity: id, id: 1);
      final j = {
        'handle': 'ayse',
        'identity_dh_key': B64u.encode(await id.dhPublicBytes()),
        'identity_sign_key': B64u.encode(await id.signPublicBytes()),
        'signed_prekey_id': 1,
        'signed_prekey': B64u.encode(await spk.publicBytes()),
        'spk_signature': B64u.encode(spk.signature),
        'one_time_prekey': null,
      };
      final fetched = FetchedBundle.fromJson(j);
      expect(fetched.oneTimePreKey, isNull);
      expect(await fetched.verifySpkSignature(), isTrue);
    });
  });

  test('cryptography library is properly wired (X25519 ECDH works)',
      () async {
    final x25519 = Cryptography.instance.x25519();
    final a = await x25519.newKeyPair();
    final b = await x25519.newKeyPair();
    final aShared = await x25519.sharedSecretKey(
      keyPair: a,
      remotePublicKey: await b.extractPublicKey(),
    );
    final bShared = await x25519.sharedSecretKey(
      keyPair: b,
      remotePublicKey: await a.extractPublicKey(),
    );
    expect(await aShared.extractBytes(), await bShared.extractBytes());
  });
}
