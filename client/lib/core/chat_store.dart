import 'socket_client.dart';
import '../crypto/group_session.dart';
import '../ui/message_bubble.dart';

class DecryptedMessage {
  final String id;
  final String text;
  final String senderId;
  final bool isMine;
  final DateTime timestamp;
  MessageState state; // 0: sending, 1: sent, 2: delivered, 3: failed

  DecryptedMessage({
    required this.id,
    required this.text,
    required this.senderId,
    required this.isMine,
    required this.timestamp,
    this.state = MessageState.delivered,
  });
}

class ChatStore {
  static final ChatStore _instance = ChatStore._internal();
  factory ChatStore() => _instance;
  ChatStore._internal();

  final GroupSessionManager groupSessionManager = GroupSessionManager();
  
  final Map<String, List<DecryptedMessage>> _messages = {};
  final Map<String, List<IncomingMessage>> _unread = {};
  final Set<String> _activeChats = {};

  List<DecryptedMessage> getMessages(String id) => _messages.putIfAbsent(id, () => []);
  
  void addMessage(String id, DecryptedMessage msg) {
    getMessages(id).add(msg);
  }

  void addUnread(String id, IncomingMessage msg) {
    _unread.putIfAbsent(id, () => []).add(msg);
  }

  List<IncomingMessage> takeUnread(String id) {
    final list = _unread[id] ?? [];
    _unread.remove(id);
    return list;
  }

  void setActive(String id, bool active) {
    if (active) _activeChats.add(id);
    else _activeChats.remove(id);
  }

  bool isActive(String id) => _activeChats.contains(id);
}
