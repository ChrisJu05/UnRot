import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

/// Renders an SVG string without flicker when it changes rapidly (sliders,
/// animations): the previous picture stays visible until the next one is ready.
class LiveSvg extends StatefulWidget {
  const LiveSvg(this.svg, {super.key});

  final String svg;

  @override
  State<LiveSvg> createState() => _LiveSvgState();
}

class _LiveSvgState extends State<LiveSvg> {
  PictureInfo? _picture;
  String? _loading;
  String? _queued;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load(widget.svg);
  }

  @override
  void didUpdateWidget(covariant LiveSvg oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.svg != widget.svg) _load(widget.svg);
  }

  Future<void> _load(String svg) async {
    if (_loading != null) {
      _queued = svg; // only the newest version matters
      return;
    }
    _loading = svg;
    try {
      final info = await vg.loadPicture(SvgStringLoader(svg), null);
      if (!mounted) {
        info.picture.dispose();
        return;
      }
      setState(() {
        _picture?.picture.dispose();
        _picture = info;
        _failed = false;
      });
    } catch (_) {
      if (mounted && _picture == null) setState(() => _failed = true);
    } finally {
      _loading = null;
      final next = _queued;
      _queued = null;
      if (next != null && mounted) _load(next);
    }
  }

  @override
  void dispose() {
    _picture?.picture.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return const Center(
        child: Text('This sketch could not be drawn.', style: TextStyle(color: Colors.white54)),
      );
    }
    final picture = _picture;
    if (picture == null) return const SizedBox.expand();
    return CustomPaint(painter: _PicturePainter(picture), size: Size.infinite);
  }
}

class _PicturePainter extends CustomPainter {
  _PicturePainter(this.info);
  final PictureInfo info;

  @override
  void paint(Canvas canvas, Size size) {
    final src = info.size;
    if (src.isEmpty) return;
    final scale = (size.width / src.width).clamp(0.0, size.height / src.height).toDouble();
    final dx = (size.width - src.width * scale) / 2, dy = (size.height - src.height * scale) / 2;
    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(scale);
    canvas.drawPicture(info.picture);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PicturePainter old) => old.info != info;
}
