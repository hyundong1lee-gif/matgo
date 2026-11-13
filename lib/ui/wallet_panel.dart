import 'package:flutter/material.dart';

import '../game/wallet.dart';
import 'stats_page.dart';

/// 내 돈과 빚을 보여 주고 대출 / 갚기 / 빚 리셋을 하는 창
Future<void> showWallet(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const Dialog(child: WalletPanel()),
  );
}

class WalletPanel extends StatelessWidget {
  const WalletPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final w = Wallet.i;
    return ListenableBuilder(
      listenable: w,
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '내 지갑',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  '잔액 ${won(w.money)}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: w.money < 0 ? Colors.red : Colors.black87,
                  ),
                ),
                Text(
                  '빚 ${won(w.debt)}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: w.debt > 0 ? Colors.red : Colors.black54,
                  ),
                ),
                Text(
                  '게임으로 번 돈 ${w.pureProfit > 0 ? '+' : ''}${won(w.pureProfit)}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: w.pureProfit < 0 ? Colors.red : Colors.green.shade700,
                  ),
                ),
                const Text(
                  '(대출·빚 리셋 제외)',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10, color: Colors.black54),
                ),
                const SizedBox(height: 4),
                Text(
                  '대출은 한 번에 ${won(kLoanUnit)} 갚을 땐 1.2배(${won(kLoanUnit * 6 ~/ 5)})\n빚이 ${won(kDebtResetAt)} 이상이면 빚 리셋 가능\n(빚 0원 + 전재산 ${won(kStartMoney)}으로 초기화)',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Colors.black54),
                ),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    FilledButton(
                      onPressed: w.borrow,
                      child: Text('${won(kLoanUnit)} 대출'),
                    ),
                    FilledButton.tonal(
                      onPressed: (w.debt > 0 && w.money > 0) ? w.repay : null,
                      child: const Text('빚 갚기'),
                    ),
                    if (w.canResetDebt)
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.red,
                        ),
                        onPressed: () => _confirmReset(context, w),
                        child: const Text('빚 리셋'),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const StatsPage(),
                        ),
                      ),
                      child: const Text('전적 보기'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('닫기'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmReset(BuildContext context, Wallet w) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('빚 리셋'),
        content: Text('빚이 0원이 되지만 전재산도 ${won(kStartMoney)}으로 바뀌어. 진행할까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('리셋'),
          ),
        ],
      ),
    );
    if (ok == true) w.resetDebt();
  }
}
