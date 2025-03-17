import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

class ConnectionService {
  static final ConnectionService _instance = ConnectionService._internal();
  factory ConnectionService() => _instance;

  WebSocketChannel? _channel;
  Function(String)? onMessage;
  bool _isHost = false;

  ConnectionService._internal();

  Future<void> startHosting() async {
    _isHost = true;
    // In a real app, you would create a WebSocket server here
    // For now, we'll just simulate the connection
    print('Host started');
  }

  Future<void> joinHost() async {
    _isHost = false;
    // In a real app, you would connect to the WebSocket server here
    // For now, we'll just simulate the connection
    print('Joined host');
  }

  void sendMessage(String message) {
    if (_channel != null) {
      _channel!.sink.add(jsonEncode(message));
    }
  }

  void dispose() {
    _channel?.sink.close();
  }

  bool get isHost => _isHost;
} 