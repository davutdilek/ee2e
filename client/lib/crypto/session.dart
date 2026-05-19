import 'dart:convert';
import 'package:cryptography/cryptography.dart';

import 'package:ee2e/crypto/identity.dart';
import 'package:ee2e/crypto/x3dh.dart';
import 'package:ee2e/crypto/x3dh_header.dart';
import 'package:ee2e/crypto/double_ratchet.dart';
import 'package:ee2e/storage/secure_keys.dart';

class E2eSession {
  final String peerId;
  final DoubleRatchet ratchet;
  
  // Initiator needs to send this header with the first message(s)
  X3dhHeader? pendingX3dhHeader;

  E2eSession._({
    required this.peerId,
    required this.ratchet,
    this.pendingX3dhHeader,
  });

  /// Alice initializes session
  static Future<E2eSession> createAsInitiator({
    required String peerId,
    required FetchedBundle peerBundle,
    required Identity myIdentity,
  }) async {
    final x3dhRes = await X3dh.deriveAsInitiator(
      peerBundle: peerBundle,
      myIdentity: myIdentity,
    );

    final skBytes = await x3dhRes.sharedKey.extractBytes();
    final peerSpk = SimplePublicKey(peerBundle.signedPreKey, type: KeyPairType.x25519);

    final dr = await DoubleRatchet.initAlice(
      skBytes,
      peerSpk, // Bob's SPK public key is the initial DHr
    );

    return E2eSession._(
      peerId: peerId,
      ratchet: dr,
      pendingX3dhHeader: x3dhRes.header,
    );
  }

  /// Bob creates session from incoming first message
  static Future<E2eSession> createAsResponder({
    required String peerId,
    required X3dhHeader header,
    required Identity myIdentity,
    required SimpleKeyPair mySignedPreKey,
    SimpleKeyPair? myOneTimePreKey,
  }) async {
    final sk = await X3dh.deriveAsResponder(
      header: header,
      myIdentity: myIdentity,
      mySignedPreKey: mySignedPreKey,
      myOneTimePreKey: myOneTimePreKey,
    );
    final skBytes = await sk.extractBytes();

    final dr = await DoubleRatchet.initBob(
      skBytes,
      mySignedPreKey, // Bob's SPK is the initial DHs
    );

    return E2eSession._(
      peerId: peerId,
      ratchet: dr,
    );
  }

  Future<Map<String, dynamic>> encrypt(String plaintext) async {
    final payload = await ratchet.encryptMessage(utf8.encode(plaintext));
    
    if (pendingX3dhHeader != null) {
      final res = {
        'type': 'prekey_message',
        'x3dh': pendingX3dhHeader!.toJson(),
        'ratchet': payload,
      };
      return res;
    }

    return {
      'type': 'message',
      'ratchet': payload,
    };
  }

  Future<String> decrypt(Map<String, dynamic> wireMessage) async {
    // If we receive a message from the responder, our handshake is fully complete.
    // We can clear our pending X3DH header so we stop sending it.
    pendingX3dhHeader = null;

    final ratchetPayload = wireMessage['ratchet'];
    if (ratchetPayload == null) {
      throw Exception('Missing ratchet payload in message');
    }
    
    final decryptedBytes = await ratchet.decryptMessage(ratchetPayload);
    return utf8.decode(decryptedBytes);
  }
}

class SessionManager {
  static final SessionManager _instance = SessionManager._internal();
  
  factory SessionManager() {
    return _instance;
  }
  
  SessionManager._internal();

  final Map<String, E2eSession> _sessions = {};
  
  E2eSession? getSession(String peerId) => _sessions[peerId];
  
  void saveSession(E2eSession session) {
    _sessions[session.peerId] = session;
  }
  
  void removeSession(String peerId) {
    _sessions.remove(peerId);
  }
  
  void clear() {
    _sessions.clear();
  }
}
