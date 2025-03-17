import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/screen_sharing_service.dart';
import '../theme/app_theme.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class StudentHomeScreen extends StatefulWidget {
  const StudentHomeScreen({super.key});

  @override
  State<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends State<StudentHomeScreen> with SingleTickerProviderStateMixin {
  final _screenSharingService = ScreenSharingService();
  final _remoteRenderer = RTCVideoRenderer();
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    _initializeRenderer();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );
  }

  Future<void> _initializeRenderer() async {
    await _remoteRenderer.initialize();
  }

  @override
  void dispose() {
    _remoteRenderer.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _toggleConnection() async {
    HapticFeedback.mediumImpact();
    
    setState(() {
      _isConnected = !_isConnected;
    });

    if (_isConnected) {
      _controller.forward();
      try {
        await _screenSharingService.joinSession();
        // Set up remote stream when available
        if (_screenSharingService.peerConnection != null) {
          _screenSharingService.peerConnection!.onTrack = (RTCTrackEvent event) {
            if (event.track.kind == 'video') {
              _remoteRenderer.srcObject = event.streams[0];
            }
          };
        }
      } catch (e) {
        _handleError(e);
      }
    } else {
      _controller.reverse();
      try {
        await _screenSharingService.leaveSession();
        _remoteRenderer.srcObject = null;
      } catch (e) {
        _handleError(e);
      }
    }
  }

  void _handleError(dynamic error) {
    setState(() {
      _isConnected = false;
    });
    _controller.reverse();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Error: $error'),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Student Screen'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            HapticFeedback.mediumImpact();
            Navigator.pop(context);
          },
        ),
      ),
      body: Column(
        children: [
          if (_isConnected && _remoteRenderer.srcObject != null)
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: AppColors.surface,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.2),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: RTCVideoView(
                    _remoteRenderer,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                  ),
                ),
              ),
            )
          else
            const Spacer(),
          Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _scaleAnimation.value,
                      child: Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isConnected ? AppColors.secondary : AppColors.primary,
                          boxShadow: [
                            BoxShadow(
                              color: (_isConnected ? AppColors.secondary : AppColors.primary).withOpacity(0.3),
                              blurRadius: 20,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _toggleConnection,
                            customBorder: const CircleBorder(),
                            child: Center(
                              child: Icon(
                                _isConnected ? Icons.logout : Icons.login,
                                size: 64,
                                color: AppColors.onPrimary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 32),
                Text(
                  _isConnected ? 'Leave Session' : 'Join Session',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 16),
                AnimatedOpacity(
                  opacity: _isConnected ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    'Connected to teacher\'s screen',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.secondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
