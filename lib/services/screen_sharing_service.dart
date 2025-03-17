import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'connection_service.dart';
import 'session_discovery_service.dart';

class ScreenSharingService {
  static final ScreenSharingService _instance = ScreenSharingService._internal();
  factory ScreenSharingService() => _instance;

  final _connectionService = ConnectionService();
  final _sessionDiscoveryService = SessionDiscoveryService();
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  bool _isHost = false;
  static const platform = MethodChannel('com.example.pro/screen_sharing');
  static const int _port = 4567;
  bool _isBackgrounded = false;
  Timer? _keepAliveTimer;
  RTCPeerConnection? _peerConnection;
  bool _isWebRTCConnected = false;
  bool _isTCPConnected = false;
  Timer? _connectionCheckTimer;
  Socket? _tcpSocket;
  bool _isReconnecting = false;
  String? _currentTeacherName;

  ScreenSharingService._internal() {
    _connectionService.onMessage.listen(_handleMessage);
    _startKeepAliveTimer();
  }

  void _startKeepAliveTimer() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_isHost && !_isBackgrounded) {
        _connectionService.sendMessage(jsonEncode({
          'type': 'keepalive',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }));
      }
    });
  }

  Future<void> handleAppLifecycle(AppLifecycleState state) async {
    print('App lifecycle state changed to: $state');
    
    switch (state) {
      case AppLifecycleState.paused:
        _isBackgrounded = true;
        if (_isHost) {
          try {
            await platform.invokeMethod('keepScreenSharingAlive');
          } catch (e) {
            print('Error keeping screen sharing alive: $e');
          }
        }
        break;
        
      case AppLifecycleState.resumed:
        _isBackgrounded = false;
        if (_isHost && _peerConnection != null) {
          await _restoreConnection();
        }
        break;
        
      case AppLifecycleState.inactive:
        break;
        
      case AppLifecycleState.detached:
        await cleanup();
        break;

      case AppLifecycleState.hidden:
        _isBackgrounded = true;
        if (_isHost) {
          try {
            await platform.invokeMethod('keepScreenSharingAlive');
          } catch (e) {
            print('Error keeping screen sharing alive: $e');
          }
        }
        break;
    }
  }

  Future<void> _restoreConnection() async {
    try {
      print('Restoring WebRTC connection');
      if (_peerConnection != null) {
        if (_isHost) {
          final offer = await _peerConnection!.createOffer();
          await _peerConnection!.setLocalDescription(offer);
          _connectionService.sendMessage(jsonEncode({
            'type': 'offer',
            'sdp': offer.sdp,
          }));
        }
      }
    } catch (e) {
      print('Error restoring connection: $e');
    }
  }

  Future<void> _handleMessage(String message) async {
    try {
      if (message.startsWith('TEACHER:')) {
        // Handle teacher info message
        final parts = message.split(':');
        if (parts.length >= 2) {
          final teacherName = parts[1].split(' ')[0];
          _connectionService.sendMessage(jsonEncode({
            'type': 'join_request',
            'teacherName': teacherName,
          }));
        }
        return;
      }

      final data = jsonDecode(message);
      print('Received: $message');

      switch (data['type']) {
        case 'join_request':
          if (_isHost) {
            print('Student requesting to join');
            _connectionService.sendMessage(jsonEncode({
              'type': 'join_accepted',
            }));
          }
          break;
        case 'join_accepted':
          if (!_isHost) {
            print('Teacher accepted join request');
            _startWebRTCConnection();
          }
          break;
        case 'offer':
          if (_isHost) {
            await _handleOffer(data['sdp']);
          }
          break;
        case 'answer':
          if (!_isHost) {
            await _handleAnswer(data['sdp']);
          }
          break;
        case 'candidate':
          await _handleCandidate(RTCIceCandidate(
            data['candidate']['candidate'],
            data['candidate']['sdpMid'],
            data['candidate']['sdpMLineIndex'],
          ));
          break;
        case 'keepalive':
          _connectionService.sendMessage(jsonEncode({
            'type': 'keepalive_ack',
          }));
          break;
        case 'keepalive_ack':
          _isTCPConnected = true;
          break;
      }
    } catch (e) {
      print('Error handling message: $e');
      if (!_isReconnecting) {
        _handleConnectionLoss();
      }
    }
  }

  Future<void> _startWebRTCConnection() async {
    try {
      if (_isHost) {
        // Host creates peer connection when student requests to join
        _peerConnection = await createPeerConnection({
          'iceServers': [
            {'urls': 'stun:stun.l.google.com:19302'},
            {'urls': 'stun:stun1.l.google.com:19302'},
            {'urls': 'stun:stun2.l.google.com:19302'},
            {'urls': 'stun:stun3.l.google.com:19302'},
            {'urls': 'stun:stun4.l.google.com:19302'},
            {'urls': 'stun:stun5.l.google.com:19302'},
            {'urls': 'stun:stun6.l.google.com:19302'},
            {'urls': 'stun:stun7.l.google.com:19302'},
          ],
          'iceTransportPolicy': 'all',
          'bundlePolicy': 'balanced',
          'rtcpMuxPolicy': 'require',
          'sdpSemantics': 'unified-plan',
        });

        _setupPeerConnectionHandlers();
        
        // Add local stream to peer connection
        _localStream?.getTracks().forEach((track) {
          _peerConnection?.addTrack(track, _localStream!);
        });
      } else {
        // Student creates peer connection and sends offer
        _peerConnection = await createPeerConnection({
          'iceServers': [
            {'urls': 'stun:stun.l.google.com:19302'},
            {'urls': 'stun:stun1.l.google.com:19302'},
            {'urls': 'stun:stun2.l.google.com:19302'},
            {'urls': 'stun:stun3.l.google.com:19302'},
            {'urls': 'stun:stun4.l.google.com:19302'},
            {'urls': 'stun:stun5.l.google.com:19302'},
            {'urls': 'stun:stun6.l.google.com:19302'},
            {'urls': 'stun:stun7.l.google.com:19302'},
          ],
          'iceTransportPolicy': 'all',
          'bundlePolicy': 'balanced',
          'rtcpMuxPolicy': 'require',
          'sdpSemantics': 'unified-plan',
        });

        _setupPeerConnectionHandlers();

        print('Creating offer to send to teacher');
        final offer = await _peerConnection!.createOffer({
          'offerToReceiveVideo': true,
          'offerToReceiveAudio': false,
          'mandatory': {
            'OfferToReceiveVideo': true,
            'OfferToReceiveAudio': false,
          },
          'optional': [],
        });
        await _peerConnection!.setLocalDescription(offer);

        _connectionService.sendMessage(jsonEncode({
          'type': 'offer',
          'sdp': offer.sdp,
        }));
      }

      _startConnectionMonitoring();
    } catch (e) {
      print('Error starting WebRTC connection: $e');
      _handleConnectionLoss();
    }
  }

  void _setupPeerConnectionHandlers() {
    _peerConnection?.onIceCandidate = (candidate) {
      print('Generated ICE candidate');
      _connectionService.sendMessage(jsonEncode({
        'type': 'candidate',
        'candidate': candidate.toMap(),
      }));
    };

    _peerConnection?.onConnectionState = (state) {
      print('Connection state changed: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        print('WebRTC connection established');
        _isWebRTCConnected = true;
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        print('WebRTC connection disconnected');
        _isWebRTCConnected = false;
        _handleConnectionLoss();
      }
    };

    _peerConnection?.onTrack = (event) {
      print('Received remote track: ${event.track.kind}');
      if (event.track.kind == 'video') {
        _remoteStream = event.streams[0];
        _remoteRenderer.srcObject = _remoteStream;
        print('Set remote stream to renderer');
      }
    };
  }

  void _startConnectionMonitoring() {
    _connectionCheckTimer?.cancel();
    _connectionCheckTimer = Timer.periodic(Duration(seconds: 5), (timer) {
      if (!_isTCPConnected || !_isWebRTCConnected) {
        print('Connection check failed - TCP: $_isTCPConnected, WebRTC: $_isWebRTCConnected');
        _handleConnectionLoss();
      }
    });

    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(Duration(seconds: 2), (timer) {
      if (_isTCPConnected) {
        _connectionService.sendMessage(jsonEncode({
          'type': 'keepalive',
        }));
      }
    });
  }

  Future<void> _handleConnectionLoss() async {
    if (_isReconnecting) return;
    _isReconnecting = true;

    try {
      print('Handling connection loss');
      _connectionCheckTimer?.cancel();
      _keepAliveTimer?.cancel();

      // Close existing connections
      await _peerConnection?.close();
      _peerConnection = null;
      _isWebRTCConnected = false;

      // Attempt to reconnect
      if (_isHost && _currentTeacherName != null) {
        await _sessionDiscoveryService.startHosting(_currentTeacherName!);
      } else if (!_isHost && _currentTeacherName != null) {
        await joinSession(_currentTeacherName!);
      }

      _isReconnecting = false;
    } catch (e) {
      print('Error during reconnection: $e');
      _isReconnecting = false;
    }
  }

  Future<void> _handleOffer(String sdp) async {
    if (_isHost) {
      try {
        print('Handling offer from student');
        final offer = RTCSessionDescription(sdp, 'offer');
        
        // Create new peer connection if needed
        if (_peerConnection == null) {
          _peerConnection = await createPeerConnection({
            'iceServers': [
              {'urls': 'stun:stun.l.google.com:19302'},
              {'urls': 'stun:stun1.l.google.com:19302'},
              {'urls': 'stun:stun2.l.google.com:19302'},
              {'urls': 'stun:stun3.l.google.com:19302'},
              {'urls': 'stun:stun4.l.google.com:19302'},
              {'urls': 'stun:stun5.l.google.com:19302'},
              {'urls': 'stun:stun6.l.google.com:19302'},
              {'urls': 'stun:stun7.l.google.com:19302'},
            ],
            'iceTransportPolicy': 'all',
            'bundlePolicy': 'balanced',
            'rtcpMuxPolicy': 'require',
            'sdpSemantics': 'unified-plan',
          });

          // Set up event handlers
          _peerConnection?.onIceCandidate = (candidate) {
            print('Generated ICE candidate');
            _connectionService.sendMessage(jsonEncode({
              'type': 'candidate',
              'candidate': candidate.toMap(),
            }));
          };

          _peerConnection?.onConnectionState = (state) {
            print('Connection state changed: $state');
            if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
              print('WebRTC connection established');
            } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
              print('Connection disconnected, attempting to restore...');
              _restoreConnection();
            }
          };

          _peerConnection?.onTrack = (event) {
            print('Received remote track: ${event.track.kind}');
            if (event.track.kind == 'video') {
              _remoteStream = event.streams[0];
              _remoteRenderer.srcObject = _remoteStream;
              print('Set remote stream to renderer');
            }
          };

          // Add local stream to peer connection
          _localStream?.getTracks().forEach((track) {
            _peerConnection?.addTrack(track, _localStream!);
          });
        }

        await _peerConnection?.setRemoteDescription(offer);
        final answer = await _peerConnection!.createAnswer();
        await _peerConnection!.setLocalDescription(answer);

        print('Sending answer to student');
        _connectionService.sendMessage(jsonEncode({
          'type': 'answer',
          'sdp': answer.sdp,
        }));
      } catch (e) {
        print('Error handling offer: $e');
        rethrow;
      }
    }
  }

  Future<void> _handleAnswer(String sdp) async {
    if (!_isHost) {
      try {
        print('Handling answer from teacher');
        final answer = RTCSessionDescription(sdp, 'answer');
        await _peerConnection?.setRemoteDescription(answer);
      } catch (e) {
        print('Error handling answer: $e');
        rethrow;
      }
    }
  }

  Future<void> _handleCandidate(RTCIceCandidate candidate) async {
    try {
      print('Handling ICE candidate');
      if (_peerConnection != null) {
        await _peerConnection!.addCandidate(candidate);
      }
    } catch (e) {
      print('Error handling candidate: $e');
    }
  }

  Future<void> startHosting(String teacherName) async {
    _isHost = true;
    _currentTeacherName = teacherName;
    
    try {
      print('Starting screen sharing as host');
      await platform.invokeMethod('startScreenSharingService', {
        'wakeLock': true,
        'notificationTitle': 'Screen Sharing Active',
        'notificationText': 'Tap to return to app',
      });
      
      await _sessionDiscoveryService.startHosting(teacherName);
      
      // Get screen capture stream with better quality settings
      final Map<String, dynamic> mediaConstraints = {
        'audio': false,
        'video': {
          'mandatory': {
            'minWidth': '1280',
            'minHeight': '720',
            'minFrameRate': '30',
            'maxWidth': '1920',
            'maxHeight': '1080',
            'maxFrameRate': '60',
          },
          'optional': [],
        }
      };

      _localStream = await navigator.mediaDevices.getDisplayMedia(mediaConstraints);
      print('Got local stream: ${_localStream?.id}');

      print('Waiting for student to connect...');

    } catch (e) {
      print('Error starting screen sharing: $e');
      rethrow;
    }
  }

  Future<void> joinSession(String teacherName) async {
    _currentTeacherName = teacherName;
    try {
      print('Joining session as student');
      final teachers = await _sessionDiscoveryService.discoverTeachers().first;
      final teacher = teachers.firstWhere((t) => t.name == teacherName);
      
      await _connectionService.connect(teacher.ip, _port);
      print('Connected to teacher at ${teacher.ip}');

      // Create peer connection with better configuration
      _peerConnection = await createPeerConnection({
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
          {'urls': 'stun:stun1.l.google.com:19302'},
          {'urls': 'stun:stun2.l.google.com:19302'},
          {'urls': 'stun:stun3.l.google.com:19302'},
          {'urls': 'stun:stun4.l.google.com:19302'},
          {'urls': 'stun:stun5.l.google.com:19302'},
          {'urls': 'stun:stun6.l.google.com:19302'},
          {'urls': 'stun:stun7.l.google.com:19302'},
        ],
        'iceTransportPolicy': 'all',
        'bundlePolicy': 'balanced',
        'rtcpMuxPolicy': 'require',
        'sdpSemantics': 'unified-plan',
      });

      // Set up event handlers
      _peerConnection?.onIceCandidate = (candidate) {
        print('Generated ICE candidate');
        _connectionService.sendMessage(jsonEncode({
          'type': 'candidate',
          'candidate': candidate.toMap(),
        }));
      };

      _peerConnection?.onTrack = (event) {
        print('Received remote track: ${event.track.kind}');
        if (event.track.kind == 'video') {
          _remoteStream = event.streams[0];
          _remoteRenderer.srcObject = _remoteStream;
          print('Set remote stream to renderer');
        }
      };

      _peerConnection?.onConnectionState = (state) {
        print('Connection state changed: $state');
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          print('WebRTC connection established');
        } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          print('Connection disconnected, attempting to restore...');
          _restoreConnection();
        }
      };

      // Create and send offer with better quality settings
      print('Creating offer to send to teacher');
      final offer = await _peerConnection!.createOffer({
        'offerToReceiveVideo': true,
        'offerToReceiveAudio': false,
        'mandatory': {
          'OfferToReceiveVideo': true,
          'OfferToReceiveAudio': false,
        },
        'optional': [],
      });
      await _peerConnection!.setLocalDescription(offer);

      _connectionService.sendMessage(jsonEncode({
        'type': 'offer',
        'sdp': offer.sdp,
      }));

    } catch (e) {
      print('Error joining session: $e');
      rethrow;
    }
  }

  Future<void> stopHosting() async {
    try {
      print('Stopping screen sharing');
      _localStream?.getTracks().forEach((track) => track.stop());
      await _peerConnection?.close();
      await _sessionDiscoveryService.stopHosting();
      await platform.invokeMethod('stopScreenSharingService');
      _isHost = false;
      _peerConnection = null;
      _isBackgrounded = false;
    } catch (e) {
      print('Error stopping screen sharing: $e');
      rethrow;
    }
  }

  Future<void> leaveSession() async {
    try {
      print('Leaving session');
      await _peerConnection?.close();
      await _localStream?.dispose();
      await _remoteStream?.dispose();
      _localStream = null;
      _remoteStream = null;
      _peerConnection = null;
    } catch (e) {
      print('Error leaving session: $e');
      rethrow;
    }
  }

  Stream<List<TeacherSession>> discoverTeachers() {
    return _sessionDiscoveryService.discoverTeachers();
  }

  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;
  RTCVideoRenderer get localRenderer => _localRenderer;
  RTCVideoRenderer get remoteRenderer => _remoteRenderer;

  Future<void> cleanup() async {
    print('Cleaning up ScreenSharingService');
    _keepAliveTimer?.cancel();
    await leaveSession();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
  }

  @override
  Future<void> dispose() async {
    _connectionCheckTimer?.cancel();
    _keepAliveTimer?.cancel();
    await _peerConnection?.close();
    _connectionService.dispose();
    _sessionDiscoveryService.dispose();
    await _remoteRenderer.dispose();
    await _localRenderer.dispose();
  }
} 