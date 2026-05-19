import 'dart:async';

import 'package:flutter/material.dart';

import '../core/connection_status.dart';
import '../core/socket_client.dart';
import '../core/keys_api.dart';
import '../crypto/session.dart';
import '../crypto/identity.dart';
import '../crypto/x3dh_header.dart';
import '../storage/secure_keys.dart';
import '../core/chat_store.dart';
import 'connection_indicator.dart';
import 'message_bubble.dart';
import 'group_chat_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.client, required this.peerId});

  final SocketClient client;
  final String peerId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  ConnectionStatus _status = ConnectionStatus.connecting;
  late final List<DecryptedMessage> _messages;
  final Set<String> _seenIncoming = <String>{};
  final Set<String> _seenAcks = <String>{};

  final _sessionManager = SessionManager();
  final _store = SecureKeyStore();
  late final KeysApi _api;

  Identity? _myIdentity;
  SignedPreKey? _mySpk;

  late StreamSubscription _statusSub;
  late StreamSubscription _msgSub;
  late StreamSubscription _ackSub;
  late Future<void> _keysFuture;

  @override
  void initState() {
    super.initState();
    _status = widget.client.status;
    _api = KeysApi(baseUrl: widget.client.serverUrl);
    _keysFuture = _bootstrapKeys();
    
    _messages = ChatStore().getMessages(widget.peerId);
    ChatStore().setActive(widget.peerId, true);

    _statusSub = widget.client.status$.listen((s) {
      if (mounted) setState(() => _status = s);
    });
    _msgSub = widget.client.messages$.listen(_onIncoming);
    _ackSub = widget.client.acks$.listen(_onAck);

    _processUnread();
  }

  Future<void> _processUnread() async {
    await _keysFuture;
    for (final unread in ChatStore().takeUnread(widget.peerId)) {
      await _onIncoming(unread);
    }
  }

  Future<void> _bootstrapKeys() async {
    _myIdentity = await _store.loadIdentity();
    _mySpk = await _store.loadSignedPreKey();
  }

  Future<void> _onIncoming(IncomingMessage incoming) async {
    await _keysFuture;
    if (incoming.msgId.isNotEmpty && !_seenIncoming.add(incoming.msgId)) {
      return;
    }
    
    final envelope = incoming.envelope;
    final sender = incoming.senderId;
    final type = envelope['type'];
    
    if (type == 'sender_key_distribution' || type == 'group_message') {
      try {
        final groupId = envelope['group_id'] as String;
        final members = List<String>.from(envelope['members'] ?? [widget.client.clientId, sender]);
        
        if (mounted && ModalRoute.of(context)?.isCurrent == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('📥 Grup daveti geldi: $groupId (Yönlendiriliyor...)')),
          );
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => GroupChatScreen(
              client: widget.client,
              groupId: groupId,
              memberHandles: members,
              initialMessage: incoming,
            ),
          ));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('❌ Grup daveti hatası: $e')),
          );
        }
      }
      return;
    }

    String text;
    
    try {
      var session = _sessionManager.getSession(sender);
      if (session == null && type == 'prekey_message') {
        if (_myIdentity == null || _mySpk == null) {
          throw Exception('Kendi anahtarlarım (IK/SPK) bulunamadı.');
        }
        
        final x3dh = X3dhHeader.fromJson(Map<String, dynamic>.from(envelope['x3dh']));
        final opkId = x3dh.recipientOpkId;
        OneTimePreKey? opk;
        if (opkId != null) {
           opk = await _store.consumeOneTimePreKey(opkId);
        }
        
        session = await E2eSession.createAsResponder(
          peerId: sender,
          header: x3dh,
          myIdentity: _myIdentity!,
          mySignedPreKey: _mySpk!.keyPair,
          myOneTimePreKey: opk?.keyPair,
        );
        _sessionManager.saveSession(session);
      }
      
      if (session != null) {
        text = await session.decrypt(envelope);
      } else {
        text = '<Şifre çözülemedi: Session yok>';
      }
    } catch (e) {
      text = '<Şifre çözme hatası: $e>';
    }

    setState(() {
      _messages.add(DecryptedMessage(
        id: incoming.msgId,
        text: text,
        isMine: false,
        senderId: incoming.senderId,
        timestamp: DateTime.now(),
        state: MessageState.delivered,
      ));
    });
    widget.client.acknowledgeDelivery(
      msgId: incoming.msgId,
      senderId: incoming.senderId,
    );
    _scrollToBottom();
  }

  void _onAck(MessageAck ack) {
    int idx = -1;
    if (ack.kind == AckKind.queued && ack.clientMsgId != null) {
      idx = _messages.indexWhere((m) => m.id == ack.clientMsgId);
      if (idx != -1) {
        setState(() {
          _messages[idx] = DecryptedMessage(
            id: ack.msgId,
            text: _messages[idx].text,
            isMine: _messages[idx].isMine,
            senderId: _messages[idx].senderId,
            timestamp: _messages[idx].timestamp,
            state: MessageState.sent,
          );
        });
        return;
      }
    }
    final ackKey = '${ack.kind.name}:${ack.msgId}';
    if (!_seenAcks.add(ackKey)) return;
    idx = _messages.indexWhere((m) => m.id == ack.msgId);
    if (idx == -1) return;
    setState(() {
      _messages[idx].state = ack.kind == AckKind.delivered
          ? MessageState.delivered
          : MessageState.sent;
    });
  }

  Future<void> _send() async {
    final peer = widget.peerId;
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _status != ConnectionStatus.online) return;

    if (_myIdentity == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Hata: Kendi kimlik anahtarlarınız eksik! Önce Faz 2A ekranından oluşturun.')),
        );
      }
      return;
    }

    final tempId = 'local-${DateTime.now().microsecondsSinceEpoch}';
    setState(() {
      _messages.add(DecryptedMessage(
        id: tempId,
        text: text,
        isMine: true,
        senderId: peer,
        timestamp: DateTime.now(),
      ));
    });

    _inputCtrl.clear();
    _scrollToBottom();

    try {
      var session = _sessionManager.getSession(peer);
      if (session == null) {
         final peerBundle = await _api.fetchBundle(peer);
         if (peerBundle == null) throw Exception('$peer kullanıcısının bundle paketi bulunamadı.');
         session = await E2eSession.createAsInitiator(
           peerId: peer,
           peerBundle: peerBundle,
           myIdentity: _myIdentity!,
         );
         _sessionManager.saveSession(session);
      }
      
      final envelope = await session.encrypt(text);
      
      widget.client.sendMessage(
        recipientId: peer,
        envelope: envelope,
        clientMsgId: tempId,
      );
    } catch (e) {
      final i = _messages.indexWhere((m) => m.id == tempId);
      if (i != -1) {
        setState(() => _messages[i].state = MessageState.failed);
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
    ChatStore().setActive(widget.peerId, false);
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
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Sohbet: ${widget.peerId}',
                style: const TextStyle(fontSize: 14)),
            ConnectionIndicator(status: _status),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _messages.length,
              itemBuilder: (_, i) {
                final m = _messages[i];
                return MessageBubble(
                  text: m.text,
                  isMine: m.isMine,
                  state: m.state,
                  timestamp: m.timestamp,
                );
              },
            ),
          ),
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
                      decoration: const InputDecoration(
                        hintText: 'Mesaj yaz…',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _status == ConnectionStatus.online ? _send : null,
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
}
