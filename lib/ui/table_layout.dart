import 'dart:ui' show Offset;

import '../game/cards.dart';

/// 먹은 패를 놓는 칸의 배경 정보 (그림 설명용)
class BoardSlot {
  const BoardSlot(
    this.left,
    this.top,
    this.width,
    this.height,
    this.label,
    this.kind,
  );

  final double left;
  final double top;
  final double width;
  final double height;
  final String label;
  final String kind; // gwang yeol hong cheong cho tti pi
}

/// 먹은 패 한 칸의 크기 설정
class CapStyle {
  const CapStyle({
    required this.w,
    required this.step,
    required this.rowH,
    required this.piX,
    required this.piStep,
    required this.width,
  });

  final double w; // 카드 너비
  final double step; // 카드 가로 간격
  final double rowH; // 줄 간격
  final double piX; // 피 구역 시작 위치 (보드 왼쪽 기준)
  final double piStep; // 피 가로 간격
  final double width; // 보드 전체 너비
}

/// 게임판 좌표 계산. 모든 좌표는 900 x 405 가상 화면 기준이다.
/// 실제 화면에서는 이 판 전체를 비율에 맞춰 줄여서 보여 준다.
class TableLayout {
  TableLayout._();

  static const double width = 900;
  static const double height = 405;

  // 카드 크기 (너비 기준, 높이는 너비 x 1.55)
  static const double handW = 54;
  static const double floorW = 44;
  static const double oppW = 22;
  static const double capW = 19;

  /// 상대가 먹은 패는 작게 내가 먹은 패는 크게 보여 준다.
  static const CapStyle oppCap = CapStyle(
    w: 19, step: 21, rowH: 33, piX: 72, piStep: 21, width: 198);
  static const CapStyle myCap = CapStyle(
    w: 25, step: 27, rowH: 40, piX: 88, piStep: 23, width: 206);

  static const Offset deck = Offset(218, 46);
  static const Offset playSpot = Offset(425, 150);
  static const Offset oppBoard = Offset(6, 28);
  static const Offset myBoard = Offset(692, 28);

  static const int floorCols = 8;

  static double h(double w) => w * 1.55;

  /// 내 손패 i번째 위치 (n장을 가운데 정렬)
  static Offset handPos(int i, int n) {
    const step = 58.0;
    final total = (n - 1) * step + handW;
    return Offset(450 - total / 2 + i * step, 320);
  }

  /// 상대 손패 뒷면 i번째 위치
  static Offset oppBackPos(int i, int n) {
    const step = 26.0;
    final total = (n - 1) * step + oppW;
    return Offset(450 - total / 2 + i * step, 4);
  }

  /// 바닥 칸 번호의 위치
  static Offset floorSlot(int slot) {
    final c = slot % floorCols;
    final r = slot ~/ floorCols;
    return Offset(275 + c * 52, 46 + r * 76);
  }

  static double _baseY(Offset o, CapStyle st) => o.dy + 2 * st.rowH + 6;

  /// 먹은 패 배치. 겹치지 않게 줄을 나눈다.
  /// 광 한 줄, 열끗 한 줄, 띠는 홍단 청단 초단 기타 순으로 줄을 바꾸고,
  /// 피는 피 값의 합이 5가 될 때마다 줄을 바꾼다(쌍피는 2로 센다).
  static Map<int, Offset> captured(List<int> ids, Offset o,
      {CapStyle style = oppCap}) {
    final out = <int, Offset>{};
    final gwang = <int>[];
    final yeol = <int>[];
    final pi = <int>[];
    final hong = <int>[];
    final cheong = <int>[];
    final cho = <int>[];
    final other = <int>[];

    for (final id in ids) {
      final c = allCards[id];
      switch (c.kind) {
        case Kind.gwang:
          gwang.add(id);
          break;
        case Kind.yeol:
          yeol.add(id);
          break;
        case Kind.pi:
          pi.add(id);
          break;
        case Kind.tti:
          switch (c.group) {
            case TtiGroup.hong:
              hong.add(id);
              break;
            case TtiGroup.cheong:
              cheong.add(id);
              break;
            case TtiGroup.cho:
              cho.add(id);
              break;
            case TtiGroup.none:
              other.add(id);
              break;
          }
          break;
      }
    }

    // 칸이 모자라면 간격을 줄여서 살짝 겹치게 한다
    void row(List<int> list, double x, double y, double maxW) {
      list.sort();
      var step = style.step;
      if (list.length > 1) {
        final fit = (maxW - style.w) / (list.length - 1);
        if (fit < step) step = fit;
      }
      for (var i = 0; i < list.length; i++) {
        out[list[i]] = Offset(x + i * step, y);
      }
    }

    final rh = style.rowH;
    final baseY = _baseY(o, style);
    final ttiW = style.piX - 4;
    row(gwang, o.dx, o.dy, style.width);
    row(yeol, o.dx, o.dy + rh, style.width);
    row(hong, o.dx, baseY, ttiW);
    row(cheong, o.dx, baseY + rh, ttiW);
    row(cho, o.dx, baseY + 2 * rh, ttiW);
    row(other, o.dx, baseY + 3 * rh, ttiW);

    pi.sort((a, b) {
      final d = allCards[b].piValue - allCards[a].piValue;
      return d != 0 ? d : a - b;
    });
    var r = 0;
    var col = 0;
    var sum = 0;
    for (final id in pi) {
      final v = allCards[id].piValue;
      if (sum + v > 5) {
        r++;
        col = 0;
        sum = 0;
      }
      out[id] = Offset(o.dx + style.piX + col * style.piStep, baseY + r * rh);
      sum += v;
      col++;
    }
    return out;
  }

  /// 먹은 패 칸의 배경
  static List<BoardSlot> slots(Offset o, {CapStyle style = oppCap}) {
    final rh = style.rowH;
    final baseY = _baseY(o, style);
    final ch = style.w * 1.55 + 4;
    final ttiW = style.piX - 4;
    return [
      BoardSlot(o.dx - 2, o.dy - 2, style.width, ch, '광', 'gwang'),
      BoardSlot(o.dx - 2, o.dy + rh - 2, style.width, ch, '열끗', 'yeol'),
      BoardSlot(o.dx - 2, baseY - 2, ttiW, ch, '홍단', 'hong'),
      BoardSlot(o.dx - 2, baseY + rh - 2, ttiW, ch, '청단', 'cheong'),
      BoardSlot(o.dx - 2, baseY + 2 * rh - 2, ttiW, ch, '초단', 'cho'),
      BoardSlot(o.dx - 2, baseY + 3 * rh - 2, ttiW, ch, '띠', 'tti'),
      BoardSlot(o.dx + style.piX - 2, baseY - 2, style.width - style.piX - 2,
          5 * rh - 3, '피', 'pi'),
    ];
  }
}
