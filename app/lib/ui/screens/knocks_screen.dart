import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/models.dart';
import '../../state/app_view_model.dart';
import '../widgets/common.dart';

class KnocksScreen extends StatefulWidget {
  const KnocksScreen({super.key});

  @override
  State<KnocksScreen> createState() => _KnocksScreenState();
}

class _KnocksScreenState extends State<KnocksScreen> {
  bool _showSent = false;
  final Set<String> _markingSeen = {};

  void _markUnseenAfterDisplay(List<Knock> knocks, AppViewModel viewModel) {
    final unseen = knocks
        .where(
          (knock) =>
              knock.status != KnockStatus.pending &&
              knock.resultSeenAt == null &&
              _markingSeen.add(knock.id),
        )
        .map((knock) => knock.id)
        .toList();
    if (unseen.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_showSent) {
        _markingSeen.removeAll(unseen);
        return;
      }
      for (final id in unseen) {
        unawaited(
          viewModel.markKnockResultSeen(id).catchError((Object _) {
            _markingSeen.remove(id);
          }),
        );
      }
    });
  }

  Future<void> _respond(String id, KnockStatus response) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppViewModel>().respondToKnock(id, response);
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('返事を送れませんでした。もう一度お試しください。')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<AppViewModel>();
    if (_showSent) _markUnseenAfterDisplay(viewModel.sent, viewModel);
    final knocks = _showSent ? viewModel.sent : viewModel.inbox;
    return PageContent(
      title: 'ノック',
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('受信')),
            ButtonSegment(value: true, label: Text('送信')),
          ],
          selected: {_showSent},
          onSelectionChanged: (selection) =>
              setState(() => _showSent = selection.first),
        ),
        const SizedBox(height: 18),
        if (knocks.isEmpty)
          EmptyState(
            message: _showSent ? '送ったノックはありません。' : '届いたノックはありません。',
            icon: Icons.notifications_none_rounded,
          ),
        for (final knock in knocks) ...[
          _KnockCard(
            knock: knock,
            sent: _showSent,
            onRespond: (status) => _respond(knock.id, status),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _KnockCard extends StatelessWidget {
  const _KnockCard({
    required this.knock,
    required this.sent,
    required this.onRespond,
  });

  final Knock knock;
  final bool sent;
  final ValueChanged<KnockStatus> onRespond;

  @override
  Widget build(BuildContext context) {
    final person = sent
        ? knock.recipient ??
              knock.sender ??
              const UserSummary(id: '', displayName: '友だち')
        : knock.sender ??
              knock.recipient ??
              const UserSummary(id: '', displayName: '友だち');
    final hasUnseenResult =
        sent &&
        knock.status != KnockStatus.pending &&
        knock.resultSeenAt == null;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: hasUnseenResult
            ? BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 1.5,
              )
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                InitialAvatar(name: person.displayName, size: 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        person.displayName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(knock.template.text),
                    ],
                  ),
                ),
                if (hasUnseenResult)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text('新着'),
                  )
                else
                  Text(
                    knock.status.label,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            if (!sent)
              if (knock.recipientNote case final note?) ...[
                const SizedBox(height: 10),
                Text(note),
              ],
            if (!sent && knock.status == KnockStatus.pending) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(
                    onPressed: () => onRespond(KnockStatus.accepted),
                    child: const Text('いいよ！'),
                  ),
                  OutlinedButton(
                    onPressed: () => onRespond(KnockStatus.later),
                    child: const Text('あとで'),
                  ),
                  OutlinedButton(
                    onPressed: () => onRespond(KnockStatus.passed),
                    child: const Text('今回はパス'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
