import 'package:flutter/material.dart' hide Text;
import 'package:spargo/shared/widgets/auto_translate_text.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/constants/app_tokens.dart';

class AnimatedCtaButton extends StatefulWidget {
  const AnimatedCtaButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.leading,
    this.expanded = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? leading;
  final bool expanded;

  @override
  State<AnimatedCtaButton> createState() => _AnimatedCtaButtonState();
}

class _AnimatedCtaButtonState extends State<AnimatedCtaButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final button = FilledButton(
      onPressed: widget.onPressed,
      child: Row(
        mainAxisSize: widget.expanded ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          if (widget.leading != null) ...<Widget>[
            Icon(widget.leading, size: 18),
            const SizedBox(width: AppSpacing.xs),
          ],
          Flexible(child: Text(widget.label)),
        ],
      ),
    );

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1,
        duration: AppDurations.micro,
        curve: Curves.easeOutCubic,
        child:
            (widget.expanded
                    ? SizedBox(width: double.infinity, child: button)
                    : button)
                .animate()
                .fadeIn(duration: 240.ms)
                .slideY(begin: 0.08, end: 0),
      ),
    );
  }
}
