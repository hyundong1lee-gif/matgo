import 'cards.dart';
import 'config.dart';

class ScoreDetail {
  final int total;
  final int gwangCount;
  final int gwangScore;
  final int piValue;
  final int piScore;
  final List<String> lines;

  const ScoreDetail({
    required this.total,
    required this.gwangCount,
    required this.gwangScore,
    required this.piValue,
    required this.piScore,
    required this.lines,
  });
}

const Map<TtiGroup, String> _danNames = {
  TtiGroup.hong: '홍단',
  TtiGroup.cheong: '청단',
  TtiGroup.cho: '초단',
};

/// 먹은 패(카드 id 목록)로 점수를 계산한다. 고와 박은 포함하지 않는다.
ScoreDetail scoreOf(List<int> ids) {
  final cs = ids.map((i) => allCards[i]).toList();
  final lines = <String>[];
  var total = 0;

  // 광
  final gw = cs.where((c) => c.kind == Kind.gwang).toList();
  var gwangScore = 0;
  if (gw.length >= 5) {
    gwangScore = MatgoConfig.gwang5;
  } else if (gw.length == 4) {
    gwangScore = MatgoConfig.gwang4;
  } else if (gw.length == 3) {
    gwangScore = gw.any((c) => c.bigwang)
        ? MatgoConfig.gwang3WithBigwang
        : MatgoConfig.gwang3;
  }
  if (gwangScore > 0) {
    total += gwangScore;
    lines.add('광 ${gw.length}장 +$gwangScore');
  }

  // 고도리
  if (cs.where((c) => c.godori).length == 3) {
    total += MatgoConfig.godori;
    lines.add('고도리 +${MatgoConfig.godori}');
  }

  // 홍단 청단 초단
  for (final e in _danNames.entries) {
    final n = cs.where((c) => c.kind == Kind.tti && c.group == e.key).length;
    if (n == 3) {
      total += MatgoConfig.dan;
      lines.add('${e.value} +${MatgoConfig.dan}');
    }
  }

  // 열끗
  final yeol = cs.where((c) => c.kind == Kind.yeol).length;
  if (yeol >= MatgoConfig.yeolStart) {
    final s = 1 + yeol - MatgoConfig.yeolStart;
    total += s;
    lines.add('열끗 $yeol장 +$s');
  }

  // 띠
  final tti = cs.where((c) => c.kind == Kind.tti).length;
  if (tti >= MatgoConfig.ttiStart) {
    final s = 1 + tti - MatgoConfig.ttiStart;
    total += s;
    lines.add('띠 $tti장 +$s');
  }

  // 피 (쌍피는 2장)
  final piValue = cs.fold<int>(0, (a, c) => a + c.piValue);
  var piScore = 0;
  if (piValue >= MatgoConfig.piStart) {
    piScore = 1 + piValue - MatgoConfig.piStart;
    total += piScore;
    lines.add('피 $piValue장 +$piScore');
  }

  return ScoreDetail(
    total: total,
    gwangCount: gw.length,
    gwangScore: gwangScore,
    piValue: piValue,
    piScore: piScore,
    lines: lines,
  );
}
