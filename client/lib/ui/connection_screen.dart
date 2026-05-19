import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/socket_client.dart';
import 'chat_screen.dart';
import 'group_chat_screen.dart';
import 'identity_screen.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  final _serverCtrl = TextEditingController();
  final _clientIdCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _serverCtrl.text = 'http://localhost:5050';
    _clientIdCtrl.text = const Uuid().v4().substring(0, 8);
  }

  @override
  void dispose() {
    _serverCtrl.dispose();
    _clientIdCtrl.dispose();
    super.dispose();
  }

  void _connect() {
    final server = _serverCtrl.text.trim();
    final clientId = _clientIdCtrl.text.trim();
    if (server.isEmpty || clientId.isEmpty) return;

    final client = SocketClient(serverUrl: server, clientId: clientId);
    client.connect();

    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChatScreen(client: client),
    ));
  }

  Future<void> _openGroup() async {
    final server = _serverCtrl.text.trim();
    final clientId = _clientIdCtrl.text.trim();
    if (server.isEmpty || clientId.isEmpty) return;

    final members = await showDialog<List<String>>(
      context: context,
      builder: (_) => _GroupSetupDialog(myId: clientId),
    );
    if (members == null || members.length < 2) return;

    final groupId = 'group-${DateTime.now().millisecondsSinceEpoch}';

    final client = SocketClient(serverUrl: server, clientId: clientId);
    client.connect();

    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GroupChatScreen(
        client: client,
        groupId: groupId,
        memberHandles: members,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('EE2E — Bağlantı')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Faz 3 — E2EE Mesajlaşma',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                const Text(
                  'X3DH + Double Ratchet (AES-256-GCM) ile uçtan uca şifreli 1:1 veya grup sohbeti.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _serverCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Sunucu URL (http/https)',
                    helperText: 'Android emulator: 10.0.2.2  •  Gerçek cihaz: ngrok URL',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _clientIdCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Client ID',
                    helperText: 'Karşı taraf bu ID ile sana mesaj atacak',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _connect,
                  icon: const Icon(Icons.lock_outline),
                  label: const Text('1:1 Şifrel. Sohbet'),
                ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: _openGroup,
                  icon: const Icon(Icons.group_outlined),
                  label: const Text('Grup Sohbeti Başlat'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    final url = _serverCtrl.text.trim();
                    if (url.isEmpty) return;
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => IdentityScreen(serverUrl: url),
                    ));
                  },
                  icon: const Icon(Icons.vpn_key_outlined),
                  label: const Text('Faz 2A — Anahtar Yönetimi'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Grup kurulum diyaloğu
// ─────────────────────────────────────────────
class _GroupSetupDialog extends StatefulWidget {
  const _GroupSetupDialog({required this.myId});
  final String myId;

  @override
  State<_GroupSetupDialog> createState() => _GroupSetupDialogState();
}

class _GroupSetupDialogState extends State<_GroupSetupDialog> {
  final _memberCtrl = TextEditingController();
  final List<String> _members = [];

  @override
  void initState() {
    super.initState();
    _members.add(widget.myId); // Kendi ID'mizi başta ekle
  }

  void _addMember() {
    final handle = _memberCtrl.text.trim();
    if (handle.isEmpty || _members.contains(handle)) return;
    setState(() => _members.add(handle));
    _memberCtrl.clear();
  }

  @override
  void dispose() {
    _memberCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Grup Kur'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Gruba eklemek istediğin üyelerin Handle\'larını gir.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _memberCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Üye Handle\'ı (örn. bob)',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _addMember(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _addMember,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_members.isEmpty)
              const Text('Henüz üye yok.')
            else
              ..._members.map((m) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.person_outline, size: 20),
                    title: Text(m),
                    trailing: m == widget.myId
                        ? const Chip(label: Text('Sen'))
                        : IconButton(
                            icon: const Icon(Icons.remove_circle_outline, size: 18),
                            onPressed: () =>
                                setState(() => _members.remove(m)),
                          ),
                  )),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('İptal'),
        ),
        FilledButton.icon(
          onPressed: _members.length >= 2
              ? () => Navigator.pop(context, _members)
              : null,
          icon: const Icon(Icons.group_add),
          label: Text('Grubu Oluştur (${_members.length} üye)'),
        ),
      ],
    );
  }
}
