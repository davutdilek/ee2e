# client/

Flutter uygulaması (Android/iOS/macOS/Windows/Linux). Faz 1'de scaffold'lanacak.

Beklenen iskelet (Faz 1 sonu):

```
client/
├── pubspec.yaml
├── lib/
│   ├── main.dart
│   ├── app.dart
│   ├── core/
│   │   ├── socket_client.dart      # SocketIO wrapper
│   │   └── connection_status.dart  # Online/Offline/Reconnecting
│   ├── ui/
│   │   ├── chat_screen.dart
│   │   ├── connection_indicator.dart
│   │   └── message_bubble.dart     # ⏱ → ✓ → ✓✓
│   └── crypto/                     # Faz 2'den itibaren
│       ├── identity.dart
│       ├── x3dh.dart
│       ├── ratchet.dart
│       └── aead.dart
├── android/, ios/, macos/, windows/, linux/
└── test/
```

> Bu klasör Faz 1'de `flutter create` ile scaffold'lanacak. Detaylar için `../PHASES.md`.
