import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/models.dart';
import '../../state/app_view_model.dart';

Future<void> showDeclarationSheet(
  BuildContext context, {
  HimaSession? current,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => DeclarationSheet(current: current),
);

class DeclarationSheet extends StatefulWidget {
  const DeclarationSheet({super.key, this.current});

  final HimaSession? current;

  @override
  State<DeclarationSheet> createState() => _DeclarationSheetState();
}

class _DeclarationSheetState extends State<DeclarationSheet> {
  static const _durations = [5, 15, 30, 60, 180];
  late Mood _mood;
  late Activity _activity;
  late int _duration;
  late final TextEditingController _noteController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _mood = widget.current?.mood ?? Mood.fire;
    _activity = widget.current?.activity ?? Activity.game;
    _duration = widget.current == null ? 15 : 30;
    _noteController = TextEditingController(text: widget.current?.note ?? '');
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  String _durationLabel(int minutes) => switch (minutes) {
    60 => '1時間',
    180 => '3時間',
    _ => '$minutes分',
  };

  Future<void> _save() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final isExtending = widget.current != null;
    final note = _noteController.text.trim();
    try {
      await context.read<AppViewModel>().declareHima(
        HimaDeclaration(
          mood: _mood,
          activity: _activity,
          note: note.isEmpty ? null : note,
          durationMin: _duration,
          source: DeclarationSource.manual,
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(content: Text(isExtending ? '時間を延長しました' : 'ヒマ宣言しました')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('保存できませんでした。もう一度お試しください。')),
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
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.current == null ? '今ヒマ！' : 'ヒマ時間を延長',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 20),
          Text('温度感', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: Mood.values
                .map(
                  (mood) => ChoiceChip(
                    label: Text('${mood.emoji} ${mood.label}'),
                    selected: _mood == mood,
                    onSelected: (_) => setState(() => _mood = mood),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 18),
          Text('やりたいこと', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: Activity.values
                .map(
                  (activity) => ChoiceChip(
                    label: Text('${activity.emoji} ${activity.label}'),
                    selected: _activity == activity,
                    onSelected: (_) => setState(() => _activity = activity),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 18),
          Text('時間', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _durations
                .map(
                  (duration) => ChoiceChip(
                    label: Text(_durationLabel(duration)),
                    selected: _duration == duration,
                    onSelected: (_) => setState(() => _duration = duration),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _noteController,
            maxLength: 50,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'ひとこと',
              hintText: 'ゲーム名など',
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(
              _saving
                  ? '保存中…'
                  : widget.current == null
                  ? '宣言する'
                  : '延長する',
            ),
          ),
        ],
      ),
    ),
  );
}
