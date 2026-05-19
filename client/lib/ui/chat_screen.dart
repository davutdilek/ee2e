import 'dart:async';

import 'package:flutter/material.dart';

import '../core/connection_status.dart';
import '../core/socket_client.dart';
import '../core/keys_api.dart';
import '../crypto/session.dart';
import '../crypto/identity.dart';
import '../crypto/x3dh_header.dart';
import '../storage/secure_keys.dart';
import 'connection_indicator.dart';
import 'message_bubble.dart';
import 'group_chat_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.client});

  final SocketClient client;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatMessage {
  _ChatMessage({
    required this.id,
    required this.text,
    required this.isMine,
    required this.peerId,
    required this.timestamp,
    this.state = MessageState.sending,
  });

  final String id;
  final String text;
  final bool isMine;
  final String peerId;
  final DateTime timestamp;
  MessageState state;
}

class _ChatScreenState extends State<ChatScreen> {
  final _peerCtrl = TextEditingController();
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  ConnectionStatus _status = ConnectionStatus.connecting;
  final List<_ChatMessage> _messages = [];
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

  @override
  void initState() {
    super.initState();
    _status = widget.client.status;
    _api = KeysApi(baseUrl: widget.client.serverUrl);
    _bootstrapKeys();
    _statusSub = widget.client.status$.listen((s) {
      if (mounted) setState(() => _status = s);
    });
    _msgSub = widget.client.messages$.listen(_onIncoming);
    _ackSub = widget.client.acks$.listen(_onAck);
  }

  Future<void> _bootstrapKeys() async {
    _myIdentity = await _store.loadIdentity();
    _mySpk = await _store.loadSignedPreKey();
  }

  Future<void> _onIncoming(IncomingMessage incoming) async {
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
      _messages.add(_ChatMessage(
        id: incoming.msgId,
        text: text,
        isMine: false,
        peerId: incoming.senderId,
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
          _messages[idx] = _ChatMessage(
            id: ack.msgId,
            text: _messages[idx].text,
            isMine: _messages[idx].isMine,
            peerId: _messages[idx].peerId,
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
    final peer = _peerCtrl.text.trim();
    final text = _inputCtrl.text.trim();
    if (peer.isEmpty || text.isEmpty || _status != ConnectionStatus.online) return;

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
      _messages.add(_ChatMessage(
        id: tempId,
        text: text,
        isMine: true,
        peerId: peer,
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
    _statusSub.cancel();
    _msgSub.cancel();
    _ackSub.cancel();
    widget.client.dispose();
    _api.close();
    _peerCtrl.dispose();
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
            Text('Ben: ${widget.client.clientId}',
                style: const TextStyle(fontSize: 14)),
            ConnectionIndicator(status: _status),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _peerCtrl,
              decoration: const InputDecoration(
                labelText: 'Karşı tarafın Client ID',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
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
