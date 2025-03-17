import 'dart:async';
import 'dart:io';

class SessionDiscoveryService {
  static final SessionDiscoveryService _instance = SessionDiscoveryService._internal();
  factory SessionDiscoveryService() => _instance;

  static const int _port = 4567;
  RawDatagramSocket? _socket;
  Timer? _broadcastTimer;
  bool _isHosting = false;
  String? _teacherName;
  final _controller = StreamController<List<TeacherSession>>.broadcast();
  final _teachers = <String>{};

  SessionDiscoveryService._internal();

  Future<void> startHosting(String teacherName) async {
    if (_isHosting) return;

    _teacherName = teacherName;
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, _port);
    
    // Start broadcasting presence
    _broadcastTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _broadcastPresence();
    });

    _isHosting = true;
  }

  void _broadcastPresence() {
    if (!_isHosting || _socket == null) return;

    final message = 'TEACHER:$_teacherName';
    final data = message.codeUnits;
    
    // Broadcast to all devices on the local network
    _socket?.send(
      data,
      InternetAddress('255.255.255.255'),
      _port,
    );
  }

  Future<void> stopHosting() async {
    _broadcastTimer?.cancel();
    _socket?.close();
    _socket = null;
    _isHosting = false;
    _teacherName = null;
  }

  Stream<List<TeacherSession>> discoverTeachers() {
    if (_socket != null) {
      _socket?.close();
    }

    // Create a new socket for discovery
    RawDatagramSocket.bind(InternetAddress.anyIPv4, _port).then((socket) {
      _socket = socket;
      socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket.receive();
          if (datagram != null) {
            final message = String.fromCharCodes(datagram.data);
            if (message.startsWith('TEACHER:')) {
              final teacherName = message.substring(8);
              if (!_teachers.contains(teacherName)) {
                _teachers.add(teacherName);
                _controller.add([TeacherSession(name: teacherName)]);
              }
            }
          }
        }
      });
    });

    return _controller.stream;
  }

  void dispose() {
    _broadcastTimer?.cancel();
    _socket?.close();
    _socket = null;
    _isHosting = false;
    _teacherName = null;
    _controller.close();
    _teachers.clear();
  }
}

class TeacherSession {
  final String name;
  
  TeacherSession({required this.name});
} 