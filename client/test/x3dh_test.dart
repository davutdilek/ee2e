import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ee2e/crypto/codec.dart';
import 'package:ee2e/crypto/identity.dart';
import 'package:ee2e/crypto/x3dh.dart';

void main() {
  group('X3DH Protocol', () {
    test('Alice ve Bob ayni Shared Secret (SK) degerini uretmelidir (OPK ile)', () async {
      // 1. Bob'un anahtarlarini uret
      final bobIdentity = await Identity.generate(handle: 'bob');
      final bobSpk = await SignedPreKey.generate(identity: bobIdentity, id: 1);
      final bobOpk = await OneTimePreKey.generate(id: 100);

      // 2. Bob'un bundle'ini olustur (Sanki sunucudan indirilmis gibi)
      final bobBundle = await PublicKeyBundle.from(
        identity: bobIdentity,
        spk: bobSpk,
        opks: [bobOpk],
      );
      final fetchedBundle = FetchedBundle.fromJson(bobBundle.toJson());
      // Ilk (ve tek) OPK'yi sec
      final fetchedBundleWithOpk = FetchedBundle(
        handle: fetchedBundle.handle,
        identityDhKey: fetchedBundle.identityDhKey,
        identitySignKey: fetchedBundle.identitySignKey,
        signedPreKeyId: fetchedBundle.signedPreKeyId,
        signedPreKey: fetchedBundle.signedPreKey,
        spkSignature: fetchedBundle.spkSignature,
        oneTimePreKey: fetchedBundle.oneTimePreKey,
      ); // json parser zaten listeyi okumaz, sadece 'one_time_prekey' field varsa alir.
      // PublicKeyBundle.toJson() list dondurur, FetchBundle tek OPK bekler,
      // Json'i uygun sekle getirelim:
      final fetchedJson = bobBundle.toJson();
      fetchedJson['one_time_prekey'] = fetchedJson['one_time_prekeys'][0];
      final bobFetchedBundle = FetchedBundle.fromJson(fetchedJson);

      // 3. Alice kendi kimligini uretir
      final aliceIdentity = await Identity.generate(handle: 'alice');

      // 4. Alice X3DH baslatir
      final aliceResult = await X3dh.deriveAsInitiator(
        myIdentity: aliceIdentity,
        peerBundle: bobFetchedBundle,
      );

      final aliceSk = await aliceResult.sharedKey.extractBytes();

      // 5. Bob, Alice'in gonderdigi header'i isler
      final bobSkResult = await X3dh.deriveAsResponder(
        header: aliceResult.header,
        myIdentity: bobIdentity,
        mySignedPreKey: bobSpk.keyPair,
        myOneTimePreKey: bobOpk.keyPair,
      );

      final bobSk = await bobSkResult.extractBytes();

      // 6. SK_alice == SK_bob olmali
      expect(aliceSk, equals(bobSk));
    });

    test('SPK-only fallback durumunda da ayni SK uretilmelidir', () async {
      final bobIdentity = await Identity.generate(handle: 'bob');
      final bobSpk = await SignedPreKey.generate(identity: bobIdentity, id: 1);
      // OPK yok

      final bobBundle = await PublicKeyBundle.from(
        identity: bobIdentity,
        spk: bobSpk,
        opks: [],
      );
      final fetchedJson = bobBundle.toJson();
      fetchedJson['one_time_prekey'] = null; // OPK havuzu bos
      final bobFetchedBundle = FetchedBundle.fromJson(fetchedJson);

      final aliceIdentity = await Identity.generate(handle: 'alice');

      final aliceResult = await X3dh.deriveAsInitiator(
        myIdentity: aliceIdentity,
        peerBundle: bobFetchedBundle,
      );

      final aliceSk = await aliceResult.sharedKey.extractBytes();

      final bobSkResult = await X3dh.deriveAsResponder(
        header: aliceResult.header,
        myIdentity: bobIdentity,
        mySignedPreKey: bobSpk.keyPair,
        myOneTimePreKey: null,
      );

      final bobSk = await bobSkResult.extractBytes();

      expect(aliceSk, equals(bobSk));
    });

    test('SPK imzasi gecersizse Exception firlatmali', () async {
      final bobIdentity = await Identity.generate(handle: 'bob');
      final bobSpk = await SignedPreKey.generate(identity: bobIdentity, id: 1);

      // Bundle olustur
      final bobBundle = await PublicKeyBundle.from(
        identity: bobIdentity,
        spk: bobSpk,
        opks: [],
      );

      // Imzayi boz
      final fetchedJson = bobBundle.toJson();
      fetchedJson['one_time_prekey'] = null;
      // SPK imzasini gecersiz bir base64 ile degistir
      final badSigBytes = List<int>.filled(64, 0);
      fetchedJson['spk_signature'] = B64u.encode(badSigBytes);
      
      final badBundle = FetchedBundle.fromJson(fetchedJson);

      final aliceIdentity = await Identity.generate(handle: 'alice');

      expect(
        () async => await X3dh.deriveAsInitiator(
          myIdentity: aliceIdentity,
          peerBundle: badBundle,
        ),
        throwsException,
      );
    });
  });
}
