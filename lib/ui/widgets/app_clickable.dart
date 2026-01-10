import 'package:flutter/material.dart';

class AppClickable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final bool isSelected;
  final BorderRadius? borderRadius;
  final Color? hoverColor;
  final Color? pressColor;
  final double scaleOnPress;

  const AppClickable({
    super.key,
    required this.child,
    this.onTap,
    this.isSelected = false,
    this.borderRadius,
    this.hoverColor,
    this.pressColor,
    this.scaleOnPress = 0.95,
  });

  @override
  State<AppClickable> createState() => _AppClickableState();
}

class _AppClickableState extends State<AppClickable> with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  bool _isPressed = false;
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: widget.scaleOnPress).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) {
          setState(() => _isPressed = true);
          _controller.forward();
        },
        onTapUp: (_) {
          setState(() => _isPressed = false);
          _controller.reverse();
        },
        onTapCancel: () {
          setState(() => _isPressed = false);
          _controller.reverse();
        },
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              borderRadius: widget.borderRadius ?? BorderRadius.circular(12),
              color: _isPressed
                  ? (widget.pressColor ?? Colors.white.withOpacity(0.1))
                  : (_isHovered
                      ? (widget.hoverColor ?? Colors.white.withOpacity(0.05))
                      : Colors.transparent),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
