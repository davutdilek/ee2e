import 'dart:typed_data';

import 'codec.dart';

/// X3DH Handshake sırasında gönderilecek ilk mesajın header'ı (Initial Message Header).
/// Bob, bu header'ı alarak hangi anahtarlarının kullanıldığını anlar ve kendi SK'sını türetir.
class X3dhHeader {
  X3dhHeader({
    required this.senderIk,
    required this.senderEk,
    required this.recipientSpkId,
    this.recipientOpkId,
  });

  /// Alice'in kimlik anahtarının (Identity Key) DH public parçası
  final Uint8List senderIk;

  /// Alice'in bu oturum için ürettiği geçici anahtarın (Ephemeral Key) public parçası
  final Uint8List senderEk;

  /// Alice'in kullandığı Bob'a ait Signed Pre-Key ID'si
  final int recipientSpkId;

  /// Alice'in kullandığı Bob'a ait One-Time Pre-Key ID'si (Eğer havuzda yoksa null olur)
  final int? recipientOpkId;

  Map<String, dynamic> toJson() => {
        'sender_ik': B64u.encode(senderIk),
        'sender_ek': B64u.encode(senderEk),
        'recipient_spk_id': recipientSpkId,
        if (recipientOpkId != null) 'recipient_opk_id': recipientOpkId,
      };

  static X3dhHeader fromJson(Map<String, dynamic> json) {
    return X3dhHeader(
      senderIk: B64u.decode(json['sender_ik'] as String),
      senderEk: B64u.decode(json['sender_ek'] as String),
      recipientSpkId: json['recipient_spk_id'] as int,
      recipientOpkId: json['recipient_opk_id'] as int?,
    );
  }
}
