/// Self-contained ticking clock for the hero card. Only this widget
/// rebuilds each second, not the whole alarm list.
library;

import 'dart:async';

import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../services/theme_provider.dart';
import '../theme/app_theme.dart';

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
    final use24 = context.watch<ThemeProvider>().use24Hour;
    const small = TextStyle(
      fontFamily: AppTheme.display,
      fontSize: 20,
      fontWeight: FontWeight.w500,
      color: Colors.white70,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          DateFormat(use24 ? 'HH:mm' : 'h:mm').format(_now),
          style: const TextStyle(
            fontFamily: AppTheme.display,
            fontSize: 68,
            height: 1,
            fontWeight: FontWeight.w600,
            color: Colors.white,
            letterSpacing: -1,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 6),
        Text(DateFormat(':ss').format(_now), style: small),
        if (!use24) ...[
          const SizedBox(width: 6),
          Text(DateFormat('a').format(_now), style: small),
        ],
      ],
    );
  }
}
