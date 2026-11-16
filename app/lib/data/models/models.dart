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

List<String> readOptionalStringList(JsonMap json, String key) {
  final value = json[key];
  if (value == null) return const [];
  return readJsonList(value).map((item) {
    if (item is String) return item;
    throw FormatException('Expected "$key" values to be strings.');
  }).toList();
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

DateTime readDateTime(JsonMap json, String key) =>
    DateTime.parse(readString(json, key)).toUtc();

DateTime? readOptionalDateTime(JsonMap json, String key) {
  final value = readOptionalString(json, key);
  return value == null ? null : DateTime.parse(value).toUtc();
}

String readOneOfStrings(JsonMap json, String firstKey, String secondKey) {
  if (json.containsKey(firstKey)) return readString(json, firstKey);
  return readString(json, secondKey);
}

UserSummary? readOptionalUser(JsonMap json, String key) {
  final value = json[key];
  return value == null ? null : UserSummary.fromJson(readJsonMap(value));
}

List<T> readModelList<T>(Object? value, T Function(JsonMap) fromJson) =>
    readJsonList(value).map((item) => fromJson(readJsonMap(item))).toList();

enum Mood { fire, ok, quiet }

enum Activity { game, chat, work, out, any }

enum DeclarationSource { manual, suggested, auto }

enum MatchKind { fireFire, fireOk, okOk }

enum KnockStatus { pending, accepted, later, passed }

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
  };
}

Mood moodFromJson(String value) => switch (value) {
  'fire' => Mood.fire,
  'ok' => Mood.ok,
  'quiet' => Mood.quiet,
  _ => throw FormatException('Unknown mood: $value'),
};

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

MatchKind matchKindFromJson(String value) => switch (value) {
  'fire_fire' => MatchKind.fireFire,
  'fire_ok' => MatchKind.fireOk,
  'ok_ok' => MatchKind.okOk,
  _ => throw FormatException('Unknown match kind: $value'),
};

KnockStatus knockStatusFromJson(String value) => switch (value) {
  'pending' => KnockStatus.pending,
  'accepted' => KnockStatus.accepted,
  'later' => KnockStatus.later,
  'passed' => KnockStatus.passed,
  _ => throw FormatException('Unknown knock status: $value'),
};

KnockTemplate knockTemplateFromJson(String value) => switch (value) {
  'game' => KnockTemplate.game,
  'chat' => KnockTemplate.chat,
  'work' => KnockTemplate.work,
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

  final bool autoMode;
  final Mood autoMood;
  final bool notifyOnHima;

  factory UserSettings.fromJson(JsonMap json) => UserSettings(
    autoMode: readBool(json, 'auto_mode'),
    autoMood: moodFromJson(readString(json, 'auto_mood')),
    notifyOnHima: readBool(json, 'notify_on_hima'),
  );

  JsonMap toJson() => {
    'auto_mode': autoMode,
    'auto_mood': autoMood.name,
    'notify_on_hima': notifyOnHima,
  };
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

  factory UserProfile.fromJson(JsonMap json) {
    final nestedUser = json['user'] ?? json['me'];
    final userJson = nestedUser == null ? json : readJsonMap(nestedUser);
    final settingsJson = json['settings'] ?? userJson['settings'];
    return UserProfile(
      id: readString(userJson, 'id'),
      displayName: readString(userJson, 'display_name'),
      avatarUrl: readOptionalString(userJson, 'avatar_url'),
      settings: UserSettings.fromJson(readJsonMap(settingsJson)),
    );
  }

  JsonMap toJson() => {
    'user': {'id': id, 'display_name': displayName, 'avatar_url': avatarUrl},
    'settings': settings.toJson(),
  };
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

  factory UserSummary.fromJson(JsonMap json) => UserSummary(
    id: readString(json, 'id'),
    displayName: readString(json, 'display_name'),
    avatarUrl: readOptionalString(json, 'avatar_url'),
  );

  JsonMap toJson() => {
    'id': id,
    'display_name': displayName,
    if (avatarUrl != null) 'avatar_url': avatarUrl,
  };
}

class Guild {
  const Guild({required this.id, required this.name, required this.visible});

  final String id;
  final String name;
  final bool visible;

  factory Guild.fromJson(JsonMap json) => Guild(
    id: readString(json, 'id'),
    name: readString(json, 'name'),
    visible: readBool(json, 'visible'),
  );

  JsonMap toJson() => {'id': id, 'name': name, 'visible': visible};
}

class GuildSummary {
  const GuildSummary({required this.id, required this.name});

  final String id;
  final String name;

  factory GuildSummary.fromJson(JsonMap json) =>
      GuildSummary(id: readString(json, 'id'), name: readString(json, 'name'));

  JsonMap toJson() => {'id': id, 'name': name};
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
  final Activity activity;
  final String? note;
  final int durationMin;
  final DeclarationSource source;

  JsonMap toJson() => {
    'mood': mood.name,
    'activity': activity.name,
    'note': note,
    'duration_min': durationMin,
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
  final Activity activity;
  final String? note;
  final DateTime startedAt;
  final DateTime expiresAt;
  final int durationMin;
  final List<String> guildIds;

  // Other users' sessions never carry source; only /hima/me may set it.
  final DeclarationSource? source;

  Duration get remaining => expiresAt.difference(DateTime.now().toUtc());

  factory HimaSession.fromJson(JsonMap json) {
    final sourceValue = readOptionalString(json, 'source');
    final startedAt = readDateTime(json, 'started_at');
    final expiresAt = readDateTime(json, 'expires_at');
    final userJson = json['user'];
    final user = userJson == null
        ? UserSummary(
            id: readString(json, 'user_id'),
            displayName: readOptionalString(json, 'display_name') ?? '',
            avatarUrl: readOptionalString(json, 'avatar_url'),
          )
        : UserSummary.fromJson(readJsonMap(userJson));
    final guildIds = json.containsKey('guild_ids')
        ? readOptionalStringList(json, 'guild_ids')
        : readJsonList(
            json['guilds'] ?? const <Object?>[],
          ).map((item) => readString(readJsonMap(item), 'id')).toList();
    final durationMinValue = json['duration_min'];
    return HimaSession(
      sessionId: readString(json, 'session_id'),
      user: user,
      mood: moodFromJson(readString(json, 'mood')),
      activity: activityFromJson(readString(json, 'activity')),
      note: readOptionalString(json, 'note'),
      startedAt: startedAt,
      expiresAt: expiresAt,
      durationMin: durationMinValue is int
          ? durationMinValue
          : expiresAt.difference(startedAt).inMinutes,
      guildIds: guildIds,
      source: sourceValue == null ? null : sourceFromJson(sourceValue),
    );
  }

  JsonMap toJson() {
    final sessionSource = source;
    return {
      'session_id': sessionId,
      'user': user.toJson(),
      'mood': mood.name,
      'activity': activity.name,
      'note': note,
      'duration_min': durationMin,
      'started_at': startedAt.toUtc().toIso8601String(),
      'expires_at': expiresAt.toUtc().toIso8601String(),
      'guild_ids': guildIds,
      if (sessionSource != null) 'source': sessionSource.name,
    };
  }
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

  factory MatchRecord.fromJson(JsonMap json) => MatchRecord(
    mySessionId: readOneOfStrings(json, 'my_session_id', 'my_hima_session_id'),
    otherSessionId: readOneOfStrings(
      json,
      'other_session_id',
      'other_hima_session_id',
    ),
    kind: matchKindFromJson(readString(json, 'kind')),
    otherUser: UserSummary.fromJson(readJsonMap(json['other_user'])),
    otherHima: MatchedHima.fromJson(readJsonMap(json['other_hima'])),
    createdAt: readDateTime(json, 'created_at'),
  );

  JsonMap toJson() => {
    'my_session_id': mySessionId,
    'other_session_id': otherSessionId,
    'kind': switch (kind) {
      MatchKind.fireFire => 'fire_fire',
      MatchKind.fireOk => 'fire_ok',
      MatchKind.okOk => 'ok_ok',
    },
    'other_user': otherUser.toJson(),
    'other_hima': otherHima.toJson(),
    'created_at': createdAt.toUtc().toIso8601String(),
  };
}

class MatchedHima {
  const MatchedHima({
    required this.mood,
    required this.activity,
    required this.expiresAt,
    this.note,
  });

  final Mood mood;
  final Activity activity;
  final String? note;
  final DateTime expiresAt;

  factory MatchedHima.fromJson(JsonMap json) => MatchedHima(
    mood: moodFromJson(readString(json, 'mood')),
    activity: activityFromJson(readString(json, 'activity')),
    note: readOptionalString(json, 'note'),
    expiresAt: readDateTime(json, 'expires_at'),
  );

  JsonMap toJson() => {
    'mood': mood.name,
    'activity': activity.name,
    'note': note,
    'expires_at': expiresAt.toUtc().toIso8601String(),
  };
}

class Knock {
  const Knock({
    required this.id,
    this.sender,
    this.recipient,
    required this.template,
    required this.status,
    required this.createdAt,
    required this.guild,
    required this.message,
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
  final GuildSummary guild;
  final String message;
  final DateTime? respondedAt;
  final String? recipientNote;
  final DateTime? resultSeenAt;

  factory Knock.fromJson(JsonMap json) => Knock(
    id: readString(json, 'id'),
    sender:
        readOptionalUser(json, 'sender') ?? readOptionalUser(json, 'from_user'),
    recipient:
        readOptionalUser(json, 'recipient') ??
        readOptionalUser(json, 'to_user'),
    template: knockTemplateFromJson(readString(json, 'template')),
    status: knockStatusFromJson(readString(json, 'status')),
    createdAt: readDateTime(json, 'created_at'),
    guild: GuildSummary.fromJson(readJsonMap(json['guild'])),
    message: readString(json, 'message'),
    respondedAt: readOptionalDateTime(json, 'responded_at'),
    recipientNote: readOptionalString(json, 'recipient_note'),
    resultSeenAt: readOptionalDateTime(json, 'result_seen_at'),
  );

  JsonMap toJson() {
    final knockSender = sender;
    final knockRecipient = recipient;
    return {
      'id': id,
      if (knockSender != null) 'from_user': knockSender.toJson(),
      if (knockRecipient != null) 'to_user': knockRecipient.toJson(),
      'template': template.name,
      'status': status.name,
      'created_at': createdAt.toUtc().toIso8601String(),
      'guild': guild.toJson(),
      'message': message,
      'responded_at': respondedAt?.toUtc().toIso8601String(),
      'recipient_note': recipientNote,
      'result_seen_at': resultSeenAt?.toUtc().toIso8601String(),
    };
  }
}

class BlockedUser {
  const BlockedUser({required this.user, required this.createdAt});

  final UserSummary user;
  final DateTime createdAt;

  factory BlockedUser.fromJson(JsonMap json) {
    final nestedUser = json['user'];
    final user = nestedUser == null
        ? UserSummary(
            id: readString(json, 'user_id'),
            displayName: readOptionalString(json, 'display_name') ?? '',
            avatarUrl: readOptionalString(json, 'avatar_url'),
          )
        : UserSummary.fromJson(readJsonMap(nestedUser));
    return BlockedUser(user: user, createdAt: readDateTime(json, 'created_at'));
  }

  JsonMap toJson() => {
    'user': user.toJson(),
    'created_at': createdAt.toUtc().toIso8601String(),
  };
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
  });

  final int weekday;
  final int startMin;
  final int endMin;

  factory RegularSlot.fromJson(JsonMap json) => RegularSlot(
    weekday: readInt(json, 'weekday'),
    startMin: readInt(json, 'start_min'),
    endMin: readInt(json, 'end_min'),
  );

  JsonMap toJson() => {
    'weekday': weekday,
    'start_min': startMin,
    'end_min': endMin,
  };
}

class HimaTimeSuggestion {
  const HimaTimeSuggestion({
    required this.weekday,
    required this.hour,
    required this.likelihood,
  });

  final int weekday;
  final int hour;
  final double likelihood;

  factory HimaTimeSuggestion.fromJson(JsonMap json) => HimaTimeSuggestion(
    weekday: readInt(json, 'weekday'),
    hour: readInt(json, 'hour'),
    likelihood: readDouble(json, 'likelihood'),
  );

  JsonMap toJson() => {
    'weekday': weekday,
    'hour': hour,
    'likelihood': likelihood,
  };
}

Object? decodeJson(String body) => jsonDecode(body) as Object?;

String encodeJson(Object value) => jsonEncode(value);
