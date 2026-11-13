import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

class ShakeWidget extends StatefulWidget {
  final Widget child;
  final Stream<void> shakeStream;
  const ShakeWidget({
    super.key,
    required this.child,
    required this.shakeStream,
  });

  @override
  State<ShakeWidget> createState() => _ShakeWidgetState();
}

class _ShakeWidgetState extends State<ShakeWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    Tween<double>(begin: 0, end: 24).animate(
      CurvedAnimation(parent: _controller, curve: const ElasticInCurve(0.4)),
    ).addListener(() => setState(() {}));
    widget.shakeStream.listen((_) {
      if (mounted) _controller.forward(from: 0.0);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Transform.translate(
    offset: Offset(math.sin(_controller.value * math.pi * 3) * 10, 0),
    child: widget.child,
  );
}
