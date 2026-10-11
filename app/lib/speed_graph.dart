import 'package:flutter/material.dart';

import 'history.dart';
import 'theme.dart';

/// Roller-speed sparkline / graph (design "speed graph").
class SpeedGraph extends StatelessWidget {
  const SpeedGraph({
    super.key,
    required this.samples,
    this.height = 120,
  });

  final List<SpeedSample> samples;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _SpeedGraphPainter(samples: samples, palette: p),
        child: samples.isEmpty
            ? Center(
                child: Text('AWAITING SAMPLES',
                    style: AppText.labelMicro.copyWith(color: p.textFaint)),
              )
            : null,
      ),
    );
  }
}

class _SpeedGraphPainter extends CustomPainter {
  _SpeedGraphPainter({required this.samples, required this.palette});

  final List<SpeedSample> samples;
  final Palette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final p = palette;
    final rect = Offset.zero & size;

    canvas.drawRect(rect, Paint()..color = p.inset);

    // Horizontal grid lines.
    final grid = Paint()
      ..color = p.hairline
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    if (samples.length < 2) return;

    final maxValue = samples
        .map((s) => s.rpm)
        .fold<double>(1, (a, b) => b > a ? b : a)
        .clamp(10, double.infinity);

    Offset pointAt(int i) {
      final x = size.width * i / (samples.length - 1);
      final norm = (samples[i].rpm / maxValue).clamp(0.0, 1.0);
      final y = size.height - norm * (size.height - 6) - 3;
      return Offset(x, y);
    }

    final line = Path()..moveTo(pointAt(0).dx, pointAt(0).dy);
    for (var i = 1; i < samples.length; i++) {
      final pt = pointAt(i);
      line.lineTo(pt.dx, pt.dy);
    }

    // Area fill.
    final area = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [p.accent.withValues(alpha: 0.28), p.accent.withValues(alpha: 0.0)],
        ).createShader(rect),
    );

    // Line.
    canvas.drawPath(
      line,
      Paint()
        ..color = p.accent
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );

    // Leading dot.
    final last = pointAt(samples.length - 1);
    canvas.drawCircle(last, 3, Paint()..color = p.accent);
  }

  @override
  bool shouldRepaint(covariant _SpeedGraphPainter oldDelegate) =>
      oldDelegate.samples != samples || oldDelegate.palette != palette;
}
