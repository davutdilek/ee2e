import 'package:cryptography/cryptography.dart';

import 'session.dart';

/// Sesame benzeri Multi-Device Session Yönetimi.
///
/// Aynı kullanıcının birden fazla cihazını (telefon, tablet, masaüstü) destekler.
/// Her cihaz kendi Identity Key çiftine sahiptir.
/// Bir mesaj gönderildiğinde, alıcının TÜM cihazlarına ayrı ayrı şifrelenir.

class DeviceInfo {
  final String deviceId;
  final String userId;
  final int registrationId;
  final SimplePublicKey? identityPublicKey;
  final DateTime lastSeen;

  DeviceInfo({
    required this.deviceId,
    required this.userId,
    required this.registrationId,
    this.identityPublicKey,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'device_id': deviceId,
        'user_id': userId,
        'registration_id': registrationId,
        'last_seen': lastSeen.toIso8601String(),
      };

  factory DeviceInfo.fromJson(Map<String, dynamic> json) {
    return DeviceInfo(
      deviceId: json['device_id'] as String,
      userId: json['user_id'] as String,
      registrationId: json['registration_id'] as int,
      lastSeen: DateTime.tryParse(json['last_seen'] as String? ?? ''),
    );
  }
}

/// Bir kullanıcının tüm cihazlarına ait oturumları yönetir.
class MultiDeviceManager {
  /// userId → { deviceId → E2eSession }
  final Map<String, Map<String, E2eSession>> _sessions = {};

  /// userId → [ DeviceInfo ]
  final Map<String, List<DeviceInfo>> _knownDevices = {};

  /// Bir kullanıcının bilinen cihazlarını kaydeder.
  void registerDevices(String userId, List<DeviceInfo> devices) {
    _knownDevices[userId] = devices;
  }

  /// Bir kullanıcının bilinen cihazlarını döndürür.
  List<DeviceInfo> getDevices(String userId) {
    return _knownDevices[userId] ?? [];
  }

  /// Bir cihaza ait oturumu kaydeder.
  void saveSession(String userId, String deviceId, E2eSession session) {
    _sessions.putIfAbsent(userId, () => {});
    _sessions[userId]![deviceId] = session;
  }

  /// Bir cihaza ait oturumu döndürür.
  E2eSession? getSession(String userId, String deviceId) {
    return _sessions[userId]?[deviceId];
  }

  /// Bir kullanıcının tüm cihazlarına ait oturumları döndürür.
  Map<String, E2eSession> getAllSessions(String userId) {
    return _sessions[userId] ?? {};
  }

  /// Bir cihazı kaldırır (cihaz artık güvenilir değil veya kullanıcı tarafından kaldırılmış).
  void removeDevice(String userId, String deviceId) {
    _sessions[userId]?.remove(deviceId);
    _knownDevices[userId]?.removeWhere((d) => d.deviceId == deviceId);
  }

  /// Bir kullanıcının tüm oturumlarını sıfırlar.
  void clearUser(String userId) {
    _sessions.remove(userId);
    _knownDevices.remove(userId);
  }

  /// Tüm oturumları sıfırlar.
  void clearAll() {
    _sessions.clear();
    _knownDevices.clear();
  }

  /// Bir mesajı, alıcının TÜM cihazlarına şifrelenmiş zarflar olarak döndürür.
  /// Her cihaz kendi E2eSession'ını kullanır.
  Future<Map<String, Map<String, dynamic>>> encryptForAllDevices(
    String recipientUserId,
    String plaintext,
  ) async {
    final sessions = getAllSessions(recipientUserId);
    final envelopes = <String, Map<String, dynamic>>{};

    for (final entry in sessions.entries) {
      final deviceId = entry.key;
      final session = entry.value;
      envelopes[deviceId] = await session.encrypt(plaintext);
    }

    return envelopes;
  }
}
