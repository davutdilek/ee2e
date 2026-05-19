import 'dart:async';

/// Push bildirim servisi (MVP/Stub).
///
/// Gerçek bir push servisine (FCM, APNs) bağlanmadan önce kullanılan
/// in-memory stub. Faz 5'te altyapıyı kurar; gerçek entegrasyon
/// platform build'leriyle yapılacaktır.

class PushToken {
  final String token;
  final String platform; // 'ios', 'android', 'web'
  final String deviceId;
  final DateTime registeredAt;

  PushToken({
    required this.token,
    required this.platform,
    required this.deviceId,
    DateTime? registeredAt,
  }) : registeredAt = registeredAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'token': token,
        'platform': platform,
        'device_id': deviceId,
        'registered_at': registeredAt.toIso8601String(),
      };

  factory PushToken.fromJson(Map<String, dynamic> json) {
    return PushToken(
      token: json['token'] as String,
      platform: json['platform'] as String,
      deviceId: json['device_id'] as String,
      registeredAt: DateTime.tryParse(json['registered_at'] as String? ?? ''),
    );
  }
}

enum PushNotificationType {
  newMessage,
  keyUpdate,
  groupInvite,
  deviceAdded,
}

class PushNotification {
  final PushNotificationType type;
  final String title;
  final String body;
  final Map<String, dynamic> data;

  PushNotification({
    required this.type,
    required this.title,
    required this.body,
    this.data = const {},
  });
}

/// İstemci tarafı push notification servisi (stub/MVP).
class PushService {
  PushToken? _currentToken;
  final _notificationController = StreamController<PushNotification>.broadcast();

  /// Gelen push notification stream'i.
  Stream<PushNotification> get notifications$ => _notificationController.stream;

  /// Mevcut push token'ı döndürür.
  PushToken? get currentToken => _currentToken;

  /// Push token'ı kaydeder (gerçek FCM/APNs entegrasyonunda token alınır).
  Future<PushToken> registerToken({
    required String deviceId,
    required String platform,
  }) async {
    // Stub: Sahte bir token üretir
    final token = 'stub-push-token-${DateTime.now().millisecondsSinceEpoch}';
    _currentToken = PushToken(
      token: token,
      platform: platform,
      deviceId: deviceId,
    );
    return _currentToken!;
  }

  /// Push token'ı sunucuya yükler.
  Future<void> uploadTokenToServer(String serverUrl, String userId) async {
    if (_currentToken == null) return;
    // Stub: Gerçek HTTP çağrısı yerine log.
    // Gerçek implementasyonda:
    // await http.post('$serverUrl/api/v1/push/register', body: ...)
  }

  /// Gelen bir push notification'ı işler (test/stub amaçlı).
  void handleIncomingPush(Map<String, dynamic> payload) {
    final typeStr = payload['type'] as String? ?? 'new_message';
    PushNotificationType type;
    switch (typeStr) {
      case 'key_update':
        type = PushNotificationType.keyUpdate;
        break;
      case 'group_invite':
        type = PushNotificationType.groupInvite;
        break;
      case 'device_added':
        type = PushNotificationType.deviceAdded;
        break;
      default:
        type = PushNotificationType.newMessage;
    }

    _notificationController.add(PushNotification(
      type: type,
      title: payload['title'] as String? ?? '',
      body: payload['body'] as String? ?? '',
      data: payload,
    ));
  }

  /// Servis temizliği.
  Future<void> dispose() async {
    await _notificationController.close();
  }
}
