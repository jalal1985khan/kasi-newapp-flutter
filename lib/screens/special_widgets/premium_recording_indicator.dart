import 'package:flutter/material.dart';

class PremiumRecordingIndicator extends StatefulWidget {
  final Duration duration;
  final VoidCallback onCancel;
  final VoidCallback onStop;

  const PremiumRecordingIndicator({
    super.key,
    required this.duration,
    required this.onCancel,
    required this.onStop,
  });

  @override
  State<PremiumRecordingIndicator> createState() => _PremiumRecordingIndicatorState();
}

class _PremiumRecordingIndicatorState extends State<PremiumRecordingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
      child: Row(
        children: [
          // Main elongated coral pink capsule
          Expanded(
            child: GestureDetector(
              onTap: widget.onCancel, // Tap capsule to cancel/stop
              child: Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF2F2),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: const Color(0xFFFFC4C4),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    // Blinking Red Dot
                    FadeTransition(
                      opacity: Tween<double>(begin: 0.3, end: 1.0).animate(
                        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
                      ),
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFFE53935),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Bold Red text "Recording MM:SS"
                    Text(
                      "Recording ",
                      style: const TextStyle(
                        color: Color(0xFFE53935),
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      _formatDuration(widget.duration),
                      style: const TextStyle(
                        color: Color(0xFFE53935),
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Soft instruction "Click to stop" / cancel
                    Expanded(
                      child: Text(
                        "Click to cancel",
                        style: const TextStyle(
                          color: Color(0xFFEF9A9A),
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Separate Circular Stop Button
          GestureDetector(
            onTap: widget.onStop,
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFFFF9E9E),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Center(
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(3),
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
