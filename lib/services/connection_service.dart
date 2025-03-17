import 'dart:async';
import 'dart:io';

class ConnectionService {
  static final ConnectionService _instance = ConnectionService._internal();
  factory ConnectionService() => _instance;

  Socket? _socket;
  final _messageController = StreamController<String>.broadcast();
  Stream<String> get onMessage => _messageController.stream;
  bool _isConnected = false;
  Timer? _reconnectTimer;
  String? _lastHost;
  int? _lastPort;

  ConnectionService._internal();

  bool get isConnected => _isConnected;

  Future<void> connect(String host, int port) async {
    try {
      print('Connecting to $host:$port');
      _lastHost = host;
      _lastPort = port;
      
      _socket = await Socket.connect(host, port);
      _isConnected = true;
      print('Connected to $host:$port');

      _socket!.listen(
        (data) {
          final message = String.fromCharCodes(data);
          print('Received: $message');
          _messageController.add(message);
        },
        onError: (error) {
          print('Connection error: $error');
          _handleDisconnection();
        },
        onDone: () {
          print('Connection closed');
          _handleDisconnection();
        },
      );

      // Start keep-alive timer
      _startKeepAliveTimer();
    } catch (e) {
      print('Error connecting: $e');
      _handleDisconnection();
    }
  }

  void _handleDisconnection() {
    _isConnected = false;
    _socket?.close();
    _socket = null;
    _stopKeepAliveTimer();
    
    // Try to reconnect if we have last connection details
    if (_lastHost != null && _lastPort != null) {
      _startReconnectTimer();
    }
  }

  void _startReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (!_isConnected && _lastHost != null && _lastPort != null) {
        print('Attempting to reconnect to ${_lastHost}:${_lastPort}');
        await connect(_lastHost!, _lastPort!);
      } else {
        timer.cancel();
      }
    });
  }

  void _startKeepAliveTimer() {
    Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_isConnected) {
        sendMessage('keepalive');
      } else {
        timer.cancel();
      }
    });
  }

  void _stopKeepAliveTimer() {
    _reconnectTimer?.cancel();
  }

  void sendMessage(String message) {
    if (_isConnected && _socket != null) {
      try {
        _socket!.add(message.codeUnits);
      } catch (e) {
        print('Error sending message: $e');
        _handleDisconnection();
      }
    } else {
      print('Cannot send message: Not connected');
    }
  }

  void dispose() {
    _stopKeepAliveTimer();
    _socket?.close();
    _messageController.close();
  }
} 