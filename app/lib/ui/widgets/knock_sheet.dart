import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/models.dart';
import '../../state/app_view_model.dart';
import 'common.dart';

Future<void> showKnockSheet(
  BuildContext context,
  UserSummary user, {
  bool quiet = false,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => KnockSheet(user: user, quiet: quiet),
);

class KnockSheet extends StatefulWidget {
  const KnockSheet({super.key, required this.user, required this.quiet});

  final UserSummary user;
  final bool quiet;

  @override
  State<KnockSheet> createState() => _KnockSheetState();
}

class _KnockSheetState extends State<KnockSheet> {
  KnockTemplate _template = KnockTemplate.game;
  bool _sending = false;

  Future<void> _send() async {
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppViewModel>().sendKnock(widget.user.id, _template);
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(const SnackBar(content: Text('ノックしました')));
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('ノックできませんでした。もう一度お試しください。')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      8,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 20,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            InitialAvatar(name: widget.user.displayName, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${widget.user.displayName}にノック',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text('誘い方', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: KnockTemplate.values
              .map(
                (template) => ChoiceChip(
                  label: Text(template.text),
                  selected: _template == template,
                  onSelected: (_) => setState(() => _template = template),
                ),
              )
              .toList(),
        ),
        if (widget.quiet) ...[
          const SizedBox(height: 12),
          Text(
            '「スルーしてOK」が付きます',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _sending ? null : _send,
          child: Text(_sending ? '送信中…' : 'ノックする'),
        ),
      ],
    ),
  );
}
