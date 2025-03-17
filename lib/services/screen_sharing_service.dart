import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'connection_service.dart';
import 'session_discovery_service.dart';

class ScreenSharingService {
  static final ScreenSharingService _instance = ScreenSharingService._internal();
  factory ScreenSharingService() => _instance;

  final _connectionService = ConnectionService();
  final _sessionDiscoveryService = SessionDiscoveryService();
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  bool _isHost = false;
  static const platform = MethodChannel('com.example.pro/screen_sharing');

  ScreenSharingService._internal();

  Future<void> startHosting(String teacherName) async {
    _isHost = true;
    
    try {
      // Start the foreground service
      await platform.invokeMethod('startScreenSharingService');
      
      // Start session discovery
      await _sessionDiscoveryService.startHosting(teacherName);
      
      // Get screen capture stream
      final Map<String, dynamic> mediaConstraints = {
        'audio': false,
        'video': {
          'mandatory': {
            'minWidth': '640',
            'minHeight': '480',
            'minFrameRate': '30',
          },
          'facingMode': 'environment',
          'optional': [],
        }
      };

      _localStream = await navigator.mediaDevices.getDisplayMedia(mediaConstraints);
      
      // Create peer connection
      _peerConnection = await createPeerConnection({
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'}
        ]
      });

      // Add local stream to peer connection
      _localStream?.getTracks().forEach((track) {
        _peerConnection?.addTrack(track, _localStream!);
      });

      // Create offer
      RTCSessionDescription offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);

      // Set up ICE candidate handling
      _peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
        _connectionService.sendMessage(jsonEncode({
          'type': 'candidate',
          'candidate': candidate.toMap(),
        }));
      };
    } catch (e) {
      print('Error starting screen sharing: $e');
      rethrow;
    }
  }

  Future<void> stopHosting() async {
    try {
      _localStream?.getTracks().forEach((track) => track.stop());
      await _peerConnection?.close();
      await _sessionDiscoveryService.stopHosting();
      await platform.invokeMethod('stopScreenSharingService');
      _isHost = false;
    } catch (e) {
      print('Error stopping screen sharing: $e');
      rethrow;
    }
  }

  Future<void> joinSession(TeacherSession teacher) async {
    _isHost = false;
    
    try {
      // Create peer connection
      _peerConnection = await createPeerConnection({
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'}
        ]
      });

      // Handle incoming stream
      _peerConnection?.onTrack = (RTCTrackEvent event) {
        if (event.track.kind == 'video') {
          // Handle the incoming video stream
          // This will be implemented in the UI
        }
      };

      // Set up ICE candidate handling
      _peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
        _connectionService.sendMessage(jsonEncode({
          'type': 'candidate',
          'candidate': candidate.toMap(),
        }));
      };

      // Connect to the teacher's session
      await _connectionService.joinHost();
    } catch (e) {
      print('Error joining session: $e');
      rethrow;
    }
  }

  Future<void> leaveSession() async {
    await _peerConnection?.close();
    _connectionService.dispose();
  }

  Stream<List<TeacherSession>> discoverTeachers() {
    return _sessionDiscoveryService.discoverTeachers();
  }

  MediaStream? get localStream => _localStream;
  RTCPeerConnection? get peerConnection => _peerConnection;
  bool get isHost => _isHost;
} 