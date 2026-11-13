import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const int kStartMoney = 5000000000; // 50억
const int kLoanUnit = 5000000000; // 한 번에 50억
const int kDebtResetAt = 10000000000; // 100억
const int kWonPerPoint = 100000000; // 1점당 1억

/// 예전 단위(5,000원 시작)에서 지금 단위로 옮길 때 곱하는 값
const int kOldUnitScale = 1000000;

String _commas(int a) {
  final s = a.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

/// 50억원 / 1억 2,000만원 / 3,500원 처럼 읽기 쉽게 적는다.
String won(int v) {
  final neg = v < 0;
  final a = v.abs();
  final sign = neg ? '-' : '';
  if (a < 10000) return '$sign${_commas(a)}원';
  final eok = a ~/ 100000000;
  final man = (a % 100000000) ~/ 10000;
  final rest = a % 10000;
  final parts = <String>[];
  if (eok > 0) parts.add('${_commas(eok)}억');
  if (man > 0) parts.add('${_commas(man)}만');
  if (rest > 0) parts.add(_commas(rest));
  return '$sign${parts.join(' ')}원';
}

/// 한 판의 기록 (내 시점)
class GameRecord {
  final int id; // 판 시작 시각(ms)
  final int result; // 1 승 -1 패 0 나가리
  final int myScore; // 판이 끝났을 때 내 점수
  final int oppScore;
  final int points; // 승부 점수(배수 적용 후) 나가리는 0
  final int delta; // 이 판으로 늘고 줄어든 돈

  const GameRecord({
    required this.id,
    required this.result,
    required this.myScore,
    required this.oppScore,
    required this.points,
    required this.delta,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'r': result,
        'm': myScore,
        'o': oppScore,
        'p': points,
        'd': delta,
      };

  factory GameRecord.fromJson(Map<String, dynamic> j) => GameRecord(
        id: j['id'] as int,
        result: j['r'] as int,
        myScore: j['m'] as int,
        oppScore: j['o'] as int,
        points: j['p'] as int,
        delta: j['d'] as int,
      );
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

  /// 지금까지 한 모든 판 (오래된 순)
  final List<GameRecord> records = [];

  int get wins => records.where((r) => r.result > 0).length;
  int get losses => records.where((r) => r.result < 0).length;
  int get draws => records.where((r) => r.result == 0).length;

  /// 대출 빚 리셋과 상관없이 게임 결과만 합친 손익
  int get pureProfit => records.fold(0, (a, r) => a + r.delta);

  int get bestScore =>
      records.fold(0, (a, r) => r.result > 0 && r.points > a ? r.points : a);

  SharedPreferences? _p;

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    final p = _p!;
    money = p.getInt('money') ?? kStartMoney;
    debt = p.getInt('debt') ?? 0;
    _lastGameId = p.getInt('lastGameId') ?? 0;
    records.clear();
    for (final e in p.getStringList('records') ?? const <String>[]) {
      try {
        records.add(GameRecord.fromJson(jsonDecode(e) as Map<String, dynamic>));
      } catch (_) {}
    }
    // 예전 단위로 저장된 돈 빚 전적은 100만 배로 바꿔 준다 (한 번만)
    if (p.getInt('unit') == null) {
      if (p.containsKey('money')) {
        money *= kOldUnitScale;
        debt *= kOldUnitScale;
        for (var i = 0; i < records.length; i++) {
          final r = records[i];
          records[i] = GameRecord(
            id: r.id,
            result: r.result,
            myScore: r.myScore,
            oppScore: r.oppScore,
            points: r.points,
            delta: r.delta * kOldUnitScale,
          );
        }
      }
      await p.setInt('unit', 2);
      await _save();
    }
    notifyListeners();
  }

  Future<void> _save() async {
    final p = _p;
    if (p == null) return;
    await p.setInt('money', money);
    await p.setInt('debt', debt);
    await p.setInt('lastGameId', _lastGameId);
    await p.setStringList(
      'records',
      records.map((r) => jsonEncode(r.toJson())).toList(),
    );
  }

  /// 판이 끝났을 때 한 번만 정산한다. 같은 판을 다시 받아도 무시한다.
  bool settle(
    int gameId,
    int delta, {
    int result = 0,
    int myScore = 0,
    int oppScore = 0,
    int points = 0,
  }) {
    if (gameId == 0 || gameId == _lastGameId) return false;
    _lastGameId = gameId;
    money += delta;
    records.add(GameRecord(
      id: gameId,
      result: result,
      myScore: myScore,
      oppScore: oppScore,
      points: points,
      delta: delta,
    ));
    lastDelta = delta;
    lastDeltaGameId = gameId;
    _save();
    notifyListeners();
    return true;
  }

  /// 대출은 한 번에 5000원 빚은 1.2배로 늘어난다.
  void borrow() {
    money += kLoanUnit;
    debt += kLoanUnit * 6 ~/ 5; // 1.2배
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
