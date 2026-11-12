import 'dart:async';

import 'package:flutter/material.dart';

import 'card_widgets.dart';

/// 화면에 올라가는 카드 한 장의 목표 상태.
/// 위치(pos)와 크기(w)가 바뀌면 CardSprite가 시간에 따라 부드럽게 옮긴다.
class SpriteSpec {
  SpriteSpec({
    required this.key,
    required this.id,
    required this.pos,
    required this.w,
    required this.z,
    this.selected = false,
    this.highlight = false,
    this.dim = false,
    this.fast = false,
    this.onTap,
  });

  final String key;
  final int? id; // null이면 뒷면
  final Offset pos;
  final double w;
  final int z;
  final bool selected;
  final bool highlight;
  final bool dim;
  final bool fast;
  final VoidCallback? onTap;

  // 새로 나타난 카드가 출발할 위치. 없으면 목표 위치에 그냥 나타난다.
  Offset? spawn;
  double? spawnW;
  bool spawnFaceDown = false;

  // 이번 이동을 시작하기 전에 기다릴 시간 (더미를 뒤집는 동안 기다리게 한다)
  int delayMs = 0;
}

class CardSprite extends StatefulWidget {
  const CardSprite({super.key, required this.spec});

  final SpriteSpec spec;

  @override
  State<CardSprite> createState() => _CardSpriteState();
}

class _CardSpriteState extends State<CardSprite> {
  static const double _base = 44;

  late Offset _pos;
  late double _w;
  late bool _faceUp;
  Timer? _moveTimer;
  Timer? _flipTimer;

  @override
  void initState() {
    super.initState();
    final s = widget.spec;
    _pos = s.spawn ?? s.pos;
    _w = s.spawn != null ? (s.spawnW ?? s.w) : s.w;
    _faceUp = !s.spawnFaceDown;
    if (s.spawn != null) {
      final wait = s.delayMs < 30 ? 30 : s.delayMs;
      _moveTimer = Timer(Duration(milliseconds: wait), _goTarget);
    }
    if (s.spawnFaceDown) {
      _flipTimer = Timer(const Duration(milliseconds: 80), () {
        if (mounted) setState(() => _faceUp = true);
      });
    }
  }

  void _goTarget() {
    if (!mounted) return;
    setState(() {
      _pos = widget.spec.pos;
      _w = widget.spec.w;
    });
  }

  @override
  void didUpdateWidget(CardSprite oldWidget) {
    super.didUpdateWidget(oldWidget);
    final a = oldWidget.spec;
    final b = widget.spec;
    if (a.pos != b.pos || a.w != b.w) {
      final pending = _moveTimer != null && _moveTimer!.isActive;
      if (!pending) {
        if (b.delayMs > 0) {
          _moveTimer = Timer(Duration(milliseconds: b.delayMs), _goTarget);
        } else {
          _pos = b.pos;
          _w = b.w;
        }
      }
    }
  }

  @override
  void dispose() {
    _moveTimer?.cancel();
    _flipTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.spec;
    return AnimatedPositioned(
      duration: Duration(milliseconds: s.fast ? 260 : 520),
      curve: Curves.easeInOutCubic,
      left: _pos.dx,
      top: _pos.dy,
      width: _w,
      height: _w * 1.55,
      child: FittedBox(
        fit: BoxFit.fill,
        child: SizedBox(
          width: _base,
          height: _base * 1.55,
          child: FlipCard(
            faceUp: _faceUp,
            front: CardView(
              id: s.id,
              w: _base,
              selected: s.selected,
              highlight: s.highlight,
              dim: s.dim,
              animate: false,
              onTap: s.onTap,
            ),
            back: CardView(
              w: _base,
              highlight: s.highlight,
              animate: false,
              onTap: s.onTap,
            ),
          ),
        ),
      ),
    );
  }
}
