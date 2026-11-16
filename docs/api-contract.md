# Atsumaro API 契約書（api-contract）

この文書は Atsumaro API とクライアント（Discord Bot / アプリ）の間の契約です。
語彙は厳守し、新規追加はこの文書の更新とセットで行います。

## 1. 語彙（固定キー）

### mood（hima_sessions.mood / users.auto_mood）— 3種固定

| key | 絵文字 | 意味 |
| --- | --- | --- |
| `fire` | 🔥 | 誘う人（自分から誘う） |
| `ok` | 🙂 | 誘われ待ち（既定値） |
| `moon` | 🌙 | 静か（掲示板には出るが、マッチング通知は一切受けない） |

※ 旧Botの内部キー `fire`/`ok`/`quiet` は `fire`/`ok`/`moon` に読み替える。

### activity（hima_sessions.activity）— 既存Botから継承・5種固定

| key | 表示 |
| --- | --- |
| `game` | 🎮 ゲーム |
| `chat` | 💬 雑談・通話 |
| `work` | 💻 作業通話 |
| `out` | 🚶 外出 |
| `any` | ✨ なんでもOK |

### hima_sessions.source — 宣言元

| key | 意味 |
| --- | --- |
| `panel` | Discord の公開パネルから |
| `command` | Discord のスラッシュコマンドから |
| `app` | アプリから |
| `auto` | regular_slots（よくヒマになる時間帯）による自動宣言 |

### matches.kind — マッチングの役割組み合わせ

| key | 意味 |
| --- | --- |
| `fire_fire` | 🔥×🔥 両方に通知 |
| `fire_ok` | 🔥×🙂 🔥 側にのみ通知 |
| `ok_ok` | 🙂×🙂 両方に通知 |

※ `moon`（🌙）はマッチング対象外。ブロック関係にあるペアも対象外。

### knocks.status — ノックのライフサイクル

`sent` → `accepted` / `later` / `passed`（返答で遷移）。未返答のまま当事者の有効セッションが消えたら `expired`。

### knocks.template — 誘い文（key は activity キーと一致）

| key | 文面 |
| --- | --- |
| `game` | ゲームしない？ |
| `chat` | ちょっと話さない？ |
| `work` | 作業通話しない？ |

## 2. 認証

- **Bot→API**：`Authorization: Bearer <BOT_API_SECRET>`。この検証を通ったリクエストのみ、ボディ／ヘッダーで渡された Discord ユーザーID を信用できる
- **アプリ→API**：API 独自のセッショントークン = JWT（HS256、`API_JWT_SECRET`、有効期限30日）。`sub` にユーザーID。OAuth コード交換エンドポイントは次段で追加

## 3. 実装済みエンドポイント

| Method | Path | 概要 |
| --- | --- | --- |
| GET | `/health` | 疎通確認。DB 接続込みで 200 を返す |
| GET | `/bot/ping` | Bot→API 認証の動作確認（シークレット必須） |

## 4. 予定エンドポイント（次段実装・この契約の対象）

### Bot→API（`Authorization: Bearer <BOT_API_SECRET>`）

| Method | Path | 概要 |
| --- | --- | --- |
| POST | `/bot/users` | ユーザー upsert（表示名・アバター） |
| POST | `/bot/guilds` | ギルド upsert |
| POST | `/bot/memberships` | メンバーシップ upsert（visible/last_seen_at） |
| POST | `/bot/sessions` | ヒマ宣言（有効セッションの作成／延長。source 付き） |
| DELETE | `/bot/sessions/current` | ヒマ解除（ended_at を書く） |
| GET | `/bot/guilds/{guild_id}/board` | 掲示板データ（ブロック不可視・🌙含む）をBotに返す |
| POST | `/bot/blocks` | ブロック登録／解除 |
| POST | `/bot/knocks` | ノック作成（クールダウン判定込み） |
| POST | `/bot/knocks/{id}/status` | 返答ステータス更新（responded_at 記録） |
| POST | `/bot/matches` | マッチング判定の実行（Botの登録イベントから） |
| POST | `/bot/devices` | FCM トークン登録（代替：アプリ経由） |

### アプリ→API（`Authorization: Bearer <app token>`）

| Method | Path | 概要 |
| --- | --- | --- |
| POST | `/auth/discord/code` | OAuth コード交換→JWT 発行（次段） |
| GET | `/me` | 自分の情報・設定取得 |
| PATCH | `/me` | 表示名・auto_mode / auto_mood / notify_on_hima 更新 |
| GET | `/guilds/{guild_id}/board` | 掲示板詳細（ブロック反映つき） |
| POST | `/sessions` | ヒマ宣言（source=app） |
| DELETE | `/sessions/current` | ヒマ解除 |
| GET | `/knocks/inbox` | 自分宛の未返答ノック |
| POST | `/knocks/{id}/respond` | ノック返答（accepted/later/passed） |
| GET | `/knocks/results` | 自分が送ったノックの未閲覧結果（取得で result_seen_at 更新） |
| PUT/DELETE | `/blocks/{user_id}` | ブロック登録／解除 |
| POST | `/devices` | FCM トークン登録（platform 付き） |
| DELETE | `/devices/{fcm_token}` | トークン削除 |
| GET/PUT | `/me/regular-slots` | よくヒマになる時間帯の取得／保存 |

## 5. 不変条件（サーバー側で強制）

- 有効セッション（`ended_at IS NULL`）はユーザーごとに1つまで（部分ユニークインデックス）。延長は同じ行の更新、終了→再宣言は新しい行
- `blocks` は双方向に効果を持つ（どちらか一方の行で成立）
- `matches` の (session_a_id, session_b_id) はユニーク（同じ登録同士で重複通知しないため）
- `moon` ユーザー・ブロック関係のペアはマッチング対象外
