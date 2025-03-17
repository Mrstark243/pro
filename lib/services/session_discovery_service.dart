import 'dart:async';
import 'dart:io';

class SessionDiscoveryService {
  static final SessionDiscoveryService _instance = SessionDiscoveryService._internal();
  factory SessionDiscoveryService() => _instance;

  final _controller = StreamController<List<TeacherSession>>.broadcast();
  final _teachers = <TeacherSession>{};
  String? _teacherIp;
  String? _teacherName;
  ServerSocket? _server;
  Socket? _client;
  bool _isHosting = false;
  static const int _port = 4567;

  SessionDiscoveryService._internal();

  Future<void> startHosting(String teacherName) async {
    if (_isHosting) return;
    _isHosting = true;
    _teacherName = teacherName;

    _teacherIp = await _getLocalIpAddress();
    if (_teacherIp == null) {
      throw Exception('Could not determine local IP address');
    }

    print('Starting hosting with IP: $_teacherIp');

    try {
      // Start TCP server
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, _port);
      print('Teacher server listening on port $_port');

      // Listen for incoming connections
      _server!.listen((Socket client) {
        print('Student connected from ${client.remoteAddress.address}');
        _handleClientConnection(client);
      });
    } catch (e) {
      print('Error starting hosting: $e');
      rethrow;
    }
  }

  void _handleClientConnection(Socket client) {
    if (_teacherName == null || _teacherIp == null) {
      print('Error: Teacher name or IP not set');
      return;
    }

    // Send teacher name and IP to connected student
    final message = 'TEACHER:$_teacherName:$_teacherIp';
    client.add(message.codeUnits);
    print('Sent teacher info to student: $message');

    client.listen(
      (data) {
        final message = String.fromCharCodes(data);
        print('Received from student: $message');
      },
      onError: (error) {
        print('Error from student: $error');
      },
      onDone: () {
        print('Student disconnected');
      },
    );
  }

  Future<void> stopHosting() async {
    _isHosting = false;
    _teacherName = null;
    await _server?.close();
    _server = null;
    _teacherIp = null;
  }

  void setTeacherIp(String ip) {
    _teacherIp = ip;
    print('Teacher IP set to: $ip');
  }

  Stream<List<TeacherSession>> discoverTeachers() {
    print('Starting teacher discovery');
    _teachers.clear();

    if (_teacherIp == null) {
      print('Teacher IP not set');
      _controller.addError('Teacher IP not set');
      return _controller.stream;
    }

    // Try to connect to teacher's server
    Socket.connect(_teacherIp!, _port).then((socket) {
      print('Connected to teacher server at $_teacherIp');
      _client = socket;

      // Listen for teacher's response
      socket.listen(
        (data) {
          final message = String.fromCharCodes(data);
          print('Received from teacher: $message');
          
          if (message.startsWith('TEACHER:')) {
            try {
              final teacher = TeacherSession.fromString(message);
              // Use the IP we connected to instead of the one in the message
              final teacherWithCorrectIp = TeacherSession(
                name: teacher.name,
                ip: _teacherIp!, // Use the IP we successfully connected to
              );
              if (!_teachers.contains(teacherWithCorrectIp)) {
                _teachers.add(teacherWithCorrectIp);
                print('Found teacher: ${teacherWithCorrectIp.name} at ${teacherWithCorrectIp.ip}');
                _controller.add(_teachers.toList());
              }
            } catch (e) {
              print('Error parsing teacher session: $e');
            }
          }
        },
        onError: (error) {
          print('Error from teacher: $error');
          _controller.addError(error);
        },
        onDone: () {
          print('Teacher disconnected');
        },
      );
    }).catchError((error) {
      print('Error connecting to teacher: $error');
      _controller.addError(error);
    });

    return _controller.stream;
  }

  Future<String?> _getLocalIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list();
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            print('Found local IP: ${addr.address}');
            return addr.address;
          }
        }
      }
    } catch (e) {
      print('Error getting local IP: $e');
    }
    return null;
  }

  void dispose() {
    print('Disposing SessionDiscoveryService');
    _server?.close();
    _client?.close();
    _server = null;
    _client = null;
    _isHosting = false;
    _teacherName = null;
    _teacherIp = null;
    _controller.close();
    _teachers.clear();
  }
}

class TeacherSession {
  final String name;
  final String ip;

  TeacherSession({
    required this.name,
    required this.ip,
  });

  factory TeacherSession.fromString(String data) {
    final parts = data.split(':');
    if (parts.length != 3) {
      throw FormatException('Invalid teacher session data: $data');
    }
    return TeacherSession(
      name: parts[1],
      ip: parts[2],
    );
  }

  @override
  String toString() => 'TEACHER:$name:$ip';
} 