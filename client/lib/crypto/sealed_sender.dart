import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'codec.dart';

/// Sealed Sender (Mühürlü Gönderici) Protokolü
///
/// Sunucu, mesajı kimin gönderdiğini (sender_id) bilemez.
/// Yalnızca alıcının Identity DH Public Key'ini kullanarak gönderici bilgisini şifreleriz.
/// Alıcı, kendi Identity DH Private Key'i ile bu mührü kırarak gerçek göndericiyi öğrenir.
class SealedSender {
  static final _x25519 = X25519();
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static final _aesGcm = AesGcm.with256bits();

  /// Göndericinin kimliğini (senderId), alıcının IK'sı (Identity Key) ile şifreler.
  static Future<Map<String, dynamic>> seal({
    required String senderId,
    required PublicKey recipientIdentityPublicKey,
  }) async {
    // 1. Ephemeral (Geçici) bir anahtar çifti üret
    final ek = await _x25519.newKeyPair();
    final ekPub = await ek.extractPublicKey() as SimplePublicKey;
    
    // 2. ECDH(Geçici Private, Alıcı IK Public) -> Shared Secret
    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: ek,
      remotePublicKey: recipientIdentityPublicKey,
    );
    final sharedSecretBytes = await sharedSecret.extractBytes();
    
    // 3. HKDF ile AES anahtarı türet
    final output = await _hkdf.deriveKey(
      secretKey: SecretKey(sharedSecretBytes),
      nonce: utf8.encode('EE2E_Sealed_Sender_Salt'),
      info: utf8.encode('EE2E_Sealed_Sender'),
    );
    final keyBytes = await output.extractBytes();
    
    // 4. Gönderici ID'sini AES-GCM ile şifrele
    final plaintext = utf8.encode(senderId);
    
    final secretBox = await _aesGcm.encrypt(
      plaintext,
      secretKey: SecretKey(keyBytes),
    );
    
    final ciphertextWithNonce = [
      ...secretBox.nonce,
      ...secretBox.cipherText,
      ...secretBox.mac.bytes
    ];
    
    // 5. Zarfı (Mührü) döndür
    return {
      'ek': B64u.encode(ekPub.bytes),
      'ciphertext': B64u.encode(ciphertextWithNonce),
    };
  }

  /// Alıcı, kendi IK Private anahtarını kullanarak mührü kırar ve göndericiyi öğrenir.
  static Future<String> unseal({
    required Map<String, dynamic> sealedEnvelope,
    required SimpleKeyPair myIdentityKeyPair,
  }) async {
    final ekBytes = B64u.decode(sealedEnvelope['ek'] as String);
    final ekPub = SimplePublicKey(ekBytes, type: KeyPairType.x25519);
    
    // 1. ECDH(Benim IK Private, Geçici Public) -> Shared Secret
    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: myIdentityKeyPair,
      remotePublicKey: ekPub,
    );
    final sharedSecretBytes = await sharedSecret.extractBytes();
    
    // 2. Aynı HKDF mantığıyla AES anahtarını türet
    final output = await _hkdf.deriveKey(
      secretKey: SecretKey(sharedSecretBytes),
      nonce: utf8.encode('EE2E_Sealed_Sender_Salt'),
      info: utf8.encode('EE2E_Sealed_Sender'),
    );
    final keyBytes = await output.extractBytes();
    
    // 3. AES-GCM ile şifreyi çöz
    final ciphertextWithNonce = B64u.decode(sealedEnvelope['ciphertext'] as String);
    if (ciphertextWithNonce.length < 12 + 16) throw Exception('Mühür çok kısa (Bozuk/Geçersiz)');
    
    final nonce = ciphertextWithNonce.sublist(0, 12);
    final ciphertext = ciphertextWithNonce.sublist(12, ciphertextWithNonce.length - 16);
    final mac = ciphertextWithNonce.sublist(ciphertextWithNonce.length - 16);
    
    final secretBox = SecretBox(ciphertext, nonce: nonce, mac: Mac(mac));
    final plaintext = await _aesGcm.decrypt(
      secretBox,
      secretKey: SecretKey(keyBytes),
    );
    
    // 4. Göndericinin kimliğini döndür
    return utf8.decode(plaintext);
  }
}
