import 'package:flutter_test/flutter_test.dart';
import 'package:matgo/game/wallet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  snapshotTests();

  test('이름은 공백을 없애고 8글자까지 저장되며 사본으로 전달된다', () {
    final w = Wallet.forTest();
    w.setName('  이현동  ');
    expect(w.name, '이현동');
    w.setName('가나다라마바사아자차');
    expect(w.name, '가나다라마바사아');
    final back = WalletSnapshot.fromJson(w.snapshot().toJson());
    expect(back.name, '가나다라마바사아');
    // 이름이 없는 예전 사본도 읽힌다
    final old = WalletSnapshot.fromJson({'money': 1, 'debt': 0, 'records': []});
    expect(old.name, '');
  });
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
    expect(won(120003500), '1억 2,000만 3,500원');
    expect(won(100003500), '1억 3,500원');
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

void snapshotTests() {
  test('빚 리셋 횟수를 센다', () {
    final w = Wallet.forTest();
    expect(w.resetCount, 0);
    w.borrow();
    w.borrow();
    w.resetDebt();
    expect(w.resetCount, 1);
    w.borrow();
    expect(w.resetDebt(), false); // 빚 60억은 아직 리셋 불가
    expect(w.resetCount, 1);
    w.borrow();
    w.resetDebt();
    expect(w.resetCount, 2);
  });

  test('지갑 사본을 주고받을 수 있고 최근 판만 보낸다', () {
    final w = Wallet.forTest();
    for (var i = 1; i <= 200; i++) {
      w.settle(i, i.isEven ? 100000000 : -100000000,
          result: i.isEven ? 1 : -1, myScore: 5, oppScore: 2, points: 3);
    }
    w.borrow();
    final snap = w.snapshot();
    expect(snap.records.length, 150);
    expect(snap.records.first.id, 51);
    final back = WalletSnapshot.fromJson(snap.toJson());
    expect(back.money, w.money);
    expect(back.debt, w.debt);
    expect(back.resets, 0);
    expect(back.records.length, 150);
    expect(back.wins + back.losses, 150);
    expect(back.pureProfit, 0);
  });
}
