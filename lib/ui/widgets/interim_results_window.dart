import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:window_manager/window_manager.dart';
import 'package:screen_retriever/screen_retriever.dart';
import '../../services/state_manager.dart';
import '../theme/app_theme.dart';

class InterimOverlayUI extends StatefulWidget {
  final String windowId;
  final Map<String, dynamic> args;

  const InterimOverlayUI({
    super.key,
    required this.windowId,
    required this.args,
  });

  @override
  State<InterimOverlayUI> createState() => _InterimOverlayUIState();
}

class _InterimOverlayUIState extends State<InterimOverlayUI> with SingleTickerProviderStateMixin {
  String _interimText = "Recording...";
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    print('DEBUG: InterimOverlayUI.initState for window ${widget.windowId}');
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _setupWindow();
  }

  Future<void> _setupWindow() async {
    print('DEBUG: InterimOverlayUI._setupWindow starting...');
    // We rely on the parent process and GTK native code for frameless/transparency
    // to avoid MissingPluginException for window_manager in secondary process.
    
    // Listen for updates
    WindowController.fromWindowId(widget.windowId).setWindowMethodHandler((call) async {
      if (call.method == 'updateInterimText') {
        print('DEBUG: InterimOverlayUI received updateInterimText: ${call.arguments}');
        setState(() {
          _interimText = call.arguments as String;
          if (_interimText.isEmpty) _interimText = "Recording...";
        });
      }
      return null;
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 40, // Anchor strictly to bottom of the window
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                constraints: const BoxConstraints(minWidth: 200, maxWidth: 1000),
                child: CustomPaint(
                  painter: InterimResultsPainter(
                    accentColor: AppTheme.skyBlue,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Pulsing Dot
                        AnimatedBuilder(
                          animation: _pulseController,
                          builder: (context, child) {
                            return Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: AppTheme.skyBlue.withOpacity(0.3 + (_pulseController.value * 0.7)),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.skyBlue.withOpacity(0.5 * _pulseController.value),
                                    blurRadius: 10,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 16),
                        Flexible(
                          child: Text(
                            _interimText,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.2,
                              decoration: TextDecoration.none,
                              fontFamily: 'Inter',
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class InterimResultsPainter extends CustomPainter {
  final Color accentColor;

  InterimResultsPainter({required this.accentColor});

  @override
  void paint(Canvas canvas, Size size) {
    final Path path = Path();
    const double radius = 40.0;

    path.addRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      const Radius.circular(radius),
    ));

    // Gradient background for a more polished look
    final Paint fillPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xF21A1A1A),
          Color(0xE62D2D2D),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    // Subtle blue glowing border (matched to theme)
    final Paint borderPaint = Paint()
      ..color = accentColor.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // Inner glow
    final Paint glowPaint = Paint()
      ..color = accentColor.withOpacity(0.1)
      ..maskFilter = const MaskFilter.blur(BlurStyle.inner, 10.0)
      ..style = PaintingStyle.fill;

    // Shadow
    canvas.drawShadow(path, Colors.black.withOpacity(0.5), 20.0, true);
    
    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
