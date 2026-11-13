import 'package:flutter_test/flutter_test.dart';
import 'package:matgo/game/wallet.dart';

void main() {
  recordTests();
  test('시작 5000원 정산은 판마다 한 번만', () {
    final w = Wallet.forTest();
    expect(w.money, 5000);
    expect(w.settle(11, 700), true);
    expect(w.money, 5700);
    expect(w.settle(11, 700), false); // 같은 판 재수신
    expect(w.money, 5700);
    expect(w.settle(12, -1200), true);
    expect(w.money, 4500);
    expect(w.settle(13, 0), true); // 나가리
    expect(w.money, 4500);
  });

  test('대출은 5000원 빚은 6000원', () {
    final w = Wallet.forTest();
    w.borrow();
    expect(w.money, 10000);
    expect(w.debt, 6000);
    expect(w.repay(), 6000);
    expect(w.money, 4000);
    expect(w.debt, 0);
  });

  test('빚 1만원 이상이면 리셋하고 전재산도 5000원', () {
    final w = Wallet.forTest();
    w.borrow();
    expect(w.resetDebt(), false);
    w.borrow();
    expect(w.debt, 12000);
    expect(w.canResetDebt, true);
    expect(w.resetDebt(), true);
    expect(w.debt, 0);
    expect(w.money, 5000);
  });

  test('마이너스 잔액과 원 표기', () {
    final w = Wallet.forTest();
    w.settle(1, -8000);
    expect(w.money, -3000);
    expect(won(-3000), '-3,000원');
    expect(won(1234567), '1,234,567원');
    expect(w.repay(), 0);
  });
}

void recordTests() {
  test('전적과 순수 손익은 빚 리셋과 무관', () {
    final w = Wallet.forTest();
    w.settle(1, 1200, result: 1, myScore: 12, oppScore: 3, points: 12);
    w.settle(2, -500, result: -1, myScore: 2, oppScore: 5, points: 5);
    w.settle(3, 0, result: 0);
    w.borrow();
    w.borrow();
    w.resetDebt();
    expect(w.records.length, 3);
    expect(w.wins, 1);
    expect(w.losses, 1);
    expect(w.draws, 1);
    expect(w.pureProfit, 700);
    expect(w.bestScore, 12);
    expect(w.money, 5000);
  });

  test('같은 판은 기록도 한 번만', () {
    final w = Wallet.forTest();
    w.settle(9, 300, result: 1, points: 3);
    w.settle(9, 300, result: 1, points: 3);
    expect(w.records.length, 1);
  });
}
