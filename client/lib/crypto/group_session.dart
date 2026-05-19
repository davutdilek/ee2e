import 'dart:convert';
import 'package:cryptography/cryptography.dart';

import 'package:ee2e/crypto/sender_key.dart';
import 'package:ee2e/crypto/sealed_sender.dart';

/// Bir grup sohbetini yöneten sınıf.
///
/// Gelen mesajları gruba özel GroupCipher ile çözer.
/// Giden mesajlarda isteğe bağlı olarak Sealed Sender mühürünü uygular.
class GroupSession {
  final String groupId;
  final String myPeerId;
  final GroupCipher cipher;

  GroupSession({
    required this.groupId,
    required this.myPeerId,
  }) : cipher = GroupCipher(groupId: groupId, myPeerId: myPeerId);

  /// Sender Key üretip dağıtım JSON'unu hazırlar.
  Future<Map<String, dynamic>> initMySenderKey() async {
    final state = await cipher.generateMySenderKey();
    return {
      'type': 'sender_key_distribution',
      'group_id': groupId,
      'distribution': state.toDistributionJson(),
    };
  }

  /// Başka bir üyenin gönderdiği dağıtım mesajını kaydeder.
  void processDistributionMessage(String senderId, Map<String, dynamic> dist) {
    cipher.processDistributionMessage(senderId, dist);
  }

  /// Grup mesajını şifreler. [sealedEnvelope] varsa sender_id gizlenir.
  Future<Map<String, dynamic>> encrypt(
    String plaintext, {
    PublicKey? recipientIdentityPublicKey,
  }) async {
    final payload = await cipher.encrypt(utf8.encode(plaintext));

    Map<String, dynamic>? sealedEnvelope;
    if (recipientIdentityPublicKey != null) {
      sealedEnvelope = await SealedSender.seal(
        senderId: myPeerId,
        recipientIdentityPublicKey: recipientIdentityPublicKey,
      );
    }

    return {
      'type': 'group_message',
      'group_id': groupId,
      'ratchet': payload,
      if (sealedEnvelope != null) 'sealed_sender': sealedEnvelope,
      if (sealedEnvelope == null) 'sender_id': myPeerId,
    };
  }

  /// Gelen bir grup mesajını çözer. Sealed Sender varsa myIdentityKeyPair ile açar.
  Future<({String text, String senderId})> decrypt(
    Map<String, dynamic> wireMessage, {
    SimpleKeyPair? myIdentityKeyPair,
  }) async {
    String senderId;
    if (wireMessage.containsKey('sealed_sender') && myIdentityKeyPair != null) {
      senderId = await SealedSender.unseal(
        sealedEnvelope:
            Map<String, dynamic>.from(wireMessage['sealed_sender']),
        myIdentityKeyPair: myIdentityKeyPair,
      );
    } else {
      senderId = wireMessage['sender_id'] as String? ?? '?';
    }

    final ratchetPayload =
        Map<String, dynamic>.from(wireMessage['ratchet']);
    final plaintext =
        await cipher.decrypt(senderId, ratchetPayload);

    return (text: utf8.decode(plaintext), senderId: senderId);
  }
}

/// Uygulama genelinde grup oturumlarını yöneten kayıt defteri.
class GroupSessionManager {
  final Map<String, GroupSession> _sessions = {};

  GroupSession getOrCreate(String groupId, String myPeerId) {
    return _sessions.putIfAbsent(
      groupId,
      () => GroupSession(groupId: groupId, myPeerId: myPeerId),
    );
  }

  GroupSession? get(String groupId) => _sessions[groupId];
  void remove(String groupId) => _sessions.remove(groupId);
  void clear() => _sessions.clear();
}
