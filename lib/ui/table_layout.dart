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

  static const Offset deck = Offset(218, 46);
  static const Offset playSpot = Offset(425, 150);
  static const Offset oppBoard = Offset(6, 28);
  static const Offset myBoard = Offset(694, 28);

  static const int floorCols = 8;
  static const double _step = 21; // 먹은 패 가로 간격
  static const double _rowH = 33; // 먹은 패 줄 간격

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

  static double _baseY(Offset o) => o.dy + 2 * _rowH + 6;

  /// 먹은 패 배치. 겹치지 않게 줄을 나눈다.
  /// 광 한 줄, 열끗 한 줄, 띠는 홍단 청단 초단 기타 순으로 줄을 바꾸고,
  /// 피는 피 값의 합이 5가 될 때마다 줄을 바꾼다(쌍피는 2로 센다).
  static Map<int, Offset> captured(List<int> ids, Offset o) {
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

    void row(List<int> list, double x, double y) {
      list.sort();
      for (var i = 0; i < list.length; i++) {
        out[list[i]] = Offset(x + i * _step, y);
      }
    }

    final baseY = _baseY(o);
    row(gwang, o.dx, o.dy);
    row(yeol, o.dx, o.dy + _rowH);
    row(hong, o.dx, baseY);
    row(cheong, o.dx, baseY + _rowH);
    row(cho, o.dx, baseY + 2 * _rowH);
    row(other, o.dx, baseY + 3 * _rowH);

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
      out[id] = Offset(o.dx + 72 + col * _step, baseY + r * _rowH);
      sum += v;
      col++;
    }
    return out;
  }

  /// 먹은 패 칸의 배경
  static List<BoardSlot> slots(Offset o) {
    final baseY = _baseY(o);
    final ch = capW * 1.55 + 4;
    return [
      BoardSlot(o.dx - 2, o.dy - 2, 198, ch, '광', 'gwang'),
      BoardSlot(o.dx - 2, o.dy + _rowH - 2, 198, ch, '열끗', 'yeol'),
      BoardSlot(o.dx - 2, baseY - 2, 68, ch, '홍단', 'hong'),
      BoardSlot(o.dx - 2, baseY + _rowH - 2, 68, ch, '청단', 'cheong'),
      BoardSlot(o.dx - 2, baseY + 2 * _rowH - 2, 68, ch, '초단', 'cho'),
      BoardSlot(o.dx - 2, baseY + 3 * _rowH - 2, 68, ch, '띠', 'tti'),
      BoardSlot(o.dx + 70, baseY - 2, 110, 6 * _rowH - 3, '피', 'pi'),
    ];
  }
}
