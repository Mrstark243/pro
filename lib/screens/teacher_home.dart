import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/screen_sharing_service.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';

class TeacherHomeScreen extends StatefulWidget {
  const TeacherHomeScreen({super.key});

  @override
  State<TeacherHomeScreen> createState() => _TeacherHomeScreenState();
}

class _TeacherHomeScreenState extends State<TeacherHomeScreen> with SingleTickerProviderStateMixin {
  final _screenSharingService = ScreenSharingService();
  final _authService = AuthService();
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isSharing = false;
  String _teacherName = '';

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
    
    if (_isSharing) {
      setState(() {
        _isSharing = false;
      });
      _controller.reverse();
      try {
        await _screenSharingService.stopHosting();
      } catch (e) {
        _handleError(e);
      }
    } else {
      // Show dialog to get teacher's name
      final name = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Enter Your Name'),
          content: TextField(
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Your name will be shown to students',
            ),
            onSubmitted: (value) => Navigator.pop(context, value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final textField = context.findRenderObject() as RenderBox;
                final text = textField.toString();
                Navigator.pop(context, text);
              },
              child: const Text('Start Sharing'),
            ),
          ],
        ),
      );

      if (name != null && name.isNotEmpty) {
        setState(() {
          _isSharing = true;
          _teacherName = name;
        });
        _controller.forward();
        try {
          await _screenSharingService.startHosting(name);
        } catch (e) {
          _handleError(e);
        }
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

  Future<void> _handleLogout() async {
    HapticFeedback.mediumImpact();
    
    // Show confirmation dialog
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (shouldLogout == true) {
      // Stop screen sharing if active
      if (_isSharing) {
        await _screenSharingService.stopHosting();
      }
      
      // Logout
      await _authService.logout();
      
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/login');
    }
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
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _handleLogout,
          ),
        ],
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
            if (_isSharing) ...[
              const SizedBox(height: 8),
              Text(
                'Students can find you as: $_teacherName',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.onBackground.withOpacity(0.7),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
