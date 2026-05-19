import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'codec.dart';
import 'padding.dart';

class DoubleRatchetHeader {
  final PublicKey dh;
  final int n;
  final int pn;

  DoubleRatchetHeader(this.dh, this.n, this.pn);

  List<int> toBytes() {
    final builder = BytesBuilder();
    builder.add((dh as SimplePublicKey).bytes);
    final nBytes = ByteData(4)..setUint32(0, n, Endian.big);
    builder.add(nBytes.buffer.asUint8List());
    final pnBytes = ByteData(4)..setUint32(0, pn, Endian.big);
    builder.add(pnBytes.buffer.asUint8List());
    return builder.toBytes();
  }

  static DoubleRatchetHeader fromBytes(List<int> bytes) {
    if (bytes.length < 40) throw Exception('Header too short');
    final dhBytes = bytes.sublist(0, 32);
    final dh = SimplePublicKey(dhBytes, type: KeyPairType.x25519);
    final bd = ByteData.sublistView(Uint8List.fromList(bytes), 32, 40);
    final n = bd.getUint32(0, Endian.big);
    final pn = bd.getUint32(4, Endian.big);
    return DoubleRatchetHeader(dh, n, pn);
  }
}

class DoubleRatchet {
  final X25519 _x25519 = X25519();
  final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 64);
  final Hmac _hmac = Hmac.sha256();
  final AesGcm _aesGcm = AesGcm.with256bits();

  SimpleKeyPair _dhS; // Self DH key pair
  PublicKey? _dhR; // Remote DH public key
  List<int> _rk; // Root key
  List<int>? _ckS; // Sending chain key
  List<int>? _ckR; // Receiving chain key
  int _nS = 0; // Sending message number
  int _nR = 0; // Receiving message number
  int _pn = 0; // Previous sending chain length

  final Map<String, List<int>> _mkSkipped = {};

  DoubleRatchet._({
    required SimpleKeyPair dhS,
    PublicKey? dhR,
    required List<int> rk,
    List<int>? ckS,
    List<int>? ckR,
  })  : _dhS = dhS,
        _dhR = dhR,
        _rk = rk,
        _ckS = ckS,
        _ckR = ckR;

  static Future<DoubleRatchet> initAlice(List<int> sk, PublicKey bobDhPublicKey) async {
    final x25519 = X25519();
    final dhS = await x25519.newKeyPair();
    
    final dr = DoubleRatchet._(
      dhS: dhS,
      dhR: bobDhPublicKey,
      rk: sk,
    );
    
    final dhOut = await dr._x25519.sharedSecretKey(
      keyPair: dr._dhS,
      remotePublicKey: dr._dhR!,
    );
    final dhOutBytes = await dhOut.extractBytes();
    final rkCk = await dr._kdfRk(dr._rk, dhOutBytes);
    dr._rk = rkCk[0];
    dr._ckS = rkCk[1];
    return dr;
  }

  static Future<DoubleRatchet> initBob(List<int> sk, SimpleKeyPair bobDhKeyPair) async {
    return DoubleRatchet._(
      dhS: bobDhKeyPair,
      dhR: null,
      rk: sk,
    );
  }

  Future<Map<String, dynamic>> encryptMessage(List<int> plaintext) async {
    if (_ckS == null) {
      throw Exception('Sending chain is not initialized yet');
    }
    
    final ckMk = await _kdfCk(_ckS!);
    _ckS = ckMk[0];
    final mk = ckMk[1];
    
    final pubKey = await _dhS.extractPublicKey();
    final header = DoubleRatchetHeader(pubKey, _nS, _pn);
    _nS++;
    
    final ad = header.toBytes();
    final paddedPlaintext = MessagePadding.pad(plaintext);
    final secretBox = await _aesGcm.encrypt(
      paddedPlaintext,
      secretKey: SecretKey(mk),
      aad: ad,
    );
    
    final ciphertext = [...secretBox.nonce, ...secretBox.cipherText, ...secretBox.mac.bytes];
    
    return {
      'header': {
        'dh': B64u.encode((pubKey as SimplePublicKey).bytes),
        'n': header.n,
        'pn': header.pn,
      },
      'ciphertext': B64u.encode(ciphertext),
    };
  }

  Future<List<int>> decryptMessage(Map<String, dynamic> message) async {
    final headerJson = message['header'];
    final dhBytes = B64u.decode(headerJson['dh']);
    final dh = SimplePublicKey(dhBytes, type: KeyPairType.x25519);
    final n = headerJson['n'] as int;
    final pn = headerJson['pn'] as int;
    final header = DoubleRatchetHeader(dh, n, pn);
    
    final ciphertext = B64u.decode(message['ciphertext']);
    
    // Check skipped keys
    final mk = await _trySkipMessageKeys(header);
    if (mk != null) {
      return _decrypt(mk, ciphertext, header.toBytes());
    }
    
    final currentDhR = _dhR;
    if (currentDhR == null || B64u.encode((currentDhR as SimplePublicKey).bytes) != B64u.encode(dhBytes)) {
      await _skipMessageKeys(header.pn);
      await _dhRatchet(dh);
    }
    
    await _skipMessageKeys(header.n);
    
    final ckMk = await _kdfCk(_ckR!);
    _ckR = ckMk[0];
    final messageKey = ckMk[1];
    _nR++;
    
    return _decrypt(messageKey, ciphertext, header.toBytes());
  }

  Future<List<int>?> _trySkipMessageKeys(DoubleRatchetHeader header) async {
    final dhBase64 = B64u.encode((header.dh as SimplePublicKey).bytes);
    final key = "${dhBase64}_${header.n}";
    if (_mkSkipped.containsKey(key)) {
      return _mkSkipped.remove(key);
    }
    return null;
  }

  Future<void> _skipMessageKeys(int until) async {
    if (_ckR == null) return;
    if (_nR + 2000 < until) {
      throw Exception('Too many skipped messages');
    }
    while (_nR < until) {
      final ckMk = await _kdfCk(_ckR!);
      _ckR = ckMk[0];
      final mk = ckMk[1];
      
      final dhBase64 = B64u.encode((_dhR as SimplePublicKey).bytes);
      _mkSkipped["${dhBase64}_$_nR"] = mk;
      _nR++;
    }
  }

  Future<void> _dhRatchet(PublicKey newDhR) async {
    _pn = _nS;
    _nS = 0;
    _nR = 0;
    _dhR = newDhR;
    
    // Receiver chain
    var dhOut = await _x25519.sharedSecretKey(keyPair: _dhS, remotePublicKey: _dhR!);
    var dhOutBytes = await dhOut.extractBytes();
    var rkCk = await _kdfRk(_rk, dhOutBytes);
    _rk = rkCk[0];
    _ckR = rkCk[1];
    
    // Sender chain
    _dhS = await _x25519.newKeyPair();
    dhOut = await _x25519.sharedSecretKey(keyPair: _dhS, remotePublicKey: _dhR!);
    dhOutBytes = await dhOut.extractBytes();
    rkCk = await _kdfRk(_rk, dhOutBytes);
    _rk = rkCk[0];
    _ckS = rkCk[1];
  }

  Future<List<List<int>>> _kdfRk(List<int> rk, List<int> dhOut) async {
    final secretKey = SecretKey(dhOut);
    final output = await _hkdf.deriveKey(
      secretKey: secretKey,
      nonce: rk,
      info: utf8.encode('EE2E_Ratchet'),
    );
    final bytes = await output.extractBytes();
    return [bytes.sublist(0, 32), bytes.sublist(32, 64)];
  }

  Future<List<List<int>>> _kdfCk(List<int> ck) async {
    final secretKey = SecretKey(ck);
    final mkMac = await _hmac.calculateMac([0x01], secretKey: secretKey);
    final ckMac = await _hmac.calculateMac([0x02], secretKey: secretKey);
    return [ckMac.bytes, mkMac.bytes];
  }

  Future<List<int>> _decrypt(List<int> mk, List<int> ciphertextWithNonce, List<int> ad) async {
    if (ciphertextWithNonce.length < 12 + 16) throw Exception('Ciphertext too short');
    final nonce = ciphertextWithNonce.sublist(0, 12);
    final ciphertext = ciphertextWithNonce.sublist(12, ciphertextWithNonce.length - 16);
    final mac = ciphertextWithNonce.sublist(ciphertextWithNonce.length - 16);
    
    final secretBox = SecretBox(
      ciphertext,
      nonce: nonce,
      mac: Mac(mac),
    );
    
    final paddedPlaintext = await _aesGcm.decrypt(
      secretBox,
      secretKey: SecretKey(mk),
      aad: ad,
    );
    
    return MessagePadding.unpad(paddedPlaintext);
  }
}
