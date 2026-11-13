import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const int kStartMoney = 5000;
const int kLoanUnit = 5000;
const double kLoanRate = 1.2;
const int kDebtResetAt = 10000;
const int kWonPerPoint = 100;

String won(int v) {
  final neg = v < 0;
  final s = v.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return '${neg ? '-' : ''}$b원';
}

/// 이 폰에 저장되는 내 돈. 앱을 껐다 켜도 유지된다.
class Wallet extends ChangeNotifier {
  Wallet._();
  static final Wallet i = Wallet._();

  /// 테스트용 새 지갑
  @visibleForTesting
  Wallet.forTest();

  int money = kStartMoney;
  int debt = 0;
  int _lastGameId = 0;

  /// 가장 최근에 정산한 판의 증감액 (결과 화면 표시용)
  int lastDelta = 0;
  int lastDeltaGameId = 0;

  SharedPreferences? _p;

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    money = _p!.getInt('money') ?? kStartMoney;
    debt = _p!.getInt('debt') ?? 0;
    _lastGameId = _p!.getInt('lastGameId') ?? 0;
    notifyListeners();
  }

  Future<void> _save() async {
    final p = _p;
    if (p == null) return;
    await p.setInt('money', money);
    await p.setInt('debt', debt);
    await p.setInt('lastGameId', _lastGameId);
  }

  /// 판이 끝났을 때 한 번만 정산한다. 같은 판을 다시 받아도 무시한다.
  bool settle(int gameId, int delta) {
    if (gameId == 0 || gameId == _lastGameId) return false;
    _lastGameId = gameId;
    money += delta;
    lastDelta = delta;
    lastDeltaGameId = gameId;
    _save();
    notifyListeners();
    return true;
  }

  /// 대출은 한 번에 5000원 빚은 1.2배로 늘어난다.
  void borrow() {
    money += kLoanUnit;
    debt += (kLoanUnit * kLoanRate).round();
    _save();
    notifyListeners();
  }

  /// 가진 돈 안에서 빚을 갚는다.
  int repay() {
    final pay = money <= 0 ? 0 : (money < debt ? money : debt);
    money -= pay;
    debt -= pay;
    _save();
    notifyListeners();
    return pay;
  }

  bool get canResetDebt => debt >= kDebtResetAt;

  /// 빚이 1만원 이상이면 빚을 0으로 만들고 전재산도 5000원으로 되돌린다.
  bool resetDebt() {
    if (!canResetDebt) return false;
    debt = 0;
    money = kStartMoney;
    _save();
    notifyListeners();
    return true;
  }
}
