enum ConnectionStatus {
  offline,
  connecting,
  online,
  reconnecting,
  failed;

  String get label {
    switch (this) {
      case ConnectionStatus.offline:
        return 'Çevrimdışı';
      case ConnectionStatus.connecting:
        return 'Bağlanıyor…';
      case ConnectionStatus.online:
        return 'Çevrimiçi';
      case ConnectionStatus.reconnecting:
        return 'Yeniden bağlanıyor…';
      case ConnectionStatus.failed:
        return 'Bağlantı başarısız';
    }
  }
}
