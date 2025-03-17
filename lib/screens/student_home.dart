import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../services/screen_sharing_service.dart';
import '../services/session_discovery_service.dart';
import '../theme/app_theme.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/auth_service.dart';
import '../widgets/teacher_ip_input.dart';

class StudentHomeScreen extends StatefulWidget {
  const StudentHomeScreen({super.key});

  @override
  State<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends State<StudentHomeScreen> {
  final _screenSharingService = ScreenSharingService();
  final _sessionService = SessionDiscoveryService();
  final _ipController = TextEditingController();
  bool _isConnecting = false;
  bool _isConnected = false;
  List<TeacherSession> _teachers = [];
  StreamSubscription<List<TeacherSession>>? _teacherSubscription;

  @override
  void initState() {
    super.initState();
    _initializeRenderers();
  }

  Future<void> _initializeRenderers() async {
    await _screenSharingService.localRenderer.initialize();
    await _screenSharingService.remoteRenderer.initialize();
  }

  void _startDiscovery() {
    if (_ipController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter the teacher\'s IP address'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() {
      _isConnecting = true;
    });

    // Update the teacher's IP in the session service
    _sessionService.setTeacherIp(_ipController.text);
    
    // Start discovery
    _teacherSubscription = _sessionService.discoverTeachers().listen(
      (teachers) {
        setState(() {
          _teachers = teachers;
          _isConnecting = false;
        });
      },
      onError: (error) {
        setState(() {
          _isConnecting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $error'),
            backgroundColor: AppColors.error,
          ),
        );
      },
    );
  }

  void _stopDiscovery() {
    _teacherSubscription?.cancel();
    setState(() {
      _isConnecting = false;
    });
  }

  Future<void> _joinSession(TeacherSession teacher) async {
    try {
      setState(() {
        _isConnecting = true;
      });

      await _screenSharingService.joinSession(teacher.name);
      
      setState(() {
        _isConnected = true;
        _isConnecting = false;
      });

      // Set up video streams
      if (_screenSharingService.localStream != null) {
        _screenSharingService.localRenderer.srcObject = _screenSharingService.localStream;
      }
      if (_screenSharingService.remoteStream != null) {
        _screenSharingService.remoteRenderer.srcObject = _screenSharingService.remoteStream;
      }
    } catch (e) {
      setState(() {
        _isConnecting = false;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error joining session: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _leaveSession() async {
    try {
      await _screenSharingService.leaveSession();
      setState(() {
        _isConnected = false;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error leaving session: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _handleLogout() async {
    try {
      await _leaveSession();
      await AuthService().logout();
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/login');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error logging out: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Student Home'),
        backgroundColor: AppColors.surface,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _handleLogout,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TeacherIpInput(
              controller: _ipController,
              onConnect: _isConnecting ? _stopDiscovery : _startDiscovery,
            ),
            const SizedBox(height: 24),
            if (_isConnecting)
              const Center(
                child: CircularProgressIndicator(
                  color: AppColors.primary,
                ),
              ),
            if (_teachers.isNotEmpty)
              Expanded(
                child: ListView.builder(
                  itemCount: _teachers.length,
                  itemBuilder: (context, index) {
                    final teacher = _teachers[index];
                    return Card(
                      color: AppColors.surface,
                      child: ListTile(
                        leading: const Icon(Icons.person, color: AppColors.primary),
                        title: Text(
                          teacher.name,
                          style: const TextStyle(color: Colors.white),
                        ),
                        onTap: () => _joinSession(teacher),
                      ),
                    );
                  },
                ),
              ),
            if (_isConnected)
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: RTCVideoView(
                            _screenSharingService.remoteRenderer,
                            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                            mirror: false,
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: ElevatedButton(
                        onPressed: _leaveSession,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.error,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Leave Session'),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _ipController.dispose();
    _teacherSubscription?.cancel();
    _screenSharingService.dispose();
    _sessionService.dispose();
    super.dispose();
  }
}
