import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_font.dart';

/// Shows a one-time, dismissible "spotlight" coach-mark around a target
/// widget (e.g. the noticeboard icon) the first time the retailer opens the
/// app — a dark backdrop with a rounded-rectangle cutout hugging the target's
/// own bounds, a pulsing outline, and a small tooltip bubble explaining what
/// it does. Shown at most once per install (stored in SharedPreferences).
class AppTourSpotlight {
  // Distinct SharedPreferences keys per tour stop — each stop is tracked (and
  // skippable) independently, so adding/reordering stops later doesn't
  // re-trigger ones the retailer already dismissed.
  static const noticeboardKey = 'retailer_noticeboard_tour_shown_v1';
  static const bookRideKey = 'retailer_book_ride_tour_shown_v1';
  static const missionKey = 'retailer_mission_tour_shown_v1';

  /// Call from the home screen's initState / postFrameCallback, after the
  /// target widget (identified by [targetKey]) has been laid out. Pass
  /// [onDismissed] to chain into the next tour stop once this one closes —
  /// it fires whether the retailer tapped "Got it" or tapped the backdrop.
  ///
  /// [padding] controls how much extra space the highlight box adds around
  /// the target's own bounds (so it hugs the widget instead of drawing a
  /// circle bigger than what it's pointing at).
  static Future<void> maybeShow({
    required BuildContext context,
    required GlobalKey targetKey,
    required String prefKey,
    required String title,
    required String description,
    VoidCallback? onDismissed,
    double padding = 6,
    double cornerRadius = 14,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(prefKey) == true) {
      onDismissed?.call();
      return; // already shown
    }

    if (!context.mounted) return;
    final box = targetKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) {
      onDismissed?.call();
      return;
    }

    final targetOffset = box.localToGlobal(Offset.zero);
    final targetRect = (targetOffset & box.size).inflate(padding);

    late OverlayEntry entry;
    void dismiss() {
      entry.remove();
      prefs.setBool(prefKey, true);
      onDismissed?.call();
    }

    entry = OverlayEntry(
      builder: (_) => _SpotlightOverlay(
        targetRect: targetRect,
        cornerRadius: cornerRadius,
        title: title,
        description: description,
        onDismiss: dismiss,
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(entry);
  }
}

class _SpotlightOverlay extends StatefulWidget {
  final Rect targetRect;
  final double cornerRadius;
  final String title;
  final String description;
  final VoidCallback onDismiss;

  const _SpotlightOverlay({
    required this.targetRect,
    required this.cornerRadius,
    required this.title,
    required this.description,
    required this.onDismiss,
  });

  @override
  State<_SpotlightOverlay> createState() => _SpotlightOverlayState();
}

class _SpotlightOverlayState extends State<_SpotlightOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _introController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _introController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    final rect = widget.targetRect;
    final showBelow = rect.center.dy < screen.height * 0.6;

    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onDismiss,
        child: Stack(
          children: [
            // Dark backdrop with a rounded-rect cutout hugging the target — fades in.
            AnimatedBuilder(
              animation: _introController,
              builder: (context, _) => CustomPaint(
                size: screen,
                painter: _SpotlightPainter(
                  rect: rect,
                  cornerRadius: widget.cornerRadius,
                  opacity: 0.72 * _introController.value,
                ),
              ),
            ),

            // Static outline right around the target.
            Positioned.fromRect(
              rect: rect,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(widget.cornerRadius),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ),

            // Pulsing "breathing" outline — the simple-but-cool bit.
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, _) {
                final t = _pulseController.value;
                final grow = t * 8;
                final pulseRect = rect.inflate(grow);
                final pulseOpacity = (1 - t).clamp(0.0, 1.0);
                return Positioned.fromRect(
                  rect: pulseRect,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(widget.cornerRadius + grow * 0.5),
                        border: Border.all(
                          color: Colors.white.withOpacity(pulseOpacity * 0.85),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),

            // Small triangle pointer, roughly under/above the target.
            Positioned(
              left: (rect.center.dx - 9).clamp(20.0, screen.width - 38.0),
              top: showBelow ? rect.bottom + 2 : rect.top - 11,
              child: FadeTransition(
                opacity: _introController,
                child: CustomPaint(
                  size: const Size(18, 9),
                  painter: _ArrowPainter(pointUp: !showBelow),
                ),
              ),
            ),

            // Tooltip bubble.
            Positioned(
              left: 20,
              right: 20,
              top: showBelow ? rect.bottom + 10 : null,
              bottom: showBelow ? null : screen.height - rect.top + 10,
              child: FadeTransition(
                opacity: _introController,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: Offset(0, showBelow ? -0.12 : 0.12),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(
                    parent: _introController,
                    curve: Curves.easeOutBack,
                  )),
                  child: _TourTooltip(
                    title: widget.title,
                    description: widget.description,
                    onDismiss: widget.onDismiss,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  final Rect rect;
  final double cornerRadius;
  final double opacity;

  _SpotlightPainter({
    required this.rect,
    required this.cornerRadius,
    required this.opacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final backdrop = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final hole = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(cornerRadius)));
    final combined = Path.combine(PathOperation.difference, backdrop, hole);
    canvas.drawPath(combined, Paint()..color = Colors.black.withOpacity(opacity));
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) =>
      oldDelegate.opacity != opacity ||
      oldDelegate.rect != rect ||
      oldDelegate.cornerRadius != cornerRadius;
}

class _ArrowPainter extends CustomPainter {
  final bool pointUp;
  _ArrowPainter({required this.pointUp});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;
    final path = Path();
    if (pointUp) {
      path.moveTo(0, size.height);
      path.lineTo(size.width / 2, 0);
      path.lineTo(size.width, size.height);
    } else {
      path.moveTo(0, 0);
      path.lineTo(size.width / 2, size.height);
      path.lineTo(size.width, 0);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ArrowPainter oldDelegate) => oldDelegate.pointUp != pointUp;
}

class _TourTooltip extends StatelessWidget {
  final String title;
  final String description;
  final VoidCallback onDismiss;

  const _TourTooltip({
    required this.title,
    required this.description,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontFamily: AppFont.fontFamily,
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: AppColor.fontColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: const TextStyle(
              fontFamily: AppFont.fontFamily,
              fontSize: 12.5,
              color: Colors.grey,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: onDismiss,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColor.themeColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Got it',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    fontFamily: AppFont.fontFamily,
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
