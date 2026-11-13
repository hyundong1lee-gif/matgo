import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:matgo/game/cards.dart';
import 'package:matgo/game/matgo_game.dart';
import 'package:matgo/game/scoring.dart';
import 'package:matgo/game/view_state.dart';

int cid(int month, int idx) => (month - 1) * 4 + idx;

/// 손패를 내고 더미를 뒤집는 두 단계를 한 번에 진행한다.
void turn(MatgoGame g, int p, int card) {
  expect(g.playCard(p, card), true);
  if (g.phase == Phase.flipStock) {
    expect(g.flipStock(p), true);
  }
}

void main() {
  test('덱 구성: 광5 열끗9 띠10 피24 (피 값 합 26)', () {
    expect(allCards.length, 48);
    int n(Kind k) => allCards.where((c) => c.kind == k).length;
    expect(n(Kind.gwang), 5);
    expect(n(Kind.yeol), 9);
    expect(n(Kind.tti), 10);
    expect(n(Kind.pi), 24);
    expect(allCards.fold<int>(0, (a, c) => a + c.piValue), 26);
    for (var i = 0; i < 48; i++) {
      expect(allCards[i].id, i);
    }
  });

  test('기본 분배: 10 + 10 + 바닥 8 + 더미 20', () {
    final g = MatgoGame();
    expect(g.hands[0].length, 10);
    expect(g.hands[1].length, 10);
    expect(g.floor.length, 8);
    expect(g.stock.length, 20);
    final all = {...g.hands[0], ...g.hands[1], ...g.floor, ...g.stock};
    expect(all.length, 48);
  });

  group('점수', () {
    test('3광은 3점 비광이 섞이면 2점 4광은 4점', () {
      expect(scoreOf([cid(1, 0), cid(3, 0), cid(8, 0)]).total, 3);
      expect(scoreOf([cid(1, 0), cid(3, 0), cid(12, 0)]).total, 2);
      expect(scoreOf([cid(1, 0), cid(3, 0), cid(8, 0), cid(11, 0)]).total, 4);
    });
    test('홍단 고도리', () {
      expect(scoreOf([cid(1, 1), cid(2, 1), cid(3, 1)]).total, 3);
      expect(scoreOf([cid(2, 0), cid(4, 0), cid(8, 1)]).total, 5);
    });
    test('피 10장부터 1점 쌍피는 2장', () {
      final ten = [
        cid(1, 2), cid(1, 3), cid(2, 2), cid(2, 3), cid(3, 2),
        cid(3, 3), cid(4, 2), cid(4, 3), cid(5, 2), cid(5, 3),
      ];
      expect(scoreOf(ten).total, 1);
      expect(scoreOf([...ten, cid(11, 1)]).total, 3); // 쌍피 +2장
    });
  });

  group('한 턴', () {
    test('쪽', () {
      final g = MatgoGame.custom(
        hand0: [cid(1, 2), cid(5, 2)],
        hand1: [cid(6, 2), cid(7, 2)],
        floor: [cid(9, 2)],
        stock: [cid(10, 2), cid(1, 3)],
        captured1: [cid(2, 2), cid(3, 2)],
      );
      expect(g.playCard(0, cid(1, 2)), true);
      expect(g.phase, Phase.flipStock); // 더미를 뒤집기를 기다린다
      expect(g.captured[0], isEmpty);
      expect(g.flipStock(0), true);
      expect(g.captured[0].length, 3); // 쪽 2장 + 가져온 피 1장
      expect(g.captured[0].contains(cid(1, 2)), true);
      expect(g.captured[0].contains(cid(1, 3)), true);
      expect(g.captured[1].length, 1);
      expect(g.events.any((e) => e.code == 'jjok'), true);
      expect(g.turn, 1);
      expect(g.phase, Phase.playCard);
    });

    test('뻑 그리고 뻑 먹기', () {
      final g = MatgoGame.custom(
        hand0: [cid(1, 2), cid(6, 3)],
        hand1: [cid(1, 0), cid(7, 2)],
        floor: [cid(1, 3), cid(5, 2)],
        stock: [cid(10, 2), cid(1, 1)],
        captured0: const [],
        captured1: [cid(2, 2)],
      );
      turn(g, 0, cid(1, 2));
      expect(g.events.any((e) => e.code == 'ppeok'), true);
      expect(g.captured[0], isEmpty);
      expect(g.floor.where((c) => allCards[c].month == 1).length, 3);

      turn(g, 1, cid(1, 0));
      for (final c in [cid(1, 0), cid(1, 1), cid(1, 2), cid(1, 3)]) {
        expect(g.captured[1].contains(c), true);
      }
    });

    test('따닥', () {
      final g = MatgoGame.custom(
        hand0: [cid(1, 2), cid(6, 3)],
        hand1: [cid(7, 2), cid(9, 3)],
        floor: [cid(1, 3), cid(1, 1), cid(9, 2)],
        stock: [cid(10, 2), cid(1, 0)],
        captured1: [cid(2, 2)],
      );
      g.playCard(0, cid(1, 2));
      expect(g.phase, Phase.chooseFloorHand);
      expect(g.chooseFloor(0, cid(1, 3)), true);
      expect(g.phase, Phase.flipStock);
      expect(g.flipStock(0), true);
      expect(g.events.any((e) => e.code == 'ttadak'), true);
      expect(g.captured[0].length, 5); // 4장 + 가져온 피 1장
      expect(g.floor, [cid(9, 2)]);
    });

    test('싹쓸이', () {
      final g = MatgoGame.custom(
        hand0: [cid(1, 2), cid(6, 3)],
        hand1: [cid(7, 2), cid(9, 3)],
        floor: [cid(1, 3), cid(2, 2)],
        stock: [cid(7, 0), cid(2, 3)],
        captured1: [cid(5, 2)],
      );
      turn(g, 0, cid(1, 2));
      expect(g.floor, isEmpty);
      expect(g.events.any((e) => e.code == 'sweep'), true);
      expect(g.captured[0].length, 5);
    });

    test('잘못된 행동은 거절', () {
      final g = MatgoGame.custom(
        hand0: [cid(1, 2)],
        hand1: [cid(2, 2)],
        floor: [],
        stock: [cid(3, 2), cid(4, 2)],
      );
      expect(g.playCard(1, cid(2, 2)), false); // 내 차례가 아님
      expect(g.playCard(0, cid(2, 2)), false); // 내 패가 아님
      expect(g.goStop(0, true), false); // 고/스톱 단계가 아님
    });
  });

  group('고 스톱과 종료', () {
    MatgoGame threeGwang() => MatgoGame.custom(
          hand0: [cid(5, 2), cid(6, 3)],
          hand1: [cid(7, 2), cid(9, 2)],
          floor: [cid(10, 2)],
          stock: [cid(4, 2), cid(11, 2)],
          captured0: [cid(1, 0), cid(3, 0), cid(8, 0)],
        );

    test('3점이 되면 고/스톱 단계로 간다', () {
      final g = threeGwang();
      turn(g, 0, cid(5, 2));
      expect(g.phase, Phase.goStop);
      expect(g.turn, 0);
    });

    test('스톱: 3점 × 광박 2 = 6점', () {
      final g = threeGwang();
      turn(g, 0, cid(5, 2));
      g.goStop(0, false);
      expect(g.phase, Phase.ended);
      expect(g.result!.winner, 0);
      expect(g.result!.points, 6);
    });

    test('고: 상대 차례로 넘어가고 고 횟수가 늘어난다', () {
      final g = threeGwang();
      turn(g, 0, cid(5, 2));
      g.goStop(0, true);
      expect(g.goCount[0], 1);
      expect(g.turn, 1);
      expect(g.phase, Phase.playCard);
    });

    test('패가 모두 떨어지면 나가리', () {
      final g = MatgoGame.custom(
        hand0: [cid(1, 2)],
        hand1: [cid(2, 2)],
        floor: [],
        stock: [cid(4, 2), cid(3, 2)],
      );
      turn(g, 0, cid(1, 2));
      turn(g, 1, cid(2, 2));
      expect(g.phase, Phase.ended);
      expect(g.result!.winner, -1);
    });
  });

  group('폭탄과 흔들기', () {
    test('폭탄: 3장을 한꺼번에 내서 4장을 먹고 피를 가져오며 폭탄패 2장을 받는다', () {
      final g = MatgoGame.custom(
        hand0: [cid(1, 0), cid(1, 1), cid(1, 2), cid(6, 3), cid(7, 2)],
        hand1: [cid(8, 2), cid(9, 3), cid(10, 2), cid(11, 2), cid(12, 2)],
        floor: [cid(1, 3), cid(5, 2)],
        stock: [cid(3, 2), cid(4, 2), cid(2, 2)],
        captured1: [cid(2, 3)],
      );
      expect(g.playBomb(0, 1), true);
      expect(g.shakeCount[0], 1);
      expect(g.captured[0].length, 5); // 4장 + 가져온 피 1장
      expect(g.captured[1], isEmpty);
      expect(g.hands[0].where(isDummyId).length, 2);
      expect(g.hands[0].length, 4); // 5 - 3 + 2
      expect(g.events.any((e) => e.code == 'bomb'), true);
      expect(g.phase, Phase.flipStock);
      expect(g.flipStock(0), true);
      expect(g.turn, 1);
    });

    test('폭탄 조건이 아니면 거절', () {
      final g = MatgoGame.custom(
        hand0: [cid(1, 0), cid(1, 1), cid(6, 3)],
        hand1: [cid(8, 2)],
        floor: [cid(1, 3), cid(1, 2)],
        stock: [cid(3, 2)],
      );
      expect(g.playBomb(0, 1), false); // 손에 2장뿐
      expect(g.playBomb(0, 6), false);
    });

    test('폭탄패를 내면 더미만 뒤집는다', () {
      final g = MatgoGame.custom(
        hand0: [kDummyBase, cid(6, 3)],
        hand1: [cid(8, 2), cid(9, 2)],
        floor: [cid(5, 2)],
        stock: [cid(3, 2), cid(5, 3)],
      );
      expect(g.playCard(0, kDummyBase), true);
      expect(g.phase, Phase.flipStock);
      expect(g.flipStock(0), true);
      expect(g.captured[0].contains(cid(5, 3)), true);
      expect(g.captured[0].contains(cid(5, 2)), true);
    });

    test('흔들기: 손에 3장 바닥에 0장이면 점수 2배', () {
      final g = MatgoGame.custom(
        hand0: [cid(1, 0), cid(1, 1), cid(1, 2), cid(6, 3)],
        hand1: [cid(8, 2), cid(9, 3), cid(10, 2), cid(11, 2)],
        floor: [cid(5, 2)],
        stock: [cid(3, 2)],
      );
      expect(g.playCard(0, cid(1, 0), shake: true), true);
      expect(g.shakeCount[0], 1);
      expect(g.events.any((e) => e.code == 'shake'), true);
    });

    test('조건이 안 맞는 흔들기 요청은 그냥 낸 것으로 처리', () {
      final g = MatgoGame.custom(
        hand0: [cid(1, 0), cid(1, 1), cid(6, 3)],
        hand1: [cid(8, 2)],
        floor: [cid(5, 2)],
        stock: [cid(3, 2)],
      );
      expect(g.playCard(0, cid(1, 0), shake: true), true);
      expect(g.shakeCount[0], 0);
    });

    test('폭탄 후 3점 스톱: 점수 2배 적용', () {
      final g = MatgoGame.custom(
        hand0: [cid(5, 0), cid(5, 1), cid(5, 2), cid(6, 3)],
        hand1: [cid(8, 2), cid(9, 3), cid(10, 2), cid(11, 2)],
        floor: [cid(5, 3), cid(7, 2)],
        stock: [cid(3, 2), cid(4, 2)],
        captured0: [cid(1, 0), cid(3, 0), cid(8, 0)],
        captured1: [cid(2, 3), cid(2, 2)],
      );
      expect(g.playBomb(0, 5), true);
      expect(g.flipStock(0), true);
      expect(g.phase, Phase.goStop);
      g.goStop(0, false);
      expect(g.phase, Phase.ended);
      // 광 3점 + 5월 열끗 1장과 띠 1장(점수 없음) -> 3점, 광박 ×2, 폭탄 ×2 = 12
      expect(g.result!.points, 12);
    });
  });

  group('박', () {
    MatgoGame base({List<int>? cap1}) => MatgoGame.custom(
          hand0: [cid(5, 0), cid(5, 1), cid(5, 2), cid(6, 3)],
          hand1: [cid(8, 2), cid(9, 3), cid(10, 2), cid(11, 2)],
          floor: [cid(5, 3), cid(7, 2)],
          stock: [cid(3, 2), cid(4, 2)],
          captured0: [cid(1, 0), cid(3, 0), cid(8, 0)],
          captured1: cap1 ?? [cid(2, 3), cid(2, 2)],
        );

    test('진 쪽이 고를 불렀으면 고박 ×2', () {
      final g = base();
      g.goCount[1] = 1;
      expect(g.playBomb(0, 5), true);
      expect(g.flipStock(0), true);
      g.goStop(0, false);
      expect(g.result!.lines.any((l) => l.startsWith('고박')), true);
      // 12점에서 고박 ×2
      expect(g.result!.points, 24);
    });

    test('고를 안 불렀으면 고박 없음', () {
      final g = base();
      expect(g.playBomb(0, 5), true);
      expect(g.flipStock(0), true);
      g.goStop(0, false);
      expect(g.result!.lines.any((l) => l.startsWith('고박')), false);
      expect(g.result!.points, 12);
    });
  });

  group('전체 진행', () {
    test('무작위 판을 끝까지 돌려도 카드가 48장으로 유지된다', () {
      for (var n = 0; n < 200; n++) {
        final g = MatgoGame();
        var guard = 0;
        while (g.phase != Phase.ended && guard < 500) {
          guard++;
          final p = g.turn;
          switch (g.phase) {
            case Phase.playCard:
              final hand = g.hands[p];
              var done = false;
              for (final c in hand) {
                if (isDummyId(c)) continue;
                final m = allCards[c].month;
                final mine = hand
                    .where((x) => !isDummyId(x) && allCards[x].month == m)
                    .length;
                final fl = g.floor.where((x) => allCards[x].month == m).length;
                if (mine == 3 && fl == 1) {
                  done = g.playBomb(p, m);
                  break;
                }
              }
              if (!done) g.playCard(p, hand.first, shake: true);
              break;
            case Phase.chooseFloorHand:
            case Phase.chooseFloorStock:
              g.chooseFloor(p, g.ctx.options.first);
              break;
            case Phase.flipStock:
              g.flipStock(p);
              break;
            case Phase.goStop:
              g.goStop(p, n % 3 == 0);
              break;
            case Phase.ended:
              break;
          }
          // 손패를 내고 더미를 뒤집는 중간 단계가 아닐 때만 카드 수를 센다
          if (g.phase == Phase.playCard ||
              g.phase == Phase.goStop ||
              g.phase == Phase.ended) {
            final all = <int>[
              ...g.hands[0].where((c) => !isDummyId(c)),
              ...g.hands[1].where((c) => !isDummyId(c)),
              ...g.floor,
              ...g.stock,
              ...g.captured[0],
              ...g.captured[1],
            ];
            expect(all.length, 48);
            expect(all.toSet().length, 48);
          }
        }
        expect(guard < 500, true);
        expect(g.phase, Phase.ended);
      }
    });
  });

  group('숨은 정보', () {
    test('참가자 시점에는 방장의 패와 더미 내용이 없다', () {
      final g = MatgoGame();
      final v = ViewState.of(g, 1, 3);
      expect(v.hand, (List<int>.of(g.hands[1])..sort()));
      expect(v.oppHandCount, g.hands[0].length);
      expect(v.stockCount, g.stock.length);
      final jsonText = jsonEncode(v.toJson());
      for (final id in g.hands[0]) {
        // 방장 패가 captured/floor/hand 어디에도 없어야 한다
        expect(v.hand.contains(id), false);
        expect(v.floor.contains(id), false);
      }
      expect(jsonText.contains('stock"'), false);
    });

    test('JSON 왕복', () {
      final g = MatgoGame();
      final v = ViewState.of(g, 0, 7);
      final back = ViewState.fromJson(
          jsonDecode(jsonEncode(v.toJson())) as Map<String, dynamic>);
      expect(back.hand, v.hand);
      expect(back.floor, v.floor);
      expect(back.phase, v.phase);
      expect(back.seq, 7);
    });
  });
}
