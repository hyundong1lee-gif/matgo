import 'package:flutter_test/flutter_test.dart';
import 'package:matgo/game/wallet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('시작 50억 정산은 판마다 한 번만', () {
    final w = Wallet.forTest();
    expect(w.money, 5000000000);
    expect(w.settle(11, 700000000), true);
    expect(w.money, 5700000000);
    expect(w.settle(11, 700000000), false); // 같은 판 재수신
    expect(w.money, 5700000000);
    expect(w.settle(12, -1200000000), true);
    expect(w.money, 4500000000);
    expect(w.settle(13, 0), true); // 나가리
    expect(w.money, 4500000000);
  });

  test('대출은 50억 빚은 60억', () {
    final w = Wallet.forTest();
    w.borrow();
    expect(w.money, 10000000000);
    expect(w.debt, 6000000000);
    expect(w.repay(), 6000000000);
    expect(w.money, 4000000000);
    expect(w.debt, 0);
  });

  test('빚 100억 이상이면 리셋하고 전재산도 50억', () {
    final w = Wallet.forTest();
    w.borrow();
    expect(w.resetDebt(), false);
    w.borrow();
    expect(w.debt, 12000000000);
    expect(w.canResetDebt, true);
    expect(w.resetDebt(), true);
    expect(w.debt, 0);
    expect(w.money, 5000000000);
  });

  test('마이너스 잔액과 원 표기', () {
    final w = Wallet.forTest();
    w.settle(1, -8000000000);
    expect(w.money, -3000000000);
    expect(won(-3000000000), '-30억원');
    expect(won(5000000000), '50억원');
    expect(won(120003500), '1억 3,500원');
    expect(won(123450000), '1억 2,345만원');
    expect(won(3500), '3,500원');
    expect(won(0), '0원');
    expect(won(1234567890000), '12,345억 6,789만원');
    expect(w.repay(), 0);
  });

  test('전적과 순수 손익은 빚 리셋과 무관', () {
    final w = Wallet.forTest();
    w.settle(1, 1200000000, result: 1, myScore: 12, oppScore: 3, points: 12);
    w.settle(2, -500000000, result: -1, myScore: 2, oppScore: 5, points: 5);
    w.settle(3, 0, result: 0);
    w.borrow();
    w.borrow();
    w.resetDebt();
    expect(w.records.length, 3);
    expect(w.wins, 1);
    expect(w.losses, 1);
    expect(w.draws, 1);
    expect(w.pureProfit, 700000000);
    expect(w.bestScore, 12);
    expect(w.money, 5000000000);
  });

  test('같은 판은 기록도 한 번만', () {
    final w = Wallet.forTest();
    w.settle(9, 300000000, result: 1, points: 3);
    w.settle(9, 300000000, result: 1, points: 3);
    expect(w.records.length, 1);
  });

  test('예전 단위로 저장된 돈은 100만 배로 환산', () async {
    SharedPreferences.setMockInitialValues({
      'money': 5700,
      'debt': 6000,
      'records': [
        '{"id":5,"r":1,"m":9,"o":2,"p":7,"d":700}',
      ],
    });
    final w = Wallet.forTest();
    await w.load();
    expect(w.money, 5700000000);
    expect(w.debt, 6000000000);
    expect(w.records.single.delta, 700000000);
    expect(w.records.single.points, 7);
    // 다시 불러와도 두 번 곱하지 않는다
    final w2 = Wallet.forTest();
    await w2.load();
    expect(w2.money, 5700000000);
  });

  test('저장된 게 없으면 50억으로 시작', () async {
    SharedPreferences.setMockInitialValues({});
    final w = Wallet.forTest();
    await w.load();
    expect(w.money, 5000000000);
    expect(w.records, isEmpty);
  });
}
