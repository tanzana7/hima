# API契約案

atsumaro モバイルアプリと API サーバー間の初版契約案です。以下のパスは API_BASE_URL からの相対パスで、JSON は UTF-8 とします。

## 共通仕様

- POST /auth/discord 以外は Authorization: Bearer <session_token> が必要です。
- Discord のユーザー ID・サーバー ID などの Snowflake は JSON で必ず文字列にします。API が発行するヒマセッション ID とノック ID も文字列です。
- 日時は UTC の ISO 8601 形式（例: 2026-11-16T12:34:56Z）。残り時間は expires_at と端末時刻から算出します。
- Bot から API への認証はアプリ用 token と分離し、別途共有するサーバー間シークレットを使います。Bot 専用 API はこの契約の対象外です。
- mood は次の値です。

| 値 | 表示 |
| --- | --- |
| fire | 🔥 今すぐ遊びたい |
| ok | 🙂 誘われたら行く |
| quiet | 🌙 ひっそり暇 |

- activity は次の値です。

| 値 | 表示 |
| --- | --- |
| game | 🎮 ゲーム |
| chat | 💬 雑談・通話 |
| work | 💻 作業通話 |
| out | 🚶 外出 |
| any | ✨ なんでもOK |

- duration_min は 5 / 15 / 30 / 60 / 180 です（表示は順に 5分 / 15分 / 30分 / 1時間 / 3時間）。source は manual / suggested / auto です。
- note は省略または null 可。文字列は Unicode コードポイント数で 50 文字以内とし、空文字は null に正規化します。
- 定期時間の weekday は月曜 0〜日曜 6、時刻は日本時間（Asia/Tokyo）の 0:00 からの分数です。

共通エラーは次の形式です。details は項目別の理由がある場合だけ付け、クライアントは message ではなく code で分岐します。

    {
      "error": {
        "code": "validation_error",
        "message": "入力内容を確認してください。",
        "details": {"duration_min": "must_be_one_of_5_15_30_60_180"}
      }
    }

| HTTP | code の例 | 意味 |
| --- | --- | --- |
| 400 | validation_error | JSON や値が不正 |
| 401 | unauthorized | token 不在・無効・期限切れ |
| 403 | forbidden | 操作権限がない |
| 404 | not_found | 存在しない、または公開対象ではない |
| 409 | conflict | 現在の状態では操作できない |
| 429 | rate_limited | 呼び出し上限超過 |
| 500 | internal_error | サーバー内部エラー |

## 認証

### POST /auth/discord

アプリが Discord OAuth2 PKCE で取得した認可 code を受け取ります。サーバーは設定済みの Discord client ID、許可済み redirect URI、受け取った code_verifier を使い、Discord token endpoint で code を交換します。続けて Discord の GET /users/@me を呼んで利用者を特定し、Discord token はアプリへ返さず API 独自の session token を発行します。redirect_uri は登録値との完全一致を検証します。

リクエスト:

    {
      "code": "discord_authorization_code",
      "code_verifier": "pkce_original_verifier",
      "redirect_uri": "atsumaro://oauth2/callback"
    }

200 OK:

    {
      "access_token": "api_session_token",
      "token_type": "Bearer",
      "expires_at": "2026-11-17T12:34:56Z",
      "me": {
        "id": "123456789012345678",
        "display_name": "あつまろユーザー",
        "avatar_url": null,
        "settings": {
          "auto_mode": false,
          "auto_mood": "ok",
          "notify_on_hima": true
        }
      }
    }

無効・使用済み code、PKCE 失敗、redirect URI 不一致は 400 invalid_oauth_code とします。

## アカウントと設定

### GET /me

200 OK:

    {
      "user": {
        "id": "123456789012345678",
        "display_name": "あつまろユーザー",
        "avatar_url": null
      },
      "settings": {
        "auto_mode": false,
        "auto_mood": "ok",
        "notify_on_hima": true
      }
    }

新規アカウントの auto_mode は false、auto_mood は ok です。notify_on_hima は友達の新しいヒマ宣言通知の設定です。

### PATCH /me/settings

auto_mode、auto_mood、notify_on_hima のうち 1 項目以上を部分更新します。auto_mood は fire / ok / quiet のみです。

リクエスト例:

    {"auto_mode": true, "auto_mood": "ok", "notify_on_hima": false}

200 OK は更新後の GET /me と同じ形式です。auto_mode 有効時に宣言する条件と実行時刻はサーバーが管理します。

## Discord サーバー

### GET /guilds

Bot と共有しているサーバーと、呼び出し元の公開設定を返します。visible は、そのサーバー上の友達に自分の宣言を公開するかを示します。

200 OK:

    {
      "guilds": [
        {"id": "234567890123456789", "name": "週末ゲーム部", "visible": true}
      ]
    }

### PATCH /guilds/{id}

id は Discord guild Snowflake です。リクエストは {"visible": false}。200 OK:

    {"id": "234567890123456789", "visible": false}

## ヒマ宣言

### GET /hima/me

自分の宣言を返します。宣言中でなければ {"hima": null} です。本人の宣言には source を含めます。

200 OK の例:

    {
      "hima": {
        "session_id": "hima_01JCV9R4M5Q8",
        "user": {
          "id": "123456789012345678",
          "display_name": "あつまろユーザー",
          "avatar_url": null
        },
        "mood": "fire",
        "activity": "game",
        "note": "30分だけ",
        "duration_min": 30,
        "guild_ids": ["234567890123456789"],
        "source": "manual",
        "started_at": "2026-11-16T12:00:00Z",
        "expires_at": "2026-11-16T12:30:00Z"
      }
    }

### PUT /hima/me

新規作成または現在の宣言の延長・更新です。アカウントごとに有効な宣言は最大 1 件です。

リクエスト:

    {
      "mood": "fire",
      "activity": "game",
      "note": "30分だけ",
      "duration_min": 30,
      "source": "manual"
    }

200 OK は GET /hima/me と同じ形式です。duration_min は上記 5 種のみ受け付け、expires_at はサーバー受理時刻を基準に設定します。有効な宣言中の PUT は session_id と started_at を維持して内容と期限を更新します。この延長では同じセッションペアを再通知しません。source は必須入力ですが、延長時は最初のセッション作成時の値を維持します。宣言がない場合は新しい session_id を発行し、再マッチ判定します。

### DELETE /hima/me

宣言を終了します。200 OK:

    {
      "ended_session_id": "hima_01JCV9R4M5Q8",
      "ended_at": "2026-11-16T12:10:00Z"
    }

宣言がない場合も成功とし、ended_session_id は null です。終了後に再宣言すると新しい session_id になります。

### GET /hima

現在ヒマな友達を返します。quiet も一覧に含みます。双方が公開中の共通サーバー経由で見える相手に限り、いずれかが相手をマッチング対象外にしているペアは含めません。同じ activity、次にどちらかが any の相手を先に並べます。同順位は expires_at 昇順です。他人の source は含めません。

200 OK:

    {
      "hima": [
        {
          "session_id": "hima_01JCVB1AB2CD",
          "user": {
            "id": "345678901234567890",
            "display_name": "みな",
            "avatar_url": null
          },
          "mood": "quiet",
          "activity": "chat",
          "note": "聞き専かも",
          "duration_min": 60,
          "started_at": "2026-11-16T12:01:00Z",
          "expires_at": "2026-11-16T13:01:00Z",
          "guild_ids": ["234567890123456789"]
        }
      ]
    }

## マッチ

### GET /matches?since={UTC timestamp}

since は任意です。指定時は created_at > since の記録を返し、省略時は現在有効な宣言セッション同士のマッチを返します。activity の一致度を優先して並べます。マッチは自分の session と相手の session のペアで特定します。

200 OK:

    {
      "matches": [
        {
          "my_session_id": "hima_01JCV9R4M5Q8",
          "other_session_id": "hima_01JCVB1AB2CD",
          "kind": "fire_ok",
          "other_user": {
            "id": "345678901234567890",
            "display_name": "みな",
            "avatar_url": null
          },
          "other_hima": {
            "mood": "ok",
            "activity": "game",
            "note": null,
            "expires_at": "2026-11-16T13:01:00Z"
          },
          "created_at": "2026-11-16T12:01:00Z"
        }
      ]
    }

kind と表示・通知対象は次のとおりです。

| kind | 対象と表示文 |
| --- | --- |
| fire_fire | 双方。「二人とも今すぐ遊びたい！」 |
| fire_ok | fire 側のみ。「誘えば来る人がいるよ」 |
| ok_ok | 双方。「お互い誘われ待ちだよ」 |

quiet を含む組み合わせはマッチ・通知しません。候補が複数なら同じ activity、次に any を優先しますが、該当する全候補を返します。マッチの一意性は順序を問わない session ID のペアで、同一ペアを再通知しません。終了・失効後に新 session ID で再宣言した場合は再度マッチ可能です。相手の source は含めません。

## ノック

template と本文の対応は固定です: game = 「ゲームしない？」、chat = 「ちょっと話さない？」、work = 「作業通話しない？」。status は pending / accepted / later / passed で、日本語表示は「返事待ち」/「いいよ！」/「あとで」/「今回はパス」です。

### POST /knocks

現在ヒマで、可視の共通サーバーにいる相手に送ります。サーバーは可視の共通サーバーから送信先を選びます。ブロック中・非公開・条件不一致の相手は 404 not_found とし、存在を推測できないようにします。

リクエスト:

    {
      "to_user_id": "345678901234567890",
      "template": "game"
    }

201 Created:

    {
      "knock": {
        "id": "knock_01JCVB9XYZ12",
        "from_user": {
          "id": "123456789012345678",
          "display_name": "あつまろユーザー",
          "avatar_url": null
        },
        "to_user": {
          "id": "345678901234567890",
          "display_name": "みな",
          "avatar_url": null
        },
        "guild": {
          "id": "234567890123456789",
          "name": "週末ゲーム部"
        },
        "template": "game",
        "message": "ゲームしない？",
        "recipient_note": "スルーしてOK",
        "status": "pending",
        "created_at": "2026-11-16T12:02:00Z",
        "responded_at": null,
        "result_seen_at": null
      }
    }

送信時点で相手が quiet なら recipient_note は必ず「スルーしてOK」、それ以外は null です。アプリも quiet の相手への送信確認に同じ文言を表示します。

### GET /knocks/inbox

自分宛てを新しい順に返します。200 OK:

    {
      "knocks": [
        {
          "id": "knock_01JCVB9XYZ12",
          "from_user": {
            "id": "123456789012345678",
            "display_name": "あつまろユーザー",
            "avatar_url": null
          },
          "guild": {
            "id": "234567890123456789",
            "name": "週末ゲーム部"
          },
          "template": "game",
          "message": "ゲームしない？",
          "recipient_note": "スルーしてOK",
          "status": "pending",
          "created_at": "2026-11-16T12:02:00Z",
          "responded_at": null
        }
      ]
    }

### GET /knocks/sent

自分が送ったものを新しい順に返します。相手を to_user として返し、result_seen_at を含みます。応答済みで result_seen_at が null のものが未確認です。200 OK:

    {
      "knocks": [
        {
          "id": "knock_01JCVB9XYZ12",
          "to_user": {
            "id": "345678901234567890",
            "display_name": "みな",
            "avatar_url": null
          },
          "guild": {
            "id": "234567890123456789",
            "name": "週末ゲーム部"
          },
          "template": "game",
          "message": "ゲームしない？",
          "recipient_note": null,
          "status": "accepted",
          "created_at": "2026-11-16T12:02:00Z",
          "responded_at": "2026-11-16T12:04:00Z",
          "result_seen_at": null
        }
      ]
    }

### POST /knocks/{id}/respond

受信者が pending のノックに応答します。リクエストは {"response": "accepted"}。response は accepted / later / passed のいずれかです。200 OK は id、更新後の status、responded_at を返します。送信者へ結果通知を行います。すでに応答済みなら 409 conflict です。

200 OK の例:

    {
      "id": "knock_01JCVB9XYZ12",
      "status": "accepted",
      "responded_at": "2026-11-16T12:04:00Z"
    }

### POST /knocks/{id}/seen

送信者が応答結果を確認した時に呼びます。本文なし。200 OK:

    {"id": "knock_01JCVB9XYZ12", "result_seen_at": "2026-11-16T12:05:00Z"}

送信者以外、pending、または参照できないノックは 404 not_found です。ブロック中の相手とのノックは双方の一覧・通知から除外します。ブロック時にペア間の pending ノックを無効化し、以後応答・通知しません。ブロックした事実は相手に通知しません。

## マッチング対象外の相手

画面上の表記は「この人とはマッチングしない」です。対象者へ設定した事実を通知しません。

### GET /blocks

自分が設定した相手を返します。200 OK:

    {
      "blocks": [
        {
          "user": {
            "id": "345678901234567890",
            "display_name": "みな",
            "avatar_url": null
          },
          "created_at": "2026-11-16T12:06:00Z"
        }
      ]
    }

### POST /blocks

リクエストは {"user_id": "345678901234567890"}。自分自身は指定できません。201 Created:

    {"user_id": "345678901234567890", "created_at": "2026-11-16T12:06:00Z"}

すでに登録済みの場合も既存登録を返す冪等操作です（新規作成は 201 Created、既存の場合は 200 OK）。

### DELETE /blocks/{user_id}

自分が登録した設定を解除します。200 OK:

    {"user_id": "345678901234567890", "blocked": false}

いずれか一方が相手を対象外にしたら、双方の友達一覧、マッチ、ノック、通知から相手を除外します。解除できるのは設定した側だけです。対象者へ設定・解除を伝えません。

## デバイス

### PUT /devices

FCM token を登録・更新します。同じ利用者と platform の登録を置き換えます。

リクエスト:

    {"platform": "android", "fcm_token": "fcm_registration_token"}

platform は android / ios。200 OK:

    {"registered": true, "platform": "android", "updated_at": "2026-11-16T12:07:00Z"}

## 定期的なヒマ時間

### GET /regular-slots

200 OK:

    {"slots": [{"weekday": 5, "start_min": 1080, "end_min": 1320}]}

### PUT /regular-slots

全スロットを置き換えます。空配列は全削除です。start_min と end_min は 0〜1440 の範囲で start_min < end_min とします。日をまたぐ時間は曜日ごとに分割します。曜日・範囲の不正や重複は 400 validation_error です。

リクエストと 200 OK の形式:

    {
      "slots": [
        {"weekday": 5, "start_min": 1080, "end_min": 1320},
        {"weekday": 6, "start_min": 600, "end_min": 720}
      ]
    }

## ヒマ時間の提案

### GET /suggestions/hima-times

過去の自分の宣言から、曜日と時間ごとの宣言しやすさをサーバー側で算出します。Asia/Tokyo 基準、likelihood は 0.0〜1.0。履歴が足りない場合は空配列です。

200 OK:

    {
      "suggestions": [
        {"weekday": 5, "hour": 20, "likelihood": 0.82}
      ]
    }

weekday は月曜 0〜日曜 6、hour は 0〜23 です。アプリ側で学習・再計算しません。

## 公開範囲とプライバシー

- 判定対象は有効期限内の宣言です。fire × fire は双方、fire × ok は fire 側、ok × ok は双方に前述の kind を作成します。
- quiet は友達一覧には表示しますが、自動マッチせず、マッチ通知も送りません。
- 同じ activity、次にいずれかが any のペアを優先します。activity が異なり双方 any でないペアもマッチ対象です。
- 共通サーバーで双方が visible の場合だけ、そのサーバー経由の一覧・マッチ・ノックを表示します。
- 片側だけの対象外設定でも相互に隠し、一覧・マッチ・ノック・通知から除外します。誰が設定したかを相手に知らせません。
- 他人の source は全レスポンス・通知から除外します。source は本人向けの GET /hima/me と PUT /hima/me に限り返します。
- アプリはフォアグラウンド中、約 30 秒ごとに一覧・マッチ・ノックを再取得します。push 対応後も公開範囲とブロック判定は同じ規則を適用します。

