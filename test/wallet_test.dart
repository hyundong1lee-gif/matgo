import 'package:flutter_test/flutter_test.dart';
import 'package:matgo/game/wallet.dart';

void main() {
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
