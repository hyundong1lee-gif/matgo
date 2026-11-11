enum Kind { gwang, yeol, tti, pi }

enum TtiGroup { none, hong, cheong, cho }

const List<String> monthNames = [
  '송학',
  '매조',
  '벚꽃',
  '흑싸리',
  '난초',
  '모란',
  '홍싸리',
  '공산',
  '국화',
  '단풍',
  '오동',
  '비',
];

class CardInfo {
  final int id;
  final int month; // 1..12
  final Kind kind;
  final TtiGroup group;
  final bool godori;
  final bool bigwang;
  final bool ssangpi;

  const CardInfo(
    this.id,
    this.month,
    this.kind, {
    this.group = TtiGroup.none,
    this.godori = false,
    this.bigwang = false,
    this.ssangpi = false,
  });

  /// 피로 셀 때의 값. 쌍피는 2장으로 센다.
  int get piValue => kind == Kind.pi ? (ssangpi ? 2 : 1) : 0;
}

/// 카드 id = (월 - 1) * 4 + 번호(0~3)
final List<CardInfo> allCards = _buildCards();

List<CardInfo> _buildCards() {
  CardInfo c(
    int m,
    int i,
    Kind k, {
    TtiGroup g = TtiGroup.none,
    bool godori = false,
    bool big = false,
    bool ss = false,
  }) =>
      CardInfo((m - 1) * 4 + i, m, k,
          group: g, godori: godori, bigwang: big, ssangpi: ss);

  return [
    c(1, 0, Kind.gwang),
    c(1, 1, Kind.tti, g: TtiGroup.hong),
    c(1, 2, Kind.pi),
    c(1, 3, Kind.pi),
    c(2, 0, Kind.yeol, godori: true),
    c(2, 1, Kind.tti, g: TtiGroup.hong),
    c(2, 2, Kind.pi),
    c(2, 3, Kind.pi),
    c(3, 0, Kind.gwang),
    c(3, 1, Kind.tti, g: TtiGroup.hong),
    c(3, 2, Kind.pi),
    c(3, 3, Kind.pi),
    c(4, 0, Kind.yeol, godori: true),
    c(4, 1, Kind.tti, g: TtiGroup.cho),
    c(4, 2, Kind.pi),
    c(4, 3, Kind.pi),
    c(5, 0, Kind.yeol),
    c(5, 1, Kind.tti, g: TtiGroup.cho),
    c(5, 2, Kind.pi),
    c(5, 3, Kind.pi),
    c(6, 0, Kind.yeol),
    c(6, 1, Kind.tti, g: TtiGroup.cheong),
    c(6, 2, Kind.pi),
    c(6, 3, Kind.pi),
    c(7, 0, Kind.yeol),
    c(7, 1, Kind.tti, g: TtiGroup.cho),
    c(7, 2, Kind.pi),
    c(7, 3, Kind.pi),
    c(8, 0, Kind.gwang),
    c(8, 1, Kind.yeol, godori: true),
    c(8, 2, Kind.pi),
    c(8, 3, Kind.pi),
    c(9, 0, Kind.yeol),
    c(9, 1, Kind.tti, g: TtiGroup.cheong),
    c(9, 2, Kind.pi),
    c(9, 3, Kind.pi),
    c(10, 0, Kind.yeol),
    c(10, 1, Kind.tti, g: TtiGroup.cheong),
    c(10, 2, Kind.pi),
    c(10, 3, Kind.pi),
    c(11, 0, Kind.gwang),
    c(11, 1, Kind.pi, ss: true),
    c(11, 2, Kind.pi),
    c(11, 3, Kind.pi),
    c(12, 0, Kind.gwang, big: true),
    c(12, 1, Kind.yeol),
    c(12, 2, Kind.tti),
    c(12, 3, Kind.pi, ss: true),
  ];
}
