import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/models.dart';
import '../../state/app_view_model.dart';
import '../widgets/common.dart';
import '../widgets/declaration_sheet.dart';
import '../widgets/knock_sheet.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _endHima(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppViewModel>().endHima();
    } catch (_) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('解除できませんでした。もう一度お試しください。')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<AppViewModel>();
    final current = viewModel.myHima;
    final active =
        current != null && current.expiresAt.isAfter(DateTime.now().toUtc());
    return PageContent(
      title: 'ホーム',
      children: [
        if (current != null && active)
          _CurrentStatusCard(
            session: current,
            onExtend: () => showDeclarationSheet(context, current: current),
            onEnd: () => _endHima(context),
          )
        else
          _DeclareCard(onPressed: () => showDeclarationSheet(context)),
        const SizedBox(height: 28),
        SectionTitle('マッチ', trailing: Text('${viewModel.matches.length}')),
        if (viewModel.matches.isEmpty)
          const EmptyState(message: 'マッチはまだありません。'),
        for (final match in viewModel.matches) ...[
          _MatchCard(
            match: match,
            onKnock: () => showKnockSheet(context, match.otherUser),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _DeclareCard extends StatelessWidget {
  const _DeclareCard({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(24),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'いまの気分を共有しよう',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Theme.of(context).colorScheme.onPrimaryContainer,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: onPressed,
          icon: const Icon(Icons.waving_hand_rounded),
          label: const Text('今ヒマ！'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(58),
            textStyle: Theme.of(context).textTheme.titleLarge,
          ),
        ),
      ],
    ),
  );
}

class _CurrentStatusCard extends StatelessWidget {
  const _CurrentStatusCard({
    required this.session,
    required this.onExtend,
    required this.onEnd,
  });

  final HimaSession session;
  final VoidCallback onExtend;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) => Card(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(session.mood.emoji, style: const TextStyle(fontSize: 26)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ヒマ宣言中',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      '${session.mood.label} · ${session.activity.emoji} ${session.activity.label}',
                    ),
                  ],
                ),
              ),
              const Icon(Icons.circle, size: 11, color: Color(0xFF4A9A75)),
            ],
          ),
          if (session.note case final note? when note.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(note),
          ],
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(Icons.hourglass_bottom_rounded, size: 20),
                const SizedBox(width: 8),
                Text('残り時間', style: Theme.of(context).textTheme.bodyMedium),
                const Spacer(),
                _CountdownText(expiresAt: session.expiresAt),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onExtend,
                  child: const Text('延長'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextButton(onPressed: onEnd, child: const Text('やめる')),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _CountdownText extends StatefulWidget {
  const _CountdownText({required this.expiresAt});

  final DateTime expiresAt;

  @override
  State<_CountdownText> createState() => _CountdownTextState();
}

class _CountdownTextState extends State<_CountdownText> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seconds = widget.expiresAt
        .difference(DateTime.now().toUtc())
        .inSeconds;
    final remaining = seconds <= 0
        ? '0:00'
        : seconds >= 3600
        ? '${seconds ~/ 3600}:${((seconds % 3600) ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}'
        : '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    return Text(
      'あと $remaining',
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({required this.match, required this.onKnock});

  final MatchRecord match;
  final VoidCallback onKnock;

  @override
  Widget build(BuildContext context) => Card(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          InitialAvatar(name: match.otherUser.displayName),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  matchMessage(match.kind),
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(match.otherUser.displayName),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(onPressed: onKnock, child: const Text('ノックする')),
        ],
      ),
    ),
  );
}
