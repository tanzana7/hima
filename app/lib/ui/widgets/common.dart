import 'package:flutter/material.dart';

import '../../data/models/models.dart';

class PageContent extends StatelessWidget {
  const PageContent({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => CustomScrollView(
    slivers: [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        sliver: SliverList.list(
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 20),
            ...children,
          ],
        ),
      ),
    ],
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

class InitialAvatar extends StatelessWidget {
  const InitialAvatar({super.key, required this.name, this.size = 48});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: size / 2,
    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
    foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
    child: Text(
      name.isEmpty ? '？' : String.fromCharCode(name.runes.first),
      style: TextStyle(fontSize: size * .38, fontWeight: FontWeight.w700),
    ),
  );
}

String remainingLabel(DateTime expiresAt) {
  final seconds = expiresAt.difference(DateTime.now().toUtc()).inSeconds;
  if (seconds <= 0) return '終了間近';
  final minutes = (seconds + 59) ~/ 60;
  if (minutes >= 60) return 'あと${minutes ~/ 60}時間${minutes % 60}分';
  return 'あと$minutes分';
}

String matchMessage(MatchKind kind) => switch (kind) {
  MatchKind.fireFire => '二人とも今すぐ遊びたい！',
  MatchKind.fireOk => '誘えば来る人がいるよ',
  MatchKind.okOk => 'お互い誘われ待ちだよ',
};

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.message, this.icon});

  final String message;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 28),
    child: Column(
      children: [
        Icon(
          icon ?? Icons.hourglass_empty_rounded,
          size: 34,
          color: Theme.of(context).colorScheme.outline,
        ),
        const SizedBox(height: 10),
        Text(message, style: Theme.of(context).textTheme.bodyMedium),
      ],
    ),
  );
}
