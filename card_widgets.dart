import 'package:flutter/material.dart';

import '../game/cards.dart';

const List<Color> _monthColors = [
  Color(0xFF2E7D32),
  Color(0xFFD81B60),
  Color(0xFFEC407A),
  Color(0xFF5D4037),
  Color(0xFF7B1FA2),
  Color(0xFFC62828),
  Color(0xFF8D6E63),
  Color(0xFF283593),
  Color(0xFFF9A825),
  Color(0xFFE65100),
  Color(0xFF4E342E),
  Color(0xFF455A64),
];

Color _groupColor(TtiGroup g) {
  if (g == TtiGroup.hong) return const Color(0xFFD32F2F);
  if (g == TtiGroup.cheong) return const Color(0xFF1976D2);
  if (g == TtiGroup.cho) return const Color(0xFF388E3C);
  return const Color(0xFF757575);
}

/// 화투 한 장. id가 null이면 뒷면이다. 모양은 전부 위젯으로 그린 단순한 도형이다.
class CardView extends StatelessWidget {
  const CardView({
    super.key,
    this.id,
    required this.w,
    this.selected = false,
    this.highlight = false,
    this.dim = false,
    this.animate = true,
    this.onTap,
  });

  final int? id;
  final double w;
  final bool selected;
  final bool highlight;
  final bool dim;
  final bool animate;
  final VoidCallback? onTap;

  double get h => w * 1.55;

  @override
  Widget build(BuildContext context) {
    final emphasized = selected || highlight;
    final borderColor = selected
        ? const Color(0xFF1565C0)
        : (highlight ? const Color(0xFFFFD600) : Colors.black54);

    final body = Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: id == null ? const Color(0xFF1A237E) : const Color(0xFFFFF8E7),
        borderRadius: BorderRadius.circular(w * 0.12),
        border: Border.all(color: borderColor, width: emphasized ? 3 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: id == null ? _back() : _face(allCards[id!]),
    );

    Widget out = Opacity(opacity: dim ? 0.4 : 1.0, child: body);
    out = AnimatedSlide(
      duration: const Duration(milliseconds: 150),
      offset: Offset(0, selected ? -0.14 : 0),
      child: out,
    );
    if (animate) {
      out = TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.6, end: 1.0),
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutBack,
        builder: (context, v, child) => Transform.scale(scale: v, child: child),
        child: out,
      );
    }
    if (onTap != null) {
      out = GestureDetector(onTap: onTap, child: out);
    }
    return out;
  }

  Widget _back() {
    return Center(
      child: Container(
        width: w * 0.5,
        height: w * 0.5,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white54, width: 1.5),
        ),
      ),
    );
  }

  Widget _face(CardInfo c) {
    final accent = _monthColors[c.month - 1];
    return Column(
      children: [
        Container(
          height: h * 0.26,
          width: double.infinity,
          color: accent,
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '${c.month}월',
              style: TextStyle(
                color: Colors.white,
                fontSize: w * 0.26,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        Expanded(child: Center(child: _marker(c))),
        if (w >= 30)
          Padding(
            padding: EdgeInsets.only(bottom: h * 0.04),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                monthNames[c.month - 1],
                style: TextStyle(fontSize: w * 0.2, color: Colors.black87),
              ),
            ),
          ),
      ],
    );
  }

  Widget _badge(double size, Color color, String text, {bool circle = false}) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(size * 0.2),
        border: Border.all(color: Colors.black54, width: 1),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: size * 0.5,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
      ),
    );
  }

  Widget _dot(double size) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFF9E9E9E),
      ),
    );
  }

  Widget _marker(CardInfo c) {
    final s = w * 0.5;
    if (c.kind == Kind.gwang) {
      return _badge(s, const Color(0xFFFFC107), '광', circle: true);
    }
    if (c.kind == Kind.yeol) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _badge(s, const Color(0xFFFF9800), '열'),
          if (c.godori)
            Text('★', style: TextStyle(fontSize: w * 0.2, color: Colors.red)),
        ],
      );
    }
    if (c.kind == Kind.tti) {
      return Container(
        width: s * 0.75,
        height: s * 1.25,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _groupColor(c.group),
          borderRadius: BorderRadius.circular(2),
        ),
        child: Text(
          '띠',
          style: TextStyle(
            color: Colors.white,
            fontSize: w * 0.17,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dot(w * 0.2),
            if (c.ssangpi) ...[
              SizedBox(width: w * 0.05),
              _dot(w * 0.2),
            ],
          ],
        ),
        Text(
          c.ssangpi ? '쌍피' : '피',
          style: TextStyle(fontSize: w * 0.17, color: Colors.black54),
        ),
      ],
    );
  }
}

/// 먹은 패를 광 열끗 띠 피 순서로 겹쳐서 한 줄로 보여 준다.
class CapturedRow extends StatelessWidget {
  const CapturedRow({super.key, required this.ids, required this.w});

  final List<int> ids;
  final double w;

  @override
  Widget build(BuildContext context) {
    final order = [Kind.gwang, Kind.yeol, Kind.tti, Kind.pi];
    final step = w * 0.4;
    final children = <Widget>[];
    for (final k in order) {
      final g = ids.where((id) => allCards[id].kind == k).toList()..sort();
      if (g.isEmpty) continue;
      children.add(
        SizedBox(
          width: w + step * (g.length - 1),
          height: w * 1.55,
          child: Stack(
            children: [
              for (var i = 0; i < g.length; i++)
                Positioned(
                  left: step * i,
                  child: CardView(
                    key: ValueKey('c${g[i]}'),
                    id: g[i],
                    w: w,
                    animate: false,
                  ),
                ),
            ],
          ),
        ),
      );
      children.add(SizedBox(width: w * 0.35));
    }
    if (children.isEmpty) return SizedBox(height: w * 1.55);
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }
}
