import 'package:flutter/material.dart';

// ─────────────────────────────────────────────
//  WIDGET
// ─────────────────────────────────────────────

class DioGradientProgressBar extends StatefulWidget {
  /// 0.0 → 1.0
  final double progress;

  /// Optional label shown above the bar (e.g. "Downloading…")
  final String? label;

  const DioGradientProgressBar({super.key, required this.progress, this.label});

  @override
  State<DioGradientProgressBar> createState() => _DioGradientProgressBarState();
}

class _DioGradientProgressBarState extends State<DioGradientProgressBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pct = (widget.progress * 100).clamp(0, 100).toStringAsFixed(0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.label!,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF6B7280),
                  letterSpacing: 0.3,
                ),
              ),
              // ── percentage badge ──
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  '$pct%',
                  key: ValueKey(pct),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF4F46E5),
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],

        // ── bar ──
        LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: [
                // Background track
                Container(
                  height: 10,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3),
                      width: 0.8,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),

                // Animated fill
                AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOutCubic,
                  height: 10,
                  width: constraints.maxWidth * widget.progress.clamp(0.0, 1.0),
                  child: AnimatedBuilder(
                    animation: _shimmerController,
                    builder: (context, _) {
                      return Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(100),
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: const [
                              Color(0xFF6366F1), // indigo
                              Color(0xFF8B5CF6), // violet
                              Color(0xFFA78BFA), // light violet
                              Color(0xFF6366F1),
                            ],
                            stops: [
                              0.0,
                              (_shimmerController.value - 0.3).clamp(0.0, 1.0),
                              _shimmerController.value.clamp(0.0, 1.0),
                              1.0,
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF6366F1).withOpacity(0.45),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),

        // ── percentage below bar (no label variant) ──
        if (widget.label == null) ...[
          const SizedBox(height: 5),
          Align(
            alignment: Alignment.centerRight,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                '$pct%',
                key: ValueKey(pct),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF4F46E5),
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
