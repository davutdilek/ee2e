import 'dart:async';

import 'package:flutter/material.dart';

import '../core/connection_status.dart';
import '../core/socket_client.dart';
import '../core/chat_store.dart';
import 'chat_screen.dart';
import 'group_chat_screen.dart';
import 'connection_indicator.dart';

class DashboardScreen extends StatefulWidget {
  final SocketClient client;
  const DashboardScreen({super.key, required this.client});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class ChatPreview {
  final String id;
  final bool isGroup;
  final List<String>? members;
  String lastMessage;
  DateTime time;

  ChatPreview({
    required this.id,
    required this.isGroup,
    this.members,
    required this.lastMessage,
    required this.time,
  });
}

class _DashboardScreenState extends State<DashboardScreen> {
  ConnectionStatus _status = ConnectionStatus.connecting;
  late StreamSubscription _statusSub;
  late StreamSubscription _msgSub;

  final Map<String, ChatPreview> _chats = {};

  @override
  void initState() {
    super.initState();
    _status = widget.client.status;
    _statusSub = widget.client.status$.listen((s) {
      if (mounted) setState(() => _status = s);
    });
    _msgSub = widget.client.messages$.listen(_onIncomingMessage);
  }

  void _onIncomingMessage(IncomingMessage incoming) {
    final envelope = incoming.envelope;
    final type = envelope['type'];
    final sender = incoming.senderId;

    if (type == 'group_message' || type == 'sender_key_distribution') {
      final groupId = envelope['group_id'] as String;
      final members = List<String>.from(envelope['members'] ?? [widget.client.clientId, sender]);
      
      if (!ChatStore().isActive(groupId)) {
        ChatStore().addUnread(groupId, incoming);
      }

      setState(() {
        _chats[groupId] = ChatPreview(
          id: groupId,
          isGroup: true,
          members: members,
          lastMessage: type == 'group_message' ? 'Yeni grup mesajı' : 'Yeni grup oluşturuldu',
          time: DateTime.now(),
        );
      });
    } else {
      if (!ChatStore().isActive(sender)) {
        ChatStore().addUnread(sender, incoming);
      }

      setState(() {
        _chats[sender] = ChatPreview(
          id: sender,
          isGroup: false,
          lastMessage: 'Yeni mesaj',
          time: DateTime.now(),
        );
      });
    }
  }

  @override
  void dispose() {
    _statusSub.cancel();
    _msgSub.cancel();
    widget.client.dispose();
    super.dispose();
  }

  void _openChat(ChatPreview preview) {
    if (preview.isGroup) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => GroupChatScreen(
          client: widget.client,
          groupId: preview.id,
          memberHandles: preview.members!,
        ),
      ));
    } else {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChatScreen(
          client: widget.client,
          peerId: preview.id,
        ),
      ));
    }
  }

  Future<void> _startDirectChat() async {
    final peerCtrl = TextEditingController();
    final peerId = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('1:1 Sohbet Başlat'),
        content: TextField(
          controller: peerCtrl,
          decoration: const InputDecoration(hintText: 'Kullanıcı (Handle) ID'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
          FilledButton(
            onPressed: () => Navigator.pop(context, peerCtrl.text.trim()),
            child: const Text('Başlat'),
          ),
        ],
      ),
    );

    if (peerId != null && peerId.isNotEmpty) {
      setState(() {
        _chats[peerId] = ChatPreview(
          id: peerId,
          isGroup: false,
          lastMessage: 'Yeni sohbet',
          time: DateTime.now(),
        );
      });
      _openChat(_chats[peerId]!);
    }
  }

  Future<void> _startGroupChat() async {
    final members = await showDialog<List<String>>(
      context: context,
      builder: (_) => _GroupSetupDialog(myId: widget.client.clientId),
    );
    if (members == null || members.length < 2) return;

    final groupId = 'group-${DateTime.now().millisecondsSinceEpoch}';
    setState(() {
      _chats[groupId] = ChatPreview(
        id: groupId,
        isGroup: true,
        members: members,
        lastMessage: 'Grup oluşturuldu',
        time: DateTime.now(),
      );
    });
    _openChat(_chats[groupId]!);
  }

  @override
  Widget build(BuildContext context) {
    final chatList = _chats.values.toList()
      ..sort((a, b) => b.time.compareTo(a.time));

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Sohbetler (${widget.client.clientId})', style: const TextStyle(fontSize: 16)),
            ConnectionIndicator(status: _status),
          ],
        ),
      ),
      body: chatList.isEmpty
          ? const Center(child: Text('Henüz aktif sohbet yok.'))
          : ListView.builder(
              itemCount: chatList.length,
              itemBuilder: (context, index) {
                final chat = chatList[index];
                return ListTile(
                  leading: CircleAvatar(
                    child: Icon(chat.isGroup ? Icons.group : Icons.person),
                  ),
                  title: Text(chat.isGroup ? 'Grup: ${chat.id}' : chat.id),
                  subtitle: Text(chat.lastMessage),
                  onTap: () => _openChat(chat),
                );
              },
            ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'group_fab',
            mini: true,
            onPressed: _startGroupChat,
            tooltip: 'Yeni Grup',
            child: const Icon(Icons.group_add),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'direct_fab',
            onPressed: _startDirectChat,
            tooltip: 'Yeni 1:1 Sohbet',
            child: const Icon(Icons.person_add),
          ),
        ],
      ),
    );
  }
}

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
    _members.add(widget.myId);
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
            const Text("Gruba eklemek istediğin üyelerin Handle'larını gir.", style: TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _memberCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Üye Handle (örn. bob)',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _addMember(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(onPressed: _addMember, icon: const Icon(Icons.add)),
              ],
            ),
            const SizedBox(height: 12),
            if (_members.isEmpty) const Text('Henüz üye yok.')
            else ..._members.map((m) => ListTile(
              dense: true,
              leading: const Icon(Icons.person_outline, size: 20),
              title: Text(m),
              trailing: m == widget.myId
                  ? const Chip(label: Text('Sen'))
                  : IconButton(
                      icon: const Icon(Icons.remove_circle_outline, size: 18),
                      onPressed: () => setState(() => _members.remove(m)),
                    ),
            )),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
        FilledButton.icon(
          onPressed: _members.length >= 2 ? () => Navigator.pop(context, _members) : null,
          icon: const Icon(Icons.group_add),
          label: Text('Grubu Oluştur (${_members.length})'),
        ),
      ],
    );
  }
}
