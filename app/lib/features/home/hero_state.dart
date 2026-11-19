import '../../../data/models/models.dart';
import '../../shared/phrase_wrap.dart';

/// The three hero states from Design.md 2.
enum HeroPhase { idle, declared, justExpired }

/// Single source of truth for the hero.
///
/// The heading, supporting line, background color and buttons are all derived
/// from this object so the UI can never show 「いま、ひま！」 together with
/// 「ひまを宣言」.
class HeroState {
  const HeroState({
    required this.phase,
    required this.mood,
    required this.activity,
    required this.durationMin,
    this.expiresAt,
  });

  factory HeroState.fromSession(
    HimaSession? session, {
    required bool justExpired,
    required Mood fallbackMood,
  }) {
    final now = DateTime.now().toUtc();
    if (session != null && session.expiresAt.isAfter(now)) {
      return HeroState(
        phase: HeroPhase.declared,
        mood: session.mood,
        activity: session.activity,
        durationMin: session.durationMin,
        expiresAt: session.expiresAt,
      );
    }
    return HeroState(
      phase: justExpired ? HeroPhase.justExpired : HeroPhase.idle,
      mood: session?.mood ?? fallbackMood,
      activity: session?.activity,
      durationMin: session?.durationMin ?? defaultHimaDurationMin,
    );
  }

  final HeroPhase phase;
  final Mood mood;
  final Activity? activity;
  final int durationMin;
  final DateTime? expiresAt;

  bool get isDeclared => phase == HeroPhase.declared;

  String get heading => isDeclared ? 'いま、ひま！' : 'いま、ひま？';

  String get supporting => switch (phase) {
    HeroPhase.declared => remainingLabel(),
    HeroPhase.justExpired => 'ひま宣言が終了したよ',
    // Phrase by phrase, so a large text scale wraps between 「ひまなら」,
    // 「友達に」 and 「知らせよう」 instead of inside one of them.
    HeroPhase.idle => wrapPhrases(['ひまなら', '友達に', '知らせよう']),
  };

  String remainingLabel([DateTime? now]) {
    final expiresAt = this.expiresAt;
    if (expiresAt == null) return '';
    return himaRemainingLabel(expiresAt, now);
  }
}

/// 「あと1時間くらい」 style label, rounded up so a fresh 60 minute declaration
/// reads as 1時間 rather than 59分.
String himaRemainingLabel(DateTime expiresAt, [DateTime? now]) {
  final seconds = expiresAt.difference(now ?? DateTime.now().toUtc()).inSeconds;
  final minutes = (seconds + 59) ~/ 60;
  if (minutes <= 0) return 'まもなく終了';
  if (minutes >= 60) {
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0 ? 'あと$hours時間くらい' : 'あと$hours時間$rest分くらい';
  }
  return 'あと$minutes分くらい';
}

/// 「あと59分」: the hero's own remaining time, without the hedge.
///
/// The meta row puts the time, the activity and 「おわる」 on one line, and
/// 「あと1時間くらい」 made the time the widest of the three for no extra
/// information — the rounding is already a guess inside the number itself. The
/// friend cards keep [himaRemainingLabel], where the hedge is the point: that
/// is someone else's declaration.
String himaRemainingShortLabel(DateTime expiresAt, [DateTime? now]) {
  final seconds = expiresAt.difference(now ?? DateTime.now().toUtc()).inSeconds;
  final minutes = (seconds + 59) ~/ 60;
  if (minutes <= 0) return 'まもなく終了';
  if (minutes >= 60) {
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0 ? 'あと$hours時間' : 'あと$hours時間$rest分';
  }
  return 'あと$minutes分';
}
