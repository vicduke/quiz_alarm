import 'dart:async';

import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

/// Self-contained ticking clock. Only this widget rebuilds each second,
/// not the whole alarm list.
class ClockDisplay extends StatefulWidget {
  const ClockDisplay({super.key});

  @override
  State<ClockDisplay> createState() => _ClockDisplayState();
}

class _ClockDisplayState extends State<ClockDisplay> {
  late DateTime _now;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      DateFormat('hh:mm:ss a').format(_now),
      style: const TextStyle(fontSize: 46, fontWeight: FontWeight.w300),
    );
  }
}
