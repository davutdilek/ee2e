import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'codec.dart';
import 'padding.dart';

/// Grup içindeki göndericinin durumunu tutar (Zincir Anahtarı ve İmza Anahtarı)
class SenderKeyState {
  final int keyId;
  int iteration;
  List<int> chainKey;
  
  final SimpleKeyPair? signatureKeyPair; // Biz göndericiysek var
  final SimplePublicKey signaturePublicKey; // Her zaman var

  SenderKeyState({
    required this.keyId,
    required this.iteration,
    required this.chainKey,
    this.signatureKeyPair,
    required this.signaturePublicKey,
  });

  /// Başlangıç durumunu 1:1 kanal üzerinden paylaşmak için
  Map<String, dynamic> toDistributionJson() {
    return {
      'key_id': keyId,
      'iteration': iteration,
      'chain_key': B64u.encode(chainKey),
      'sig_pub': B64u.encode(signaturePublicKey.bytes),
    };
  }

  static SenderKeyState fromDistributionJson(Map<String, dynamic> json) {
    final sigPubBytes = B64u.decode(json['sig_pub'] as String);
    return SenderKeyState(
      keyId: json['key_id'] as int,
      iteration: json['iteration'] as int,
      chainKey: B64u.decode(json['chain_key'] as String),
      signaturePublicKey: SimplePublicKey(sigPubBytes, type: KeyPairType.ed25519),
    );
  }
}

/// Grup Mesajlarını Şifreleme / Çözme (Sender Keys Protocol)
class GroupCipher {
  final String groupId;
  final String myPeerId;

  // Grup üyelerinin (ben dahil) anahtar durumları.
  // senderId -> SenderKeyState
  final Map<String, SenderKeyState> _states = {};
  
  // Atlanan mesaj anahtarları havuzu (Out-of-order için)
  // "${senderId}_${iteration}" -> MessageKey
  final Map<String, List<int>> _mkSkipped = {};

  final Hmac _hmac = Hmac.sha256();
  final AesGcm _aesGcm = AesGcm.with256bits();
  final Ed25519 _ed25519 = Ed25519();

  GroupCipher({required this.groupId, required this.myPeerId});

  /// Kendimiz için yeni bir Sender Key oluştururuz. (Gruba ilk mesaj atmadan önce)
  Future<SenderKeyState> generateMySenderKey() async {
    final rand = Random.secure();
    final keyId = rand.nextInt(0xFFFFFFFF);
    final initialChainKey = List<int>.generate(32, (_) => rand.nextInt(256));
    final sigKeyPair = await _ed25519.newKeyPair();
    final sigPubKey = await sigKeyPair.extractPublicKey() as SimplePublicKey;

    final state = SenderKeyState(
      keyId: keyId,
      iteration: 0,
      chainKey: initialChainKey,
      signatureKeyPair: sigKeyPair,
      signaturePublicKey: sigPubKey,
    );
    
    _states[myPeerId] = state;
    return state;
  }

  /// Bir başkasından gelen Distribution Message'ı kaydeder.
  void processDistributionMessage(String senderId, Map<String, dynamic> distJson) {
    _states[senderId] = SenderKeyState.fromDistributionJson(distJson);
  }

  /// Gruba gönderilecek mesajı şifreler (My Sender Key kullanılarak)
  Future<Map<String, dynamic>> encrypt(List<int> plaintext) async {
    final state = _states[myPeerId];
    if (state == null) {
      throw Exception('Gönderici anahtarınız bulunamadı. Önce generateMySenderKey() çağrılmalı.');
    }

    final iteration = state.iteration;
    final mk = await _advanceChain(state);

    // Header = (keyId, iteration)
    final header = {
      'key_id': state.keyId,
      'iteration': iteration,
    };
    final headerBytes = utf8.encode(jsonEncode(header));

    final paddedPlaintext = MessagePadding.pad(plaintext);

    // AES-GCM ile şifrele (AD = Header)
    final secretBox = await _aesGcm.encrypt(
      paddedPlaintext,
      secretKey: SecretKey(mk),
      aad: headerBytes,
    );

    final ciphertextWithNonce = [
      ...secretBox.nonce,
      ...secretBox.cipherText,
      ...secretBox.mac.bytes
    ];

    // Şifreli metin + Header'ı imzala
    final payloadToSign = [...headerBytes, ...ciphertextWithNonce];
    final signature = await _ed25519.sign(
      payloadToSign,
      keyPair: state.signatureKeyPair!,
    );

    return {
      'header': header,
      'ciphertext': B64u.encode(ciphertextWithNonce),
      'signature': B64u.encode(signature.bytes),
    };
  }

  /// Gruptan gelen şifreli bir mesajı deşifre eder.
  Future<List<int>> decrypt(String senderId, Map<String, dynamic> message) async {
    final state = _states[senderId];
    if (state == null) {
      throw Exception('Sender $senderId için Sender Key bulunamadı.');
    }

    final headerJson = message['header'] as Map<String, dynamic>;
    final keyId = headerJson['key_id'] as int;
    final iteration = headerJson['iteration'] as int;

    if (keyId != state.keyId) {
      throw Exception('Sender Key ID uyuşmazlığı. Eski/yeni bir distribution mesajı gerekiyor.');
    }

    final ciphertextWithNonce = B64u.decode(message['ciphertext'] as String);
    final signatureBytes = B64u.decode(message['signature'] as String);

    final headerBytes = utf8.encode(jsonEncode(headerJson));
    final payloadToSign = [...headerBytes, ...ciphertextWithNonce];

    // 1. İmzayı doğrula
    final isAuthentic = await _ed25519.verify(
      payloadToSign,
      signature: Signature(signatureBytes, publicKey: state.signaturePublicKey),
    );
    if (!isAuthentic) {
      throw Exception('Grup mesajının imzası GEÇERSİZ!');
    }

    // 2. Mesaj Anahtarını (Message Key) bul (Skipped keys kontrolü dahil)
    final mk = await _getMessageKey(senderId, state, iteration);

    // 3. Deşifre Et
    if (ciphertextWithNonce.length < 12 + 16) throw Exception('Ciphertext çok kısa');
    final nonce = ciphertextWithNonce.sublist(0, 12);
    final ciphertext = ciphertextWithNonce.sublist(12, ciphertextWithNonce.length - 16);
    final mac = ciphertextWithNonce.sublist(ciphertextWithNonce.length - 16);

    final secretBox = SecretBox(ciphertext, nonce: nonce, mac: Mac(mac));

    final paddedPlaintext = await _aesGcm.decrypt(
      secretBox,
      secretKey: SecretKey(mk),
      aad: headerBytes,
    );
    
    return MessagePadding.unpad(paddedPlaintext);
  }

  Future<List<int>> _getMessageKey(String senderId, SenderKeyState state, int targetIteration) async {
    final skippedKey = "${senderId}_$targetIteration";
    if (_mkSkipped.containsKey(skippedKey)) {
      return _mkSkipped.remove(skippedKey)!;
    }

    if (state.iteration > targetIteration) {
      throw Exception('Mesaj anahtarı atlananlar arasında bulunamadı ve zincir bu iterasyonu geçmiş.');
    }

    if (targetIteration - state.iteration > 2000) {
      throw Exception('Çok fazla mesaj atlandı (2000 limit).');
    }

    while (state.iteration < targetIteration) {
      final skippedMk = await _advanceChain(state);
      _mkSkipped["${senderId}_${state.iteration - 1}"] = skippedMk;
    }

    // Hedef iterasyona geldik
    return await _advanceChain(state);
  }

  Future<List<int>> _advanceChain(SenderKeyState state) async {
    final secretKey = SecretKey(state.chainKey);
    final mkMac = await _hmac.calculateMac([0x01], secretKey: secretKey);
    final ckMac = await _hmac.calculateMac([0x02], secretKey: secretKey);
    
    state.chainKey = ckMac.bytes;
    state.iteration++;
    
    return mkMac.bytes;
  }
}
