import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/screen_sharing_service.dart';
import '../theme/app_theme.dart';

class TeacherHomeScreen extends StatefulWidget {
  const TeacherHomeScreen({super.key});

  @override
  State<TeacherHomeScreen> createState() => _TeacherHomeScreenState();
}

class _TeacherHomeScreenState extends State<TeacherHomeScreen> with SingleTickerProviderStateMixin {
  final _screenSharingService = ScreenSharingService();
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isSharing = false;

  @override
  void initState() {
    super.initState();
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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _toggleScreenSharing() async {
    HapticFeedback.mediumImpact();
    
    setState(() {
      _isSharing = !_isSharing;
    });

    if (_isSharing) {
      _controller.forward();
      try {
        await _screenSharingService.startHosting();
      } catch (e) {
        _handleError(e);
      }
    } else {
      _controller.reverse();
      try {
        await _screenSharingService.stopHosting();
      } catch (e) {
        _handleError(e);
      }
    }
  }

  void _handleError(dynamic error) {
    setState(() {
      _isSharing = false;
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
        title: const Text('Teacher Screen'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            HapticFeedback.mediumImpact();
            Navigator.pop(context);
          },
        ),
      ),
      body: Center(
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
                      color: _isSharing ? AppColors.secondary : AppColors.primary,
                      boxShadow: [
                        BoxShadow(
                          color: (_isSharing ? AppColors.secondary : AppColors.primary).withOpacity(0.3),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _toggleScreenSharing,
                        customBorder: const CircleBorder(),
                        child: Center(
                          child: Icon(
                            _isSharing ? Icons.stop_screen_share : Icons.screen_share,
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
              _isSharing ? 'Stop Sharing' : 'Start Sharing',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),
            AnimatedOpacity(
              opacity: _isSharing ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: Text(
                'Your screen is being shared',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppColors.secondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
