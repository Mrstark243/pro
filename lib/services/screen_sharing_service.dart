import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter/services.dart';

class ScreenSharingService {
  static final ScreenSharingService _instance = ScreenSharingService._internal();
  factory ScreenSharingService() => _instance;

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  bool _isHost = false;
  static const platform = MethodChannel('com.example.pro/screen_sharing');

  ScreenSharingService._internal();

  Future<void> startHosting() async {
    _isHost = true;
    
    try {
      // Start the foreground service
      await platform.invokeMethod('startScreenSharingService');
      
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
        // Store the candidate for the student to use
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
      await platform.invokeMethod('stopScreenSharingService');
      _isHost = false;
    } catch (e) {
      print('Error stopping screen sharing: $e');
      rethrow;
    }
  }

  Future<void> joinSession() async {
    _isHost = false;
    
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
      // Store the candidate for the teacher to use
    };
  }

  Future<void> leaveSession() async {
    await _peerConnection?.close();
  }

  MediaStream? get localStream => _localStream;
  RTCPeerConnection? get peerConnection => _peerConnection;
  bool get isHost => _isHost;
} 