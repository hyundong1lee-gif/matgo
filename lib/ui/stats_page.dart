import 'package:flutter/material.dart';

import '../game/wallet.dart';

String _sign(int v) => v > 0 ? '+${won(v)}' : won(v);

String _time(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  String t(int n) => n.toString().padLeft(2, '0');
  return '${d.month}/${d.day} ${t(d.hour)}:${t(d.minute)}';
}

/// 전적 화면: 승패 요약 + 순수 게임 손익 + 모든 판 기록
class StatsPage extends StatelessWidget {
  /// 기본은 내 전적. 상대 전적을 볼 때는 [source]와 [read]를 넘긴다.
  const StatsPage({super.key, this.title = '전적', this.source, this.read});

  final String title;
  final Listenable? source;
  final WalletSnapshot? Function()? read;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: source ?? Wallet.i,
          builder: (context, _) {
            final w = (read != null ? read!() : Wallet.i.snapshot(maxRecords: 100000));
            if (w == null) return const Center(child: Text('아직 정보를 못 받았어'));
            final total = w.records.length;
            final decided = w.wins + w.losses;
            final rate = decided == 0 ? '-' : '${(w.wins * 100 / decided).round()}%';
            final profit = w.pureProfit;
            final recent = w.records.reversed.toList();
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 18,
                    runSpacing: 6,
                    children: [
                      _stat('총 $total판', '${w.wins}승 ${w.losses}패 ${w.draws}무'),
                      _stat('승률', rate),
                      _stat('최고 점수', w.bestScore == 0 ? '-' : '${w.bestScore}점'),
                      _stat(
                        '게임으로 번 돈',
                        _sign(profit),
                        color: profit < 0 ? Colors.red : Colors.green.shade700,
                      ),
                      _stat('빚 리셋', '${w.resets}번'),
                    ],
                  ),
                ),
                const Text(
                  '게임으로 번 돈은 대출 빚과 빚 리셋을 빼고 판 결과만 합친 금액이야',
                  style: TextStyle(fontSize: 11, color: Colors.black54),
                ),
                const Divider(),
                Expanded(
                  child: recent.isEmpty
                      ? const Center(child: Text('아직 기록이 없어'))
                      : ListView.separated(
                          itemCount: recent.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final r = recent[i];
                            final label =
                                r.result > 0 ? '승' : (r.result < 0 ? '패' : '무');
                            final color = r.result > 0
                                ? Colors.green.shade700
                                : (r.result < 0 ? Colors.red : Colors.grey);
                            return ListTile(
                              dense: true,
                              leading: CircleAvatar(
                                radius: 14,
                                backgroundColor: color,
                                child: Text(
                                  label,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              title: Text(
                                r.result == 0
                                    ? '나가리'
                                    : '승부 ${r.points}점 (나 ${r.myScore} : ${r.oppScore}${r.oppScore2 >= 0 ? ' : ${r.oppScore2}' : ''})',
                              ),
                              subtitle: Text('${total - i}번째 판 · ${_time(r.id)}'),
                              trailing: Text(
                                _sign(r.delta),
                                style: TextStyle(
                                  color: color,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _stat(String title, String value, {Color? color}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: const TextStyle(fontSize: 11, color: Colors.black54)),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}
