import 'dart:convert';

typedef JsonMap = Map<String, Object?>;

JsonMap readJsonMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  throw const FormatException('Expected a JSON object.');
}

List<Object?> readJsonList(Object? value) {
  if (value is List<Object?>) return value;
  throw const FormatException('Expected a JSON array.');
}

String readString(JsonMap json, String key) {
  final value = json[key];
  if (value is String) return value;
  throw FormatException('Expected "$key" to be a string.');
}

String? readOptionalString(JsonMap json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is String) return value;
  throw FormatException('Expected "$key" to be a string or null.');
}

/// Discord snowflakes arrive as JSON numbers. Dart `int` is 64-bit on mobile, so
/// the value survives the trip; the app keeps ids as Strings everywhere else and
/// converts them back to numbers only when calling the API.
String readId(JsonMap json, String key) {
  final value = json[key];
  if (value is num) return value.toInt().toString();
  if (value is String) return value;
  throw FormatException('Expected "$key" to be an id.');
}

String? readOptionalId(JsonMap json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is num) return value.toInt().toString();
  if (value is String) return value;
  throw FormatException('Expected "$key" to be an id or null.');
}

List<String> readIdList(JsonMap json, String key) {
  final value = json[key];
  if (value == null) return const [];
  return readJsonList(value).map((item) {
    if (item is num) return item.toInt().toString();
    if (item is String) return item;
    throw FormatException('Expected "$key" values to be ids.');
  }).toList();
}

int readInt(JsonMap json, String key) {
  final value = json[key];
  if (value is int) return value;
  throw FormatException('Expected "$key" to be an integer.');
}

double readDouble(JsonMap json, String key) {
  final value = json[key];
  if (value is num) return value.toDouble();
  throw FormatException('Expected "$key" to be a number.');
}

bool readBool(JsonMap json, String key) {
  final value = json[key];
  if (value is bool) return value;
  throw FormatException('Expected "$key" to be a boolean.');
}

/// Reads a flag that older rows may leave null, so a missing value falls back to
/// the contract default instead of failing the whole response.
bool readBoolOr(JsonMap json, String key, {required bool fallback}) {
  final value = json[key];
  if (value == null) return fallback;
  if (value is bool) return value;
  throw FormatException('Expected "$key" to be a boolean or null.');
}

DateTime readDateTime(JsonMap json, String key) =>
    DateTime.parse(readString(json, key)).toUtc();

DateTime? readOptionalDateTime(JsonMap json, String key) {
  final value = readOptionalString(json, key);
  return value == null ? null : DateTime.parse(value).toUtc();
}

/// `avatar` is a full CDN URL or null. `avatar_url` is still accepted because
/// that is the key the app used before it talked to the real server.
String? readAvatar(JsonMap json) =>
    readOptionalString(json, 'avatar') ?? readOptionalString(json, 'avatar_url');

List<T> readModelList<T>(Object? value, T Function(JsonMap) fromJson) =>
    readJsonList(value).map((item) => fromJson(readJsonMap(item))).toList();

enum Mood { fire, ok, quiet }

enum Activity { game, chat, work, out, any }

enum DeclarationSource { manual, suggested, auto }

enum MatchKind { fireFire, fireOk, okOk }

enum KnockStatus { pending, accepted, later, passed, expired }

enum KnockTemplate { game, chat, work }

enum DevicePlatform { android, ios }

extension MoodPresentation on Mood {
  String get label => switch (this) {
    Mood.fire => '今すぐ遊びたい',
    Mood.ok => '誘われたら行く',
    Mood.quiet => 'ひっそり暇',
  };
  String get emoji => switch (this) {
    Mood.fire => '🔥',
    Mood.ok => '🙂',
    Mood.quiet => '🌙',
  };
}

extension ActivityPresentation on Activity {
  String get label => switch (this) {
    Activity.game => 'ゲーム',
    Activity.chat => '雑談・通話',
    Activity.work => '作業通話',
    Activity.out => '外出',
    Activity.any => 'なんでもOK',
  };
  String get emoji => switch (this) {
    Activity.game => '🎮',
    Activity.chat => '💬',
    Activity.work => '💻',
    Activity.out => '🚶',
    Activity.any => '✨',
  };
}

/// Declare durations the app offers. The API accepts any minutes; the app keeps
/// these three so the picker stays a one-tap choice.
const List<int> himaDurationChoices = [30, 60, 120];
const int defaultHimaDurationMin = 60;

/// Weekday index 0 = 月曜 … 6 = 日曜, the same order as `regular_slots.weekday`.
const List<String> weekdayLabels = ['月', '火', '水', '木', '金', '土', '日'];

String durationLabel(int minutes) => switch (minutes) {
  30 => '30分',
  60 => '1時間',
  120 => '2時間',
  _ => '$minutes分',
};

/// `HH:MM` for minutes after midnight. The forecast may end a range at 1440,
/// which reads as 24:00.
String clockLabel(int minute) {
  if (minute >= 24 * 60) return '24:00';
  final hour = (minute ~/ 60).toString().padLeft(2, '0');
  final rest = (minute % 60).toString().padLeft(2, '0');
  return '$hour:$rest';
}

/// How well [other]'s activity fits [mine], used for match ordering.
/// 0 = same activity, 1 = either side なんでもOK, 2 = no preference.
/// A null activity means the user did not choose, so a null counterpart ranks
/// below `any`; `any` is still preferred even when only one side chose it.
int activityMatchRank(Activity? mine, Activity? other) {
  if (mine != null && mine == other) return 0;
  if (mine == Activity.any || other == Activity.any) return 1;
  return 2;
}

/// The match the contract defines for my mood and the other person's mood.
///
/// fire×fire and ok×ok notify both sides, so both see the match. fire×ok
/// notifies only the fire side, so it is a match for me only when I am the fire
/// one. 🌙 (the app's [Mood.quiet]) never matches.
MatchKind? matchKindFor(Mood mine, Mood other) => switch ((mine, other)) {
  (Mood.fire, Mood.fire) => MatchKind.fireFire,
  (Mood.fire, Mood.ok) => MatchKind.fireOk,
  (Mood.ok, Mood.ok) => MatchKind.okOk,
  _ => null,
};

extension KnockTemplatePresentation on KnockTemplate {
  String get text => switch (this) {
    KnockTemplate.game => 'ゲームしない？',
    KnockTemplate.chat => 'ちょっと話さない？',
    KnockTemplate.work => '作業通話しない？',
  };
}

extension KnockStatusPresentation on KnockStatus {
  String get label => switch (this) {
    KnockStatus.pending => '返事待ち',
    KnockStatus.accepted => 'いいよ！',
    KnockStatus.later => 'あとで',
    KnockStatus.passed => '今回はパス',
    KnockStatus.expired => '終了',
  };
}

/// The server calls the quiet mood `moon`; the app keeps `Mood.quiet` so the UI
/// vocabulary does not change. The mapping lives only at this boundary.
Mood moodFromJson(String value) => switch (value) {
  'fire' => Mood.fire,
  'ok' => Mood.ok,
  'moon' || 'quiet' => Mood.quiet,
  _ => throw FormatException('Unknown mood: $value'),
};

String moodToJson(Mood mood) => switch (mood) {
  Mood.fire => 'fire',
  Mood.ok => 'ok',
  Mood.quiet => 'moon',
};

/// `activity` is required by the server. The app treats "not chosen" as null and
/// sends `any`; a null in a response is still tolerated.
Activity? activityFromJsonOrNull(Object? value) {
  if (value == null) return null;
  if (value is String) return activityFromJson(value);
  throw const FormatException('Expected "activity" to be a string or null.');
}

Activity activityFromJson(String value) => switch (value) {
  'game' => Activity.game,
  'chat' => Activity.chat,
  'work' => Activity.work,
  'out' => Activity.out,
  'any' => Activity.any,
  _ => throw FormatException('Unknown activity: $value'),
};

DeclarationSource sourceFromJson(String value) => switch (value) {
  'manual' => DeclarationSource.manual,
  'suggested' => DeclarationSource.suggested,
  'auto' => DeclarationSource.auto,
  _ => throw FormatException('Unknown source: $value'),
};

/// The server's `sent` is the app's [KnockStatus.pending] (返事待ち).
KnockStatus knockStatusFromJson(String value) => switch (value) {
  'sent' || 'pending' => KnockStatus.pending,
  'accepted' => KnockStatus.accepted,
  'later' => KnockStatus.later,
  'passed' => KnockStatus.passed,
  'expired' => KnockStatus.expired,
  _ => throw FormatException('Unknown knock status: $value'),
};

/// The reply actions `POST /app/knocks/{id}/reply` accepts.
String knockReplyAction(KnockStatus status) => switch (status) {
  KnockStatus.accepted => 'accept',
  KnockStatus.later => 'later',
  KnockStatus.passed => 'pass',
  KnockStatus.pending || KnockStatus.expired => throw ArgumentError.value(
    status,
    'status',
    'not a reply action',
  ),
};

/// `knocks.template` stores the invitation text itself, not a key, so the app's
/// enum is mapped to and from the fixed phrases.
KnockTemplate knockTemplateFromJson(String value) => switch (value) {
  'ゲームしない？' || 'game' => KnockTemplate.game,
  'ちょっと話さない？' || 'chat' => KnockTemplate.chat,
  '作業通話しない？' || 'work' => KnockTemplate.work,
  _ => throw FormatException('Unknown knock template: $value'),
};

DevicePlatform devicePlatformFromJson(String value) => switch (value) {
  'android' => DevicePlatform.android,
  'ios' => DevicePlatform.ios,
  _ => throw FormatException('Unknown device platform: $value'),
};

class DiscordAuthRequest {
  const DiscordAuthRequest({
    required this.code,
    required this.codeVerifier,
    required this.redirectUri,
  });

  final String code;
  final String codeVerifier;
  final String redirectUri;

  JsonMap toJson() => {
    'code': code,
    'code_verifier': codeVerifier,
    'redirect_uri': redirectUri,
  };
}

class UserSettings {
  const UserSettings({
    required this.autoMode,
    required this.autoMood,
    required this.notifyOnHima,
  });

  /// Used when a payload has no settings yet (the OAuth response, for example).
  static const fallback = UserSettings(
    autoMode: false,
    autoMood: Mood.ok,
    notifyOnHima: false,
  );

  final bool autoMode;
  final Mood autoMood;
  final bool notifyOnHima;

  factory UserSettings.fromJson(JsonMap json) => UserSettings(
    autoMode: readBoolOr(json, 'auto_mode', fallback: false),
    autoMood: _moodOrOk(readOptionalString(json, 'auto_mood')),
    notifyOnHima: readBoolOr(json, 'notify_on_hima', fallback: false),
  );

  UserSettings copyWith({bool? autoMode, Mood? autoMood, bool? notifyOnHima}) =>
      UserSettings(
        autoMode: autoMode ?? this.autoMode,
        autoMood: autoMood ?? this.autoMood,
        notifyOnHima: notifyOnHima ?? this.notifyOnHima,
      );
}

Mood _moodOrOk(String? value) {
  if (value == null) return Mood.ok;
  try {
    return moodFromJson(value);
  } on FormatException {
    return Mood.ok;
  }
}

class UserProfile {
  const UserProfile({
    required this.id,
    required this.displayName,
    required this.settings,
    this.avatarUrl,
  });

  final String id;
  final String displayName;
  final String? avatarUrl;
  final UserSettings settings;

  UserSummary get summary =>
      UserSummary(id: id, displayName: displayName, avatarUrl: avatarUrl);

  /// `GET /app/me` returns `{user, settings, session, memberships}`.
  factory UserProfile.fromJson(JsonMap json) {
    final nestedUser = json['user'] ?? json['me'];
    final userJson = nestedUser == null ? json : readJsonMap(nestedUser);
    final settingsJson = json['settings'] ?? userJson['settings'];
    return UserProfile(
      id: readId(userJson, 'id'),
      displayName: readString(userJson, 'display_name'),
      avatarUrl: readAvatar(userJson),
      settings: settingsJson == null
          ? UserSettings.fallback
          : UserSettings.fromJson(readJsonMap(settingsJson)),
    );
  }

  UserProfile withSettings(UserSettings settings) => UserProfile(
    id: id,
    displayName: displayName,
    avatarUrl: avatarUrl,
    settings: settings,
  );
}

class UserSummary {
  const UserSummary({
    required this.id,
    required this.displayName,
    this.avatarUrl,
  });

  final String id;
  final String displayName;
  final String? avatarUrl;

  /// Accepts both `{id, display_name, avatar}` (`/app/me`) and
  /// `{user_id, display_name, avatar}` (`/app/members`).
  factory UserSummary.fromJson(JsonMap json) => UserSummary(
    id: readOptionalId(json, 'id') ?? readId(json, 'user_id'),
    displayName: readString(json, 'display_name'),
    avatarUrl: readAvatar(json),
  );
}

/// One of my servers, from `/app/me` memberships or `/app/members`.
class Guild {
  const Guild({required this.id, required this.name, required this.visible});

  final String id;
  final String name;
  final bool visible;

  /// `{guild_id, guild_name, visible}` (memberships) or
  /// `{guild_id, name, visible}` (`/app/members`).
  factory Guild.fromJson(JsonMap json) => Guild(
    id: readOptionalId(json, 'guild_id') ?? readId(json, 'id'),
    name:
        readOptionalString(json, 'guild_name') ??
        readOptionalString(json, 'name') ??
        '',
    visible: readBoolOr(json, 'visible', fallback: true),
  );

  Guild withVisibility(bool visible) =>
      Guild(id: id, name: name, visible: visible);
}

/// The server does not report which server a knock went through, so only the
/// offline mock fills this in.
class GuildSummary {
  const GuildSummary({required this.id, required this.name});

  final String id;
  final String name;
}

/// A person the caller shares a Discord server with. `hima` is null when the
/// person is not currently free (or the server is not visible to the caller).
class FriendMember {
  const FriendMember({required this.user, this.hima});

  final UserSummary user;
  final HimaSession? hima;

  bool get isFree => hima != null;

  FriendMember withHima(HimaSession? hima) =>
      FriendMember(user: user, hima: hima);
}

/// Members of one shared server, used by the 友達 tab.
class FriendServer {
  const FriendServer({required this.guild, required this.members});

  final Guild guild;
  final List<FriendMember> members;

  FriendServer withMembers(List<FriendMember> members) =>
      FriendServer(guild: guild, members: members);
}

class HimaDeclaration {
  const HimaDeclaration({
    required this.mood,
    required this.activity,
    required this.durationMin,
    required this.source,
    this.note,
  });

  final Mood mood;
  final Activity? activity;
  final String? note;
  final int durationMin;
  final DeclarationSource source;

  /// `POST /app/sessions {mood, activity, note, minutes, source}`.
  ///
  /// `activity` is required by the server, so an unchosen activity is sent as
  /// `any`; the duration is sent as `minutes`.
  JsonMap toJson() => {
    'mood': moodToJson(mood),
    'activity': activity?.name ?? Activity.any.name,
    'note': note,
    'minutes': durationMin,
    'source': source.name,
  };
}

class HimaSession {
  const HimaSession({
    required this.sessionId,
    required this.user,
    required this.mood,
    required this.activity,
    required this.startedAt,
    required this.expiresAt,
    this.durationMin = 0,
    this.guildIds = const [],
    this.note,
    this.source,
  });

  final String sessionId;
  final UserSummary user;
  final Mood mood;
  final Activity? activity;
  final String? note;
  final DateTime startedAt;
  final DateTime expiresAt;
  final int durationMin;
  final List<String> guildIds;

  // Other users' sessions never carry source; only `/app/me` does.
  final DeclarationSource? source;

  Duration get remaining => expiresAt.difference(DateTime.now().toUtc());

  /// Parses either a `/app/board` row or my own `/app/me` session.
  ///
  /// Board rows carry the owner as flat `user_id` / `display_name` and have no
  /// session id or `started_at`; my own session has `source` and `started_at`
  /// but no user, so [owner] supplies it.
  factory HimaSession.fromJson(JsonMap json, {UserSummary? owner}) {
    final expiresAt = readDateTime(json, 'expires_at');
    final remaining = json['remaining_minutes'];
    final remainingMin = remaining is num ? remaining.toInt() : null;
    final startedAtValue = json['started_at'];
    final startedAt = startedAtValue is String
        ? DateTime.parse(startedAtValue).toUtc()
        : expiresAt.subtract(Duration(minutes: remainingMin ?? 0));
    final user =
        owner ??
        UserSummary(
          id: readId(json, 'user_id'),
          displayName: readOptionalString(json, 'display_name') ?? '',
          avatarUrl: readAvatar(json),
        );
    final durationMinValue = json['duration_min'];
    final sourceValue = readOptionalString(json, 'source');
    return HimaSession(
      // The server has no session id in these payloads; the owner id is stable
      // across an extend, which is what the UI keys on.
      sessionId: readOptionalString(json, 'session_id') ?? 'u:${user.id}',
      user: user,
      mood: moodFromJson(readString(json, 'mood')),
      activity: activityFromJsonOrNull(json['activity']),
      note: readOptionalString(json, 'note'),
      startedAt: startedAt,
      expiresAt: expiresAt,
      durationMin: durationMinValue is num
          ? durationMinValue.toInt()
          : remainingMin ?? expiresAt.difference(startedAt).inMinutes,
      guildIds: json.containsKey('shared_guild_ids')
          ? readIdList(json, 'shared_guild_ids')
          : readIdList(json, 'guild_ids'),
      source: sourceValue == null ? null : sourceFromJson(sourceValue),
    );
  }

  /// Returns this session with the duration the user actually picked.
  ///
  /// The server keeps `started_at` when a declaration is extended, so
  /// `expires_at - started_at` grows on every extend and cannot be used as the
  /// chosen duration. The app remembers the choice and stamps it here.
  HimaSession withDurationMin(int minutes) => HimaSession(
    sessionId: sessionId,
    user: user,
    mood: mood,
    activity: activity,
    note: note,
    startedAt: startedAt,
    expiresAt: expiresAt,
    durationMin: minutes,
    guildIds: guildIds,
    source: source,
  );
}

class MatchRecord {
  const MatchRecord({
    required this.mySessionId,
    required this.otherSessionId,
    required this.kind,
    required this.otherUser,
    required this.otherHima,
    required this.createdAt,
  });

  final String mySessionId;
  final String otherSessionId;
  final MatchKind kind;
  final UserSummary otherUser;
  final MatchedHima otherHima;
  final DateTime createdAt;

  String get id => '$mySessionId:$otherSessionId';
}

class MatchedHima {
  const MatchedHima({
    required this.mood,
    required this.activity,
    required this.expiresAt,
    this.note,
  });

  final Mood mood;
  final Activity? activity;
  final String? note;
  final DateTime expiresAt;
}

class Knock {
  const Knock({
    required this.id,
    this.sender,
    this.recipient,
    required this.template,
    required this.status,
    required this.createdAt,
    required this.message,
    this.guild,
    this.respondedAt,
    this.recipientNote,
    this.resultSeenAt,
  });

  final String id;
  final UserSummary? sender;
  final UserSummary? recipient;
  final KnockTemplate template;
  final KnockStatus status;
  final DateTime createdAt;

  /// The server does not report which server a knock went through, so this is
  /// only filled in by the offline mock.
  final GuildSummary? guild;
  final String message;
  final DateTime? respondedAt;

  /// Hint shown on a received knock. `to_moon` is carried here because the UI
  /// already has one slot for it.
  final String? recipientNote;
  final DateTime? resultSeenAt;

  /// A knock I received: `{id, from_user, from_display_name, template,
  /// created_at, to_moon}`.
  factory Knock.fromInboxJson(JsonMap json) {
    final template = knockTemplateFromJson(readString(json, 'template'));
    return Knock(
      id: readId(json, 'id'),
      sender: UserSummary(
        id: readId(json, 'from_user'),
        displayName: readOptionalString(json, 'from_display_name') ?? '',
      ),
      template: template,
      // The inbox only carries knocks that are still waiting for my answer.
      status: KnockStatus.pending,
      createdAt: readDateTime(json, 'created_at'),
      message: template.text,
      // `to_moon` means I am 🌙 right now, so the knock is informational.
      recipientNote: readBoolOr(json, 'to_moon', fallback: false)
          ? 'スルーしてOK'
          : null,
    );
  }

  /// A reply to a knock I sent, from `/app/board` `results`:
  /// `{id, to_user, to_display_name, template, status, responded_at}`.
  factory Knock.fromResultJson(JsonMap json) {
    final template = knockTemplateFromJson(readString(json, 'template'));
    final respondedAt = readOptionalDateTime(json, 'responded_at');
    return Knock(
      id: readId(json, 'id'),
      recipient: UserSummary(
        id: readId(json, 'to_user'),
        displayName: readOptionalString(json, 'to_display_name') ?? '',
      ),
      template: template,
      status: knockStatusFromJson(readString(json, 'status')),
      // An expired knock never got an answer, so it has no `responded_at`.
      createdAt: respondedAt ?? DateTime.now().toUtc(),
      message: template.text,
      respondedAt: respondedAt,
    );
  }

  /// A knock I sent, from `GET /app/knocks/sent`.
  factory Knock.fromSentJson(JsonMap json) {
    final template = knockTemplateFromJson(readString(json, 'template'));
    return Knock(
      id: readId(json, 'id'),
      recipient: UserSummary(
        id: readId(json, 'to_user_id'),
        displayName: readOptionalString(json, 'to_display_name') ?? '',
        avatarUrl: readOptionalString(json, 'to_avatar') ?? readAvatar(json),
      ),
      template: template,
      status: knockStatusFromJson(readString(json, 'status')),
      createdAt: readDateTime(json, 'created_at'),
      message: template.text,
      respondedAt: readOptionalDateTime(json, 'responded_at'),
      resultSeenAt: readOptionalDateTime(json, 'result_seen_at'),
    );
  }

  Knock copyWith({
    KnockStatus? status,
    DateTime? respondedAt,
    DateTime? resultSeenAt,
  }) => Knock(
    id: id,
    sender: sender,
    recipient: recipient,
    template: template,
    status: status ?? this.status,
    createdAt: createdAt,
    message: message,
    guild: guild,
    respondedAt: respondedAt ?? this.respondedAt,
    recipientNote: recipientNote,
    resultSeenAt: resultSeenAt ?? this.resultSeenAt,
  );
}

class BlockedUser {
  const BlockedUser({required this.user, this.createdAt});

  final UserSummary user;
  final DateTime? createdAt;

  /// One entry of `GET /app/blocks`.
  ///
  /// The server currently returns bare ids; the requested shape adds the name
  /// and avatar. Both are accepted, and the caller fills a missing name from the
  /// members it already knows.
  factory BlockedUser.fromBlockedEntry(Object? entry) {
    if (entry is num || entry is String) {
      return BlockedUser(
        user: UserSummary(
          id: entry is num ? entry.toInt().toString() : entry as String,
          displayName: '',
        ),
      );
    }
    final json = readJsonMap(entry);
    return BlockedUser(
      user: UserSummary(
        id: readId(json, 'user_id'),
        displayName: readOptionalString(json, 'display_name') ?? '',
        avatarUrl: readAvatar(json),
      ),
    );
  }

  BlockedUser withUser(UserSummary user) =>
      BlockedUser(user: user, createdAt: createdAt);
}

class DeviceRegistration {
  const DeviceRegistration({required this.platform, required this.fcmToken});

  final DevicePlatform platform;
  final String fcmToken;

  JsonMap toJson() => {'platform': platform.name, 'fcm_token': fcmToken};
}

class RegularSlot {
  const RegularSlot({
    required this.weekday,
    required this.startMin,
    required this.endMin,
    this.id,
  });

  /// Server id. Null for a slot that has not been saved yet.
  final String? id;

  /// 0 = 月曜 … 6 = 日曜.
  final int weekday;
  final int startMin;
  final int endMin;

  factory RegularSlot.fromJson(JsonMap json) => RegularSlot(
    id: readOptionalId(json, 'id'),
    weekday: readInt(json, 'weekday'),
    startMin: readInt(json, 'start_min'),
    endMin: readInt(json, 'end_min'),
  );

  /// `POST /app/regular-slots {weekday, start_min, end_min}`.
  JsonMap toJson() => {
    'weekday': weekday,
    'start_min': startMin,
    'end_min': endMin,
  };
}

/// One free-time range from `GET /app/free-time/forecast`.
///
/// `endMin` can be 1440 (midnight) because the server merges 30-minute slots.
class HimaTimeSuggestion {
  const HimaTimeSuggestion({
    required this.weekday,
    required this.startMin,
    required this.endMin,
    required this.basis,
    required this.score,
    required this.days,
  });

  /// 0 = 月曜 … 6 = 日曜.
  final int weekday;
  final int startMin;
  final int endMin;

  /// `history` (past declarations only), `manual` (regular slots only) or
  /// `both`.
  final String basis;
  final double score;
  final int days;

  factory HimaTimeSuggestion.fromJson(JsonMap json) => HimaTimeSuggestion(
    weekday: readInt(json, 'weekday'),
    startMin: readInt(json, 'start_min'),
    endMin: readInt(json, 'end_min'),
    basis: readOptionalString(json, 'basis') ?? 'history',
    score: json['score'] is num ? readDouble(json, 'score') : 0,
    days: json['days'] is num ? readInt(json, 'days') : 0,
  );

  /// 「月曜 22:00〜23:30 によくひま」.
  String get label =>
      '${weekdayLabels[weekday.clamp(0, weekdayLabels.length - 1)]}曜 '
      '${clockLabel(startMin)}〜${clockLabel(endMin)} によくひま';
}

/// Everything `GET /app/me` returns: my profile, my settings, my own active
/// session (the only place `source` is visible) and my server memberships.
class MeSnapshot {
  const MeSnapshot({
    required this.profile,
    required this.session,
    required this.guilds,
  });

  final UserProfile profile;
  final HimaSession? session;
  final List<Guild> guilds;
}

/// Everything `GET /app/board` returns: other people's active sessions, the
/// knocks I received and the replies to my knocks that I have not seen yet.
class BoardSnapshot {
  const BoardSnapshot({
    required this.sessions,
    required this.inbox,
    required this.results,
  });

  final List<HimaSession> sessions;
  final List<Knock> inbox;
  final List<Knock> results;
}

Object? decodeJson(String body) => jsonDecode(body) as Object?;

String encodeJson(Object value) => jsonEncode(value);
