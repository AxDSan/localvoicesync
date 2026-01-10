import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:math' as math;
import 'dart:ui';
import '../../ui/theme/app_theme.dart';
import '../../services/state_manager.dart';
import '../../ui/pages/app_shell.dart';
import '../../ui/widgets/app_clickable.dart';
import 'voice_sync_manager.dart';

class RecordPage extends ConsumerStatefulWidget {
  const RecordPage({super.key});

  @override
  ConsumerState<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends ConsumerState<RecordPage>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _waveController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _waveAnimation;
  
  // Smoothing for waveform
  late List<double> _currentHeights;
  late List<double> _targetHeights;
  static const int _barCount = 32;

  @override
  void initState() {
    super.initState();
    _currentHeights = List.filled(_barCount, 0.05);
    _targetHeights = List.filled(_barCount, 0.05);

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _waveController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    )..addListener(() {
        setState(() {
          for (int i = 0; i < _barCount; i++) {
            _currentHeights[i] = lerpDouble(_currentHeights[i], _targetHeights[i], 0.2)!;
          }
        });
      });

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _waveAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _waveController, curve: Curves.linear),
    );
    
    _waveController.repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Use the direct state notifier for immediate UI updates
    final recordingState = ref.watch(recordingStateNotifierProvider);
    final isRecording = recordingState == RecordingState.recording;

    if (isRecording) {
      _pulseController.repeat();
    } else {
      _pulseController.stop();
      _pulseController.reset();
    }

    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      body: Container(
        color: AppTheme.bgLight,
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildWaveformVisualizer(context),
                    const SizedBox(height: 60),
                    _buildRecordingButton(context, isRecording),
                    const SizedBox(height: 40),
                    _buildModeSelector(context),
                    const SizedBox(height: 40),
                    _buildStatusCard(context),
                  ],
                ),
              ),
              _buildBottomBar(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.skyBlue,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.mic_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Voice Sync',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppTheme.textDark,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              Text(
                'Ready to capture',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.textGray,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWaveformVisualizer(BuildContext context) {
    final manager = ref.read(voiceSyncManagerProvider);
    
    return StreamBuilder<double>(
      stream: manager.audioService.volumeStream,
      initialData: 0.0,
      builder: (context, snapshot) {
        final volume = snapshot.data ?? 0.0;
        
        // Update targets for the CustomPainter
        for (int i = 0; i < _barCount; i++) {
          // Center-weighted distribution
          double centerDistance = (i - (_barCount / 2)).abs() / (_barCount / 2);
          double weight = 1.0 - (centerDistance * 0.7);
          _targetHeights[i] = 0.05 + (volume * 0.95 * weight * (0.8 + math.Random().nextDouble() * 0.4));
        }
        
        return Container(
          height: 120,
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.black.withOpacity(0.05),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: CustomPaint(
            painter: WaveformPainter(
              heights: _currentHeights,
              color: AppTheme.skyBlue,
            ),
          ),
        );
      },
    );
  }

  Widget _buildRecordingButton(BuildContext context, bool isRecording) {
    final manager = ref.read(voiceSyncManagerProvider);

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return AppClickable(
          onTap: () {
            if (isRecording) {
              manager.stopRecording();
            } else {
              manager.startRecording();
            }
          },
          borderRadius: BorderRadius.circular(70),
          scaleOnPress: 0.9,
          child: Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isRecording ? Colors.red.shade400 : AppTheme.skyBlue,
              boxShadow: [
                BoxShadow(
                  color: (isRecording ? Colors.red : AppTheme.skyBlue).withOpacity(0.2),
                  blurRadius: 20 * _pulseAnimation.value,
                  spreadRadius: 5 * _pulseAnimation.value,
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (isRecording)
                  Container(
                    width: 140 * _pulseAnimation.value,
                    height: 140 * _pulseAnimation.value,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.red.withOpacity(0.3),
                        width: 2,
                      ),
                    ),
                  ),
                Icon(
                  isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                  size: isRecording ? 50 : 60,
                  color: Colors.white,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildModeSelector(BuildContext context) {
    final settings = ref.watch(settingsServiceProvider);
    final currentMode = settings.recordingMode;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildModeChip(
            context,
            'Manual',
            Icons.touch_app_rounded,
            currentMode == 'Manual',
            () {
              settings.recordingMode = 'Manual';
              ref.read(voiceSyncManagerProvider).stopListening();
            },
          ),
          const SizedBox(width: 12),
          _buildModeChip(
            context,
            'Live',
            Icons.radio_button_checked_rounded,
            currentMode == 'Live',
            () {
              settings.recordingMode = 'Live';
              ref.read(voiceSyncManagerProvider).startListening();
            },
          ),
          const SizedBox(width: 12),
          _buildModeChip(
            context,
            'PTT',
            Icons.push_pin_rounded,
            currentMode == 'PTT',
            () {
              settings.recordingMode = 'PTT';
              ref.read(voiceSyncManagerProvider).stopListening();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildModeChip(
    BuildContext context,
    String label,
    IconData icon,
    bool isSelected,
    VoidCallback onTap,
  ) {
    return AppClickable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.skyBlue : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? Colors.transparent : Colors.black.withOpacity(0.1),
            width: 1,
          ),
          boxShadow: isSelected ? [
            BoxShadow(
              color: AppTheme.skyBlue.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 2),
            )
          ] : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? Colors.white : AppTheme.textGray,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isSelected ? Colors.white : AppTheme.textGray,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(BuildContext context) {
    final statusMessage = ref.watch(statusMessageProvider);
    final elapsedMs = ref.watch(elapsedMsProvider);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.black.withOpacity(0.05),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.skyBlue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.info_outline_rounded,
                    color: AppTheme.skyBlue,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    statusMessage,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.textDark,
                          overflow: TextOverflow.ellipsis,
                        ),
                  ),
                ),
              ],
            ),
          ),
          if (elapsedMs > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${(elapsedMs / 1000).toStringAsFixed(1)}s',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Colors.transparent,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildQuickAction(
            context,
            'Settings',
            Icons.settings_outlined,
            () {
              ref.read(navigationProvider.notifier).state = 2;
            },
          ),
          const SizedBox(width: 16),
          _buildQuickAction(
            context,
            'History',
            Icons.history_outlined,
            () {
              ref.read(navigationProvider.notifier).state = 1;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAction(
    BuildContext context,
    String label,
    IconData icon,
    VoidCallback onTap,
  ) {
    return AppClickable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.black.withOpacity(0.05),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: AppTheme.textGray,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textGray,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class WaveformPainter extends CustomPainter {
  final List<double> heights;
  final Color color;

  WaveformPainter({required this.heights, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.8)
      ..style = PaintingStyle.fill
      ..strokeCap = StrokeCap.round;

    final barWidth = size.width / (heights.length * 2);
    final centerY = size.height / 2;

    for (int i = 0; i < heights.length; i++) {
      final h = heights[i] * size.height * 0.8;
      final x = (i * 2 * barWidth) + barWidth;
      
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(x, centerY), width: barWidth * 0.8, height: math.max(4.0, h)),
          const Radius.circular(4),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant WaveformPainter oldDelegate) => true;
}
