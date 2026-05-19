import 'dart:async';

import 'package:flutter/material.dart';

import '../core/connection_status.dart';
import '../core/socket_client.dart';
import '../core/keys_api.dart';
import '../crypto/group_session.dart';
import '../crypto/identity.dart';
import '../storage/secure_keys.dart';
import '../core/chat_store.dart';
import 'connection_indicator.dart';
import 'message_bubble.dart';

class GroupChatScreen extends StatefulWidget {
  final SocketClient client;
  final String groupId;
  final List<String> memberHandles;
  final IncomingMessage? initialMessage;

  const GroupChatScreen({
    super.key,
    required this.client,
    required this.groupId,
    required this.memberHandles,
    this.initialMessage,
  });

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  ConnectionStatus _status = ConnectionStatus.connecting;
  late final List<DecryptedMessage> _messages;
  final Set<String> _seenMsgIds = <String>{};

  late StreamSubscription _statusSub;
  late StreamSubscription _msgSub;
  late StreamSubscription _ackSub;

  final _store = SecureKeyStore();
  late final KeysApi _api;
  late final GroupSession _groupSession;

  Identity? _myIdentity;
  bool _ready = false;
  bool _setupError = false;
  String _statusText = 'Grup oturumu başlatılıyor…';
  late Future<void> _setupFuture;

  @override
  void initState() {
    super.initState();
    _status = widget.client.status;
    _api = KeysApi(baseUrl: widget.client.serverUrl);
    _groupSession = ChatStore().groupSessionManager.getOrCreate(
      widget.groupId,
      widget.client.clientId,
    );

    _messages = ChatStore().getMessages(widget.groupId);
    ChatStore().setActive(widget.groupId, true);

    _statusSub = widget.client.status$.listen((s) {
      if (mounted) setState(() => _status = s);
    });
    _msgSub = widget.client.messages$.listen(_onIncoming);
    _ackSub = widget.client.acks$.listen((_) {});

    _setupFuture = _setupGroup();
    _setupFuture.then((_) async {
      if (widget.initialMessage != null && mounted) {
        await _onIncoming(widget.initialMessage!);
      }
      for (final unread in ChatStore().takeUnread(widget.groupId)) {
        await _onIncoming(unread);
      }
    });
  }

  Future<void> _setupGroup() async {
    try {
      _myIdentity = await _store.loadIdentity();
      if (_myIdentity == null) {
        setState(() {
          _setupError = true;
          _statusText = 'Kimlik anahtarı bulunamadı. Önce Faz 2A ekranından oluşturun.';
        });
        return;
      }

      // 1. Kendi Sender Key'ini üret ve dağıtım payload'ını al
      setState(() => _statusText = 'Sender Key üretiliyor…');
      final distPayload = await _groupSession.initMySenderKey();

      // 2. Üyelerden bundle çek ve her birine Sender Key dağıt (1:1 kanal üzerinden)
      setState(() => _statusText = '${widget.memberHandles.length} üyeye anahtar dağıtılıyor…');
      for (final handle in widget.memberHandles) {
        if (handle == _myIdentity!.handle) continue;
        try {
          final env = Map<String, dynamic>.from(distPayload);
          env['members'] = widget.memberHandles;
          widget.client.sendMessage(
            recipientId: handle,
            envelope: env,
          );
        } catch (_) {}
      }

      // 3. Diğer üyelerin Sender Key dağıtımlarını bekliyoruz (mesajlar geldiğinde işleneceiz)
      setState(() {
        _ready = true;
        _statusText = 'Hazır — ${widget.memberHandles.length} üye';
      });
    } catch (e) {
      setState(() {
        _setupError = true;
        _statusText = 'Kurulum hatası: $e';
      });
    }
  }

  Future<void> _onIncoming(IncomingMessage incoming) async {
    await _setupFuture;
    if (!_seenMsgIds.add(incoming.msgId)) return;

    final envelope = incoming.envelope;
    final type = envelope['type'];

    if (type == 'sender_key_distribution') {
      // Bir üyenin Sender Key dağıtımı geldi — kaydedelim
      final groupId = envelope['group_id'];
      if (groupId != widget.groupId) return;

      final dist = Map<String, dynamic>.from(envelope['distribution']);
      _groupSession.processDistributionMessage(incoming.senderId, dist);
      return;
    }

    if (type != 'group_message') return;
    if (envelope['group_id'] != widget.groupId) return;

    try {
      final result = await _groupSession.decrypt(envelope);
      if (!mounted) return;

      setState(() {
        _messages.add(DecryptedMessage(
          id: incoming.msgId,
          text: result.text,
          senderId: result.senderId,
          isMine: false,
          timestamp: DateTime.now(),
        ));
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(DecryptedMessage(
          id: incoming.msgId,
          text: '<Şifre çözme hatası: $e>',
          senderId: incoming.senderId,
          isMine: false,
          timestamp: DateTime.now(),
          state: MessageState.failed,
        ));
      });
    }

    widget.client.acknowledgeDelivery(
      msgId: incoming.msgId,
      senderId: incoming.senderId,
    );
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _status != ConnectionStatus.online || !_ready) return;

    final tempId = 'local-${DateTime.now().microsecondsSinceEpoch}';
    setState(() {
      _messages.add(DecryptedMessage(
        id: tempId,
        text: text,
        senderId: widget.client.clientId,
        isMine: true,
        timestamp: DateTime.now(),
        state: MessageState.sending,
      ));
    });
    _inputCtrl.clear();
    _scrollToBottom();

    try {
      // Grup mesajını şifrele (Padding otomatik uygulanır GroupCipher içinde)
      final envelope = await _groupSession.encrypt(text);

      // Her üyeye ayrı ayrı gönder
      for (final handle in widget.memberHandles) {
        if (handle == widget.client.clientId) continue;
        widget.client.sendMessage(
          recipientId: handle,
          envelope: envelope,
          clientMsgId: tempId,
        );
      }

      final i = _messages.indexWhere((m) => m.id == tempId);
      if (i != -1 && mounted) {
        setState(() {
          _messages[i] = DecryptedMessage(
            id: tempId,
            text: _messages[i].text,
            senderId: _messages[i].senderId,
            isMine: true,
            timestamp: _messages[i].timestamp,
            state: MessageState.sent,
          );
        });
      }
    } catch (e) {
      final i = _messages.indexWhere((m) => m.id == tempId);
      if (i != -1 && mounted) {
        setState(() {
          _messages[i] = DecryptedMessage(
            id: tempId,
            text: _messages[i].text,
            senderId: _messages[i].senderId,
            isMine: true,
            timestamp: _messages[i].timestamp,
            state: MessageState.failed,
          );
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gönderim hatası: $e')),
        );
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    ChatStore().setActive(widget.groupId, false);
    _statusSub.cancel();
    _msgSub.cancel();
    _ackSub.cancel();
    _api.close();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('🔒 Grup: ${widget.groupId}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ConnectionIndicator(status: _status),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Grup üyeleri',
            icon: const Icon(Icons.group_outlined),
            onPressed: () => _showMembers(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // Durum banner
          if (!_ready)
            Container(
              width: double.infinity,
              color: _setupError
                  ? scheme.errorContainer
                  : scheme.primaryContainer,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              child: Text(
                _statusText,
                style: TextStyle(
                  fontSize: 12,
                  color: _setupError
                      ? scheme.onErrorContainer
                      : scheme.onPrimaryContainer,
                ),
                textAlign: TextAlign.center,
              ),
            ),

          // Mesaj listesi
          Expanded(
            child: ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _messages.length,
              itemBuilder: (_, i) {
                final m = _messages[i];
                return _GroupMessageBubble(
                  text: m.text,
                  senderId: m.senderId,
                  isMine: m.isMine,
                  state: m.state,
                  timestamp: m.timestamp,
                );
              },
            ),
          ),

          // Giriş alanı
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputCtrl,
                      minLines: 1,
                      maxLines: 4,
                      onSubmitted: (_) => _send(),
                      enabled: _ready,
                      decoration: InputDecoration(
                        hintText: _ready ? 'Gruba mesaj yaz…' : 'Hazırlanıyor…',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed:
                        _status == ConnectionStatus.online && _ready ? _send : null,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showMembers(BuildContext ctx) {
    showModalBottomSheet(
      context: ctx,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Grup Üyeleri',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            const Divider(height: 1),
            ...widget.memberHandles.map((h) => ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(h),
                  trailing: h == widget.client.clientId
                      ? const Chip(label: Text('Sen'))
                      : null,
                )),
          ],
        ),
      ),
    );
  }
}

class _GroupMessageBubble extends StatelessWidget {
  const _GroupMessageBubble({
    required this.text,
    required this.senderId,
    required this.isMine,
    required this.state,
    required this.timestamp,
  });

  final String text;
  final String senderId;
  final bool isMine;
  final MessageState state;
  final DateTime timestamp;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg =
        isMine ? scheme.primaryContainer : scheme.surfaceContainerHighest;
    final fg = isMine ? scheme.onPrimaryContainer : scheme.onSurface;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isMine ? 16 : 4),
              bottomRight: Radius.circular(isMine ? 4 : 16),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isMine)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    senderId,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: scheme.primary,
                    ),
                  ),
                ),
              Text(text, style: TextStyle(color: fg, fontSize: 15)),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _fmtTime(timestamp),
                    style: TextStyle(
                      color: fg.withValues(alpha: 0.6),
                      fontSize: 11,
                    ),
                  ),
                  if (isMine) ...[
                    const SizedBox(width: 6),
                    Text(
                      state == MessageState.sent
                          ? '✓'
                          : state == MessageState.delivered
                              ? '✓✓'
                              : state == MessageState.failed
                                  ? '!'
                                  : '⏱',
                      style: TextStyle(
                        color: state == MessageState.delivered
                            ? Colors.lightBlueAccent
                            : fg.withValues(alpha: 0.6),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtTime(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
