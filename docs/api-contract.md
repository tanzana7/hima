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

### activity（hima_sessions.activity）— 5種固定

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
| `manual` | 自分の意思での宣言（**Bot 経由の宣言は常に manual**） |
| `suggested` | サジェストからの宣言（次段の提案機能用） |
| `auto` | regular_slots（よくヒマになる時間帯）による自動宣言 |

### matches.kind — マッチングの役割組み合わせ

| key | 意味 |
| --- | --- |
| `fire_fire` | 🔥×🔥 両方にDM |
| `fire_ok` | 🔥×🙂 🔥 側にだけDM |
| `ok_ok` | 🙂×🙂 両方にDM |

※ `moon`（🌙）はマッチング対象外（宣言者・候補のどちらかが 🌙 なら成立しない）。ブロック関係にあるペアも対象外。`matches` は (session_a_id, session_b_id) の小さい方を a として保存し、同じペアの行が既にあれば温度感が変わっても再通知しない。1回の宣言で送るマッチ DM は最大3件（activity 一致の相手を優先）。

### knocks.status — ノックのライフサイクル

`sent` → `accept`/`later`/`pass` 返答で `accepted` / `later` / `passed`。未返答のまま（①当事者の有効セッションが消えた、②宛先が宣言解除した）場合は `expired`。同一ペア（双方向）のノックは5分クールダウン（409）。

### knocks.template — 誘い文（自由文字列。推奨は activity キーに対応する次の3種）

| key | 文面 |
| --- | --- |
| `game` | ゲームしない？ |
| `chat` | ちょっと話さない？ |
| `work` | 作業通話しない？ |

### 公開パネルのボタン custom_id（Discord components に埋め込む値）

| custom_id | ボタン |
| --- | --- |
| `atsumaro:board` | 掲示板を見る（押した本人にだけ詳細を表示） |
| `atsumaro:join` | 今ヒマ！ |
| `atsumaro:leave` | やめる |

### 共有メッセージの形式

- 人数メッセージ：`いま{n}人ヒマ`（n = visible な membership を持つ有効セッション中のユーザー数。宣言・解除の直後とワーカーtickで更新）
- パネルメッセージ：上記3ボタン付き

## 2. 認証

- **Bot→API**：`Authorization: Bearer <BOT_API_SECRET>`。この検証を通ったリクエストのみ、ボディ／ヘッダーで渡された Discord ユーザーID を信用できる。guild_id と user_id を含むリクエストでは membership が upsert され（last_seen_at 更新）、users 行が無ければ作られる
- **アプリ→API**：API 独自のセッショントークン = JWT（HS256、`API_JWT_SECRET`、有効期限30日）。`sub` にユーザーID。OAuth コード交換エンドポイントは次段で追加

## 3. 実装済みエンドポイント（すべて Bot 認証必須）

| Method | Path | 概要 |
| --- | --- | --- |
| GET | `/health` | 疎通確認。DB 接続込みで 200 を返す（認証不要） |
| GET | `/bot/ping` | Bot→API 認証の動作確認 |
| POST | `/bot/guilds/{guild_id}/setup` | guilds を upsert し、人数メッセージ＋パネルメッセージを REST 投稿して ID を保存 |
| POST | `/bot/guilds/{guild_id}/teardown` | 2つのメッセージを REST 削除（失敗は無視）し、メッセージID を NULL に |
| POST | `/bot/sessions` | ヒマ宣言（延長=同ID更新／新規は source=manual）。マッチング評価＋見守りキュー登録＋人数メッセージ更新 |
| DELETE | `/bot/sessions` | 有効セッション終了。宛ノックを expired に、人数メッセージを更新 |
| GET | `/bot/board?guild_id=&user_id=` | 閲覧者に見える有効セッション一覧（共有可視・ブロック除外・source非表示）＋宛ノック（最大5件、🌙関係で `to_moon=true`）＋未見結果 |
| POST | `/bot/knocks/results/seen` | 未見結果に `result_seen_at` を打つ |
| POST | `/bot/knocks` | ノック作成（相手が有効セッション中・共有可視・非ブロック必須。5分クールダウンは 409） |
| POST | `/bot/knocks/{id}/reply` | 返答（accept/later/pass）。to_user 本人のみ。status と responded_at を更新 |
| POST | `/bot/blocks` | ブロック登録（効果は双方向） |
| DELETE | `/bot/blocks` | ブロック解除 |
| GET | `/bot/blocks?user_id=` | 自分がブロックしているユーザー一覧 |
| PUT | `/bot/users/{user_id}/settings` | `notify_on_hima` の更新 |
| PUT | `/bot/memberships/visibility` | membership の visible 更新（人数メッセージを即更新） |
| GET | `/bot/guilds/{guild_id}/count` | 人数の取得（デバッグ用） |

## 4. データモデル（主要テーブル）

- `users`, `guilds`, `memberships`（PK: guild_id+user_id, visible, last_seen_at）
- `hima_sessions`（部分ユニークインデックスで有効セッション1人1つ。延長=同ID更新、終了→再宣言=新ID）
- `blocks`（blocker_id+blocked_id PK。双方向に効果：掲示板・マッチング・ノック・見守りすべてで不可視/対象外）
- `matches`（(session_a_id, session_b_id) ユニーク）
- `knocks`（status ライフサイクル上記。`responded_at` / `result_seen_at`）
- `devices`, `regular_slots`
- **`watch_queue`**（見守り通知キュー）：id, watcher_id, session_id, created_at, sent_at(nullable)。未送信行の部分インデックスあり

## 5. バックグラウンドワーカー（30秒tick・advisory lock）

- 期限切れセッションのクローズ（ended_at 書き込み）
- 全ギルドの人数メッセージ再計算・修正
- **3分ごと**：未送信 watch_queue を watcher ごとにまとめ1通の DM（「👀 ヒマな人が出たよ：名前…（n人）」）を送り sent_at を記録
- Discord REST は失敗時も例外を投げない（ログのみ）。テストでは `api.discord_rest.rest` をモックへ差し替え可能

## 6. 予定エンドポイント（次段：アプリ→API）

| Method | Path | 概要 |
| --- | --- | --- |
| POST | `/auth/discord/code` | OAuth コード交換→JWT 発行 |
| GET | `/me` / PATCH `/me` | 自分の情報・設定（auto_mode / auto_mood など） |
| GET | `/guilds/{guild_id}/board` | アプリ向け掲示板（/bot/board と同じ描画ルール） |
| POST | `/sessions` / DELETE `/sessions/current` | アプリからの宣言（source=app）/解除 |
| GET | `/knocks/inbox` / POST `/knocks/{id}/respond` / GET `/knocks/results` | アプリ側のノック受信箱・返答・結果 |
| PUT/DELETE | `/blocks/{user_id}` | アプリからのブロック操作 |
| POST/DELETE | `/devices` | FCM トークン管理 |
| GET/PUT | `/me/regular-slots` | よくヒマになる時間帯 |
