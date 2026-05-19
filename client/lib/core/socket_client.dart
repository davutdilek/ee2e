import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

import 'connection_status.dart';

/// EE2E Socket.IO istemcisi.
///
/// Faz 1: plaintext payload taşıyabilir. Faz 3'ten itibaren `envelope` her
/// zaman opaque ciphertext'tir; bu sınıf içerik hakkında HİÇBİR varsayım yapmaz
/// — sadece taşır.
class SocketClient {
  SocketClient({required this.serverUrl, required this.clientId});

  final String serverUrl;
  final String clientId;

  io.Socket? _socket;

  final _statusController = StreamController<ConnectionStatus>.broadcast();
  final _messageController = StreamController<IncomingMessage>.broadcast();
  final _ackController = StreamController<MessageAck>.broadcast();

  Stream<ConnectionStatus> get status$ => _statusController.stream;
  Stream<IncomingMessage> get messages$ => _messageController.stream;
  Stream<MessageAck> get acks$ => _ackController.stream;

  ConnectionStatus _status = ConnectionStatus.offline;
  ConnectionStatus get status => _status;
  bool _disposed = false;

  void _setStatus(ConnectionStatus s) {
    if (_disposed || _statusController.isClosed) return;
    _status = s;
    _statusController.add(s);
  }

  void _emitMessage(IncomingMessage m) {
    if (_disposed || _messageController.isClosed) return;
    _messageController.add(m);
  }

  void _emitAck(MessageAck a) {
    if (_disposed || _ackController.isClosed) return;
    _ackController.add(a);
  }

  void connect() {
    if (_socket != null || _disposed) return;

    _setStatus(ConnectionStatus.connecting);

    final socket = io.io(
      serverUrl,
      io.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .disableAutoConnect()
          .setAuth({'client_id': clientId})
          .setReconnectionAttempts(10)
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(8000)
          .build(),
    );

    socket
      ..onConnect((_) {
        // ignore: avoid_print
        print('[SocketClient] connected to $serverUrl as $clientId');
        _setStatus(ConnectionStatus.online);
      })
      ..onDisconnect((_) {
        // ignore: avoid_print
        print('[SocketClient] disconnected');
        _setStatus(ConnectionStatus.offline);
      })
      ..onConnectError((err) {
        // ignore: avoid_print
        print('[SocketClient] connect_error: $err');
        _setStatus(ConnectionStatus.failed);
      })
      ..onError((err) {
        // ignore: avoid_print
        print('[SocketClient] error: $err');
      })
      ..onReconnectAttempt((_) => _setStatus(ConnectionStatus.reconnecting))
      ..onReconnectFailed((_) => _setStatus(ConnectionStatus.failed))
      ..on('message:recv', (data) {
        if (data is Map) {
          _emitMessage(IncomingMessage.fromJson(
            Map<String, dynamic>.from(data),
          ));
        }
      })
      ..on('message:queued', (data) {
        if (data is Map && data['msg_id'] is String) {
          final clientMsgId = data['client_msg_id'];
          _emitAck(MessageAck(
            msgId: data['msg_id'] as String,
            clientMsgId: clientMsgId is String ? clientMsgId : null,
            kind: AckKind.queued,
          ));
        }
      })
      ..on('message:ack', (data) {
        if (data is Map && data['msg_id'] is String) {
          _emitAck(MessageAck(
            msgId: data['msg_id'] as String,
            kind: AckKind.delivered,
          ));
        }
      });

    socket.connect();
    _socket = socket;
  }

  void sendMessage({
    required String recipientId,
    required Map<String, dynamic> envelope,
    String? clientMsgId,
  }) {
    final s = _socket;
    if (s == null || !s.connected) {
      throw StateError('Socket not connected');
    }
    final payload = <String, dynamic>{
      'sender_id': clientId,
      'recipient_id': recipientId,
      'envelope': envelope,
    };
    if (clientMsgId != null) {
      payload['client_msg_id'] = clientMsgId;
    }
    s.emit('message:send', payload);
  }

  void acknowledgeDelivery({required String msgId, required String senderId}) {
    final s = _socket;
    if (s == null || !s.connected) return;
    s.emit('message:delivered', {
      'msg_id': msgId,
      'sender_id': senderId,
    });
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final s = _socket;
    _socket = null;
    if (s != null) {
      try {
        s.clearListeners();
        s.disconnect();
        s.dispose();
      } catch (_) {}
    }
    await _statusController.close();
    await _messageController.close();
    await _ackController.close();
  }
}

class IncomingMessage {
  IncomingMessage({
    required this.msgId,
    required this.senderId,
    required this.envelope,
  });

  final String msgId;
  final String senderId;
  final Map<String, dynamic> envelope;

  factory IncomingMessage.fromJson(Map<String, dynamic> json) {
    return IncomingMessage(
      msgId: json['msg_id'] as String? ?? '',
      senderId: json['sender_id'] as String? ?? '',
      envelope: Map<String, dynamic>.from(json['envelope'] as Map? ?? {}),
    );
  }
}

enum AckKind { queued, delivered }

class MessageAck {
  MessageAck({required this.msgId, required this.kind, this.clientMsgId});
  final String msgId;
  final String? clientMsgId;
  final AckKind kind;
}
