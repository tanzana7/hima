# Atsumaro API 契約書（api-contract）

この文書は Atsumaro API とクライアント（Discord Bot / アプリ）の間の契約です。
語彙は厳守し、新規追加はこの文書の更新とセットで行います。

## 1. 語彙（固定キー）

### mood（hima_sessions.mood / users.auto_mood）— 2種固定（**fire は廃止。アプリ側の追随が必要な変更**）

| key | 絵文字 | 意味 |
| --- | --- | --- |
| `ok` | 🙂 | 誘われ待ち（既定値） |
| `moon` | 🌙 | ひっそり（掲示板には出るが、マッチング通知は一切受けない） |

※ `fire`（🔥 誘う人）は廃止。宣言 API（Bot／アプリ共通）で `mood=fire` は **400**。users.auto_mood が fire の既存行はマイグレーションで ok に寄せた。旧データの fire 有効セッションは ok として扱われる

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

### matches.kind — マッチングの役割組み合わせ（fire 廃止により ok_ok のみ）

| key | 意味 |
| --- | --- |
| `ok_ok` | 🙂×🙂 両方にDM |

※ `moon`（🌙）はマッチング対象外（宣言者・候補のどちらかが 🌙 なら成立しない）。旧 fire 行（matches の過去データ）はそのまま残す。ブロック関係にあるペアも対象外。`matches` は (session_a_id, session_b_id) の小さい方を a として保存し、同じペアの行が既にあれば温度感が変わっても再通知しない。1回の宣言で送るマッチ DM は最大3件（activity 一致の相手を優先）。

### knocks.status — ノック（**ユーザー向け呼称は「お返事」**。API 名・custom_id・テーブル名は不変）のライフサイクル

誘い文なしでも送れる（`template` は NULL。着信 DM は「{送信者} さんからお返事が届いたよ」の形）。

`sent` → `accept`/`later`/`pass` 返答で `accepted` / `later` / `passed`。未返答のまま（①当事者の有効セッションが消えた、②宛先が宣言解除した）場合は `expired`。同一ペア（双方向）のノックは5分クールダウン（409）。

**accepted 返答時の送信者 DM**：返答が `accepted`（「いいよ！」）に遷移したときだけ、送信者へ DM を 1 通送る（文面：`{返答者} さんがお返事に『いいよ！』してくれたよ`・ボタンなし・通知のみ）。`later` / `passed` では送らない（結果欄での表示は現行どおり）。入口（Bot の DM ボタン／掲示板の受信箱／アプリ）によらず domain 層の返答処理で発火するため同じ挙動。送信者が 🌙 のセッションを持っていても送る（着信 DM の 🌙 宛抑制とは扱いを分ける）。DM 送信に失敗しても返答処理自体は成功扱い（ログのみ）。accepted への遷移は 1 回だけなので二重送信は起こらない（既に返答済みへの再返答は 409）。

### ノック着信 DM（🌙 を除く）

- ノック作成が成功したら、宛先ユーザーへ DM を送る（送信は API サーバー側＝domain のノック作成処理から Discord REST で行う。**Bot 経由・アプリ経由どちらのノックでも同じ挙動**）
- 文面：`🚪 {送信者} さんからノック：「{テンプレ}」` ＋送信者が宣言中なら `{温度感絵文字} {やりたいこと} 中・あと{n}分` の行
- DM には返答ボタン3つ（いいよ！／あとで／パス）を付ける。custom_id は掲示板受信箱と同じ `atsumaro:knockreply:{knock_id}:{accept|later|pass}`（Bot 側 DynamicItem を流用）
- **例外**：宛先が現在 🌙（moon）の有効セッションを持つ場合は DM を送らない（🌙 は通知を受けない役割。受信箱で見る形のまま）
- 送信成功時は `knocks.dm_message_id` に保存（nullable）。DM が閉じられている等で失敗しても**ログのみでノック作成は成功**（受信箱に残る）
- 痕跡を残さないための削除：①Bot 側で DM の返答ボタンを押して返答が成功したら、その DM メッセージを Bot が削除する（掲示板 ephemeral 上のボタンは従来どおり・削除しない）。②ノックが expired になったとき（宛先の宣言解除・ワーカーによるセッション期限切れ）は、dm_message_id があれば API 側で DM を削除する（チャンネルは宛先との DM を開き直して特定）。削除後は dm_message_id を NULL にして再試行しない

### knocks.template — 誘い文（**nullable＝なし可**。自由文字列。推奨は activity キーに対応する次の3種）

| key | 文面 |
| --- | --- |
| `game` | ゲームしない？ |
| `chat` | ちょっと話さない？ |
| `work` | 作業通話しない？ |

### 個人用掲示板のボタン custom_id（Bot が components に埋め込む値）

| custom_id | ボタン |
| --- | --- |
| `atsumaro:knockreply:{knock_id}:{accept\|later\|pass}` | ノック返答（いいよ！／あとで／パス。DynamicItem・再起動後も有効） |
| `atsumaro:watchtoggle:{0\|1}` | **廃止**（お知らせ ON/OFF トグル。掲示板には付与しない。残存ボタンの押下では何も起きない） |
| `atsumaro:suggest:declare` | 提案 DM の「このまま宣言する」（押すと `POST /bot/suggest-declare` を呼び、source=suggested / 30分 / auto_mood（ok / moon 以外は ok にフォールバック）で宣言。DynamicItem・再起動後も有効） |
| `board:declare` / `board:knock` / `board:blocks` | 掲示板下部ボタン（Bot 内部用）。`board:knock` は掲示板が 0人のときは表示しない（旧 `board:leave`＝掲示板の「やめる」ボタンは廃止。宣言取り消しは /panel 取り消し） |

### 公開パネルのボタン custom_id（Discord components に埋め込む値）

| custom_id | ボタン |
| --- | --- |
| `atsumaro:board` | 掲示板を見る（押した本人にだけ詳細を表示） |
| `atsumaro:join` | 今ヒマ！ |
| `atsumaro:leave` | やめる |

※ トピック人数方式（人数をチャンネルトピックに表示）は一時採用後に不採用（revert: back to counter and panel messages）。guilds の base_topic / topic_counter 列は未使用のまま残置

### チャンネル内の常設メッセージ（廃止）

- **チャンネルに Bot の常設メッセージ（人数メッセージ・パネルメッセージ）は置かない**。人数の常時表示も廃止（現在地は `GET /bot/guilds/{id}/count` で確認可能）
- 操作の入口は **`/panel` コマンドグループの4サブコマンド（すべて ephemeral）のみ**：
  - `/panel 確認`：いま募集している人と自分の状態を見る（旧 /board と同一内容。掲示板＋受信箱＋ボタン群）
  - `/panel 募集`：募集をはじめる（温度感・やりたいこと・時間の選択フローを起動）
  - `/panel 取り消し`：募集を取り消す（未宣言なら「いまは募集していません」）
  - `/panel 参加 相手`：募集している人にノックで参加を申し込む（相手が募集していなければ「いまは募集していないみたいです」）
- **廃止したコマンド**：`/board`（/panel 確認 に統合）、`/panel_remove`（API の teardown エンドポイントは残る）、`/hima` / `/hima_off` / `/hima_list`
- `POST /bot/guilds/{id}/setup` はギルド登録のみ（メッセージは投稿しない）。`teardown` は旧パネル掃除用（ID 保存済みの常設メッセージ対が残っていれば削除）
- `guilds.list_message_id` / `panel_message_id` / `base_topic` / `topic_counter` は**未使用列**（マイグレーションはせず、今後書き込まない）
- 上記 `atsumaro:board/join/leave` は、残っている旧パネルが押された場合の受け口として永続登録だけ維持する（新規に投稿されることはない）
- トピック人数方式も一時採用後に不採用（revert: back to counter and panel messages → remove channel panel）

## 2. 認証

- **Bot→API**：`Authorization: Bearer <BOT_API_SECRET>`。この検証を通ったリクエストのみ、ボディ／ヘッダーで渡された Discord ユーザーID を信用できる。guild_id と user_id を含むリクエストでは **Guild → User → Membership の順で upsert する**。①guilds 行が無ければ作る（guild_name 指定時はその名前、無指定は仮名 `guild:<guild_id>`）。あれば `guild_name` が渡されていれば name を更新（仮名・空値では既存の本物の名前を上書きしない）。②users 行が無ければ作られる。③membership が upsert され（last_seen_at 更新）、guilds・users への外部キー制約は常に満たされる。**リクエストに `display_name` がある場合（Bot がインタラクションから渡した本物の表示名）、users.display_name をその値で更新する。ただし仮名（`discord:<ユーザーID>` 形式）・空値では既存の本物の名前を上書きしない**（表示名なしで作られた既存仮名行は、そのユーザーの次の Bot 操作で自己修復される。移行用マイグレーションはなし）。Bot は interaction からサーバー名（`interaction.guild.name`）を `guild_name` として渡す（宣言・掲示板取得・visibility）
- **アプリ→API**：API 独自のセッショントークン = JWT（HS256、`API_JWT_SECRET`、有効期限30日）。`sub` にユーザーID。`POST /auth/discord` で発行する。**全 `/app/*` エンドポイントで必須**。JWT から取得したユーザーIDのみを信用し、リクエストで送られた user_id は採用しない

## 3. 実装済みエンドポイント（すべて Bot 認証必須）

| Method | Path | 概要 |
| --- | --- | --- |
| GET | `/health` | 疎通確認。DB 接続込みで 200 を返す（認証不要） |
| GET | `/bot/ping` | Bot→API 認証の動作確認 |
| POST | `/bot/guilds/{guild_id}/setup` | guilds を upsert し、name と list_channel_id を記録する。**メッセージは一切投稿しない**（応答の counter_message_id / panel_message_id は常に null） |
| POST | `/bot/guilds/{guild_id}/teardown` | list_message_id / panel_message_id が残っていればその2件を REST 削除（失敗は無視）して NULL 化。旧パネル掃除用 |
| POST | `/bot/sessions` | ヒマ宣言（延長=同ID更新／新規は source=manual）。minutes は整数分（**5〜720 分を想定**。API は 1〜1440 にクランプ）。マッチング評価（**お知らせ＝watch 通知は廃止。誰にも通知がいかない**） |
| DELETE | `/bot/sessions` | 有効セッション終了。宛ノックを expired に |
| GET | `/bot/board?guild_id=&user_id=&display_name=&guild_name=` | 閲覧者に見える有効セッション一覧（共有可視・ブロック除外・source非表示）＋受信したお返事（最大5件。**`to_moon` は宛先＝受信者が現在🌙の有効セッションを持つときのみ true**）＋未見結果。レスポンスに `viewer.notify_on_hima` を含む（**現在は未使用**：お知らせ廃止のため値は互換用）。**guilds 行が無い新規サーバーでも、閲覧者の Guild → User → Membership upsert を行う**（行が無ければ visible=true で作成。既存行の visible は変更しない・last_seen_at のみ更新）。「掲示板を見ただけのユーザー」もお返事を送れるようになるための upsert（契約 §2 の guild_id＋user_id を含むリクエストの規則どおり）。`display_name` は任意。指定時は閲覧者の users.display_name を更新（仮名・空値では上書きしない） |
| POST | `/bot/knocks/results/seen` | 未見結果に `result_seen_at` を打つ |
| POST | `/bot/knocks` | ノック作成（相手が有効セッション中・共有可視・非ブロック必須。5分クールダウンは 409）。`display_name` は任意（送信者の users 行 upsert 用） |
| POST | `/bot/knocks/{id}/reply` | 返答（accept/later/pass）。`{user_id, action}`。to_user 本人のみ。status と responded_at を更新。**Bot 側は user_id 必須のまま（変更なし）** |
| POST | `/bot/blocks` | ブロック登録（効果は双方向） |
| DELETE | `/bot/blocks` | ブロック解除 |
| GET | `/bot/blocks?user_id=` | 自分がブロックしているユーザー一覧 |
| PUT | `/bot/users/{user_id}/settings` | `notify_on_hima` の更新（**現在は未使用**：お知らせ機能は廃止済みで、API はこの値を理由に通知を送らない。アプリ互換のため設定保存のみ残す）。`display_name` は任意（users upsert 用・仮名では上書きしない） |
| PUT | `/bot/memberships/visibility` | membership の visible 更新 |
| POST | `/bot/suggest-declare` | 提案 DM の「このまま宣言する」ボタン用。`{user_id}`。そのユーザーの auto_mood（ok / moon 以外は ok にフォールバック）/ activity=any / 30分 / source=suggested で宣言（マッチング・人数更新は通常宣言と同一）。応答は `/bot/sessions` と同じ形 |
| GET | `/bot/guilds/{guild_id}/count` | 人数の取得（デバッグ用） |

## 4. データモデル（主要テーブル）

- `users`（id=Discord ID, display_name, avatar, auto_mode, auto_mood, notify_on_hima, **suggest_dm**（既定 true／提案 DM・プッシュの許可。false なら提案ワーカーの対象外））, `guilds`, `memberships`（PK: guild_id+user_id, visible, last_seen_at）
- `hima_sessions`（部分ユニークインデックスで有効セッション1人1つ。延長=同ID更新、終了→再宣言=新ID）
- `blocks`（blocker_id+blocked_id PK。双方向に効果：掲示板・マッチング・ノックですべてで不可視/対象外）
- `matches`（(session_a_id, session_b_id) ユニーク）
- `knocks`（status ライフサイクル上記。`responded_at` / `result_seen_at`。着信 DM の `dm_message_id`（🌙 宛は NULL））
- `devices`, `regular_slots`（id, user_id, weekday 0=月〜6=日, start_min, end_min。demo フラグはダメ投入スクリプトの投入物を識別）
- `watch_queue`（**廃止・未使用**：お知らせ機能の廃止に伴い新規投入なし。テーブルは残置し、既存の未送信行は破棄済み）
- **`suggestion_log`**（提案送信記録）：id, user_id, slot_date（ローカル日付）, weekday, start_min, sent_at。(user_id, slot_date, start_min) ユニーク＝同じ枠・同じ日は1回だけ
- `hima_sessions.demo` / `regular_slots.demo`：`scripts/seed_demo_history.py` が投入したデモデータの識別用（`--reset` で demo=true の行だけ削除）

## 5.5 自由時間の推定と提案（Phase C）

### GET /app/free-time/forecast（JWT 必須）

- 過去8週間の終了済み hima_sessions を集計する（Python 側で素直に集計。キャッシュや専用テーブルは作らない）
- 曜日 × 30分刻みの枠ごとに「その曜日に宣言が枠と重なった日の数 ÷ その曜日が期間内にあった日数」をスコアにする
- スコア 0.5 以上かつ実績3日以上の枠を、連続する枠はマージして返す（タイムゾーンは Asia/Tokyo）
- 各枠に `basis` を付ける：`history`（集計のみ）／`manual`（regular_slots のみ）／`both`。manual のみの枠は score=0 / days=0
- 応答：`{user_id, slots: [{weekday, start_min, end_min, basis, score, days}]}`

### 提案（ワーカー）

- ワーカーは **15分ごと**（30秒tick × 30）に判定する
- いまが「forecast（history/manual/both いずれも）または regular_slots の枠の**開始15分前**」に当たるユーザーがいて、
  ①そのユーザーが宣言中でなく、②同じ枠・同じ日に suggestion_log の送信実績がなければ、提案を1回送る
- **除外条件：`users.suggest_dm = false` のユーザーは提案対象から除外する**（Discord DM も FCM プッシュも送らない。suggestion_log も書かないので、同じ枠の途中で true に戻せばその後のパスで送られる）
- 送信先：devices があればプッシュ（dry-run 可）。あわせて Discord DM も送る。DM には「このまま宣言する」ボタン（`atsumaro:suggest:declare`）を付ける。文面は「そろそろヒマな時間じゃない？ HH:MM 頃のあなたのいつもの時間だよ。このまま宣言する？」
- DM 送信は Discord REST 失敗でも例外を投げない（ログのみ）

### デモ用ダミー履歴（scripts/seed_demo_history.py）

- 実ユーザー2人（引数）＋ダミーユーザー3人（ID 990000000000000001〜003、表示名「デモ・みか／そら／かい」）
- 過去4週間分の終了済みセッションを投入：平日は22時台、週末は午後の偏り付き。mood / activity / source を混ぜる（source は manual 中心）
- 実ユーザー2人には regular_slots（平日22:00〜23:59）も登録
- `--reset` で demo=true の投入分だけを削除

## 5. バックグラウンドワーカー（30秒tick・advisory lock）

- 期限切れセッションのクローズ（ended_at 書き込み）＋当事者の未返答ノックを expired にし、着信 DM（dm_message_id 保存済み）を削除
- ~~3分ごと：未送信 watch_queue をまとめ送信~~（**廃止**。ワーカーは期限切れクローズと提案のみ）
- Discord REST は失敗時も例外を投げない（ログのみ）。テストでは `api.discord_rest.rest` をモックへ差し替え可能

## 6. アプリ向けエンドポイント（JWT 認証。`/auth/discord` のみ認証不要）

### Discord OAuth

| Method | Path | 概要 |
| --- | --- | --- |
| POST | `/auth/discord` | ボディ `{code, redirect_uri, code_verifier}`（PKCE）。Discord v10 `/oauth2/token` で交換（`DISCORD_CLIENT_ID`/`DISCORD_CLIENT_SECRET` は環境変数）→ `/users/@me` で users を upsert（`display_name` は global_name があればそれ、無ければ username。`avatar` は CDN URL `https://cdn.discordapp.com/avatars/{id}/{hash}.png`、hash 無しは null）→ `/users/@me/guilds` と guilds テーブルの**共通サーバーのみ** memberships を upsert（visible 既定 true、last_seen_at 更新）→ 第1段の JWT を発行し `{token, user, guilds}` を返す |

### アプリ本体（すべて JWT 必須。user_id は常に JWT から取得）

| Method | Path | 概要 |
| --- | --- | --- |
| GET | `/app/me` | プロフィール・設定（`suggest_dm` を含む）・**自分の有効セッション（source を含む）**・memberships 一覧 |
| PUT | `/app/me/settings` | `notify_on_hima` / `auto_mode` / `auto_mood` / `suggest_dm` の部分更新（未指定の項目は変更しない） |
| PUT | `/app/memberships/{guild_id}/visibility` | 自分の**既存 membership の visible 更新のみ**。membership が無い（自分が入っていないサーバー）場合は **404**（このエンドポイントでは新規作成しない。作成は OAuth の参加サーバー一覧と Bot interaction 由来のみ） |
| GET | `/app/board` | **横断掲示板**：自分が member の全サーバーを統合。共有可視・ブロック除外判定は Bot 側と同じ。各行に `shared_guild_ids`（共通の visible サーバーID一覧）と **`avatar`** を付ける。ノック受信箱（最大5件、`to_moon` 付き・**送信者の `from_avatar` 付き**）＋未見結果も返す。**他人のセッション行に source は含めない**（自分の行のみ `/app/me` で返す） |
| POST | `/app/sessions` | ヒマ宣言 `{mood, activity, note, minutes, source}`（source は manual/suggested/auto）。Bot 側と**同一のサービス関数**を使うためマッチングも同じに発火（お知らせは廃止） |
| DELETE | `/app/sessions` | 有効セッション終了（Bot 側と同一挙動） |
| POST | `/app/knocks` | ノック作成（from_user は JWT 本人） |
| POST | `/app/knocks/{id}/reply` | 返答（accept/later/pass）。**アプリ専用スキーマ `{action}` のみ**。返答者は JWT 本人から取得し、**リクエストボディの user_id は受理しない**（含めても無視されるため、別人のふりでの返答は不可能）。宛先本人（knock.to_user == JWT 本人）以外は 403 |
| GET | `/app/knocks/sent` | 自分が送ったノックの履歴（**新しい順**）。各行: `id` / `to_user` / `to_display_name` / `to_avatar` / `template`（null 可）/ `status` / `created_at` / `responded_at`（未返答は null） |
| POST | `/app/knocks/results/seen` | 未見結果に `result_seen_at` を打つ |
| GET | `/app/members` | **共有サーバーごとのメンバー一覧**。`guild_id` は任意クエリパラメータ。指定時はそのサーバーのメンバーのみ（サーバーが存在しない・または本人がそのサーバーの membership を持たない場合は **404**）。未指定時は本人が所属する全サーバーのメンバーを返す。各行: `user_id` / `display_name` / `avatar`（users の保存値・未保存は null）/ `guild_id`。**visible=true の membership のみ**を列挙（visible=false の自分は取得者になれるが一覧には出ない）。並び順は guild_id, user_id 昇順 |
| GET | `/app/blocks` | 自分がブロックしている一覧。**`blocked_users`（各行 `user_id` / `display_name` / `avatar`）を追加**。従来の `blocked`（ID一覧）は互換のため残す |
| POST | `/app/blocks` | ブロック登録 `{blocked_user_id}`（効果は双方向） |
| DELETE | `/app/blocks` | ブロック解除 |
| POST | `/app/devices` | FCM トークン upsert `{platform, fcm_token}`（updated_at 更新） |
| DELETE | `/app/devices` | FCM トークン削除 |
| GET | `/app/regular-slots` | 自分の登録済み時間帯一覧 `{id, weekday, start_min, end_min}` |
| POST | `/app/regular-slots` | 時間帯追加 `{weekday, start_min, end_min}`（weekday は 0=月曜〜6=日曜、分は 0〜1439、start < end を検証。違反は 400） |
| DELETE | `/app/regular-slots/{id}` | 自分の枠のみ削除可（存在しない・他人のは 404） |
| GET | `/app/free-time/forecast` | 自分のヒマ時間帯の推定（下記「自由時間の推定」参照） |

### プッシュ通知（FCM）

- `api/push.py` の `send_push` がマッチ成立時・ノック着信時・ノック返答時に、**相手が devices を持っていれば**送る
- `FCM_SERVICE_ACCOUNT_JSON`（サービスアカウント JSON のファイルパス）未設定なら **dry-run**：通知は送らず `[push dry-run] user=… devices=… title=… body=…` をログ出力するだけ（**ハッカソン期間の既定**）
- プッシュはどのような失敗（例外・HTTP エラー）でも**リクエストを失敗させない**（ログのみ）

### 実装上の注記

- 宣言・終了・マッチング・ノックのロジックは Bot / アプリで**同一のサービス層**（`api/domain.py`）を共有し、二重実装はない。Bot 側の外部仕様（パス・項目・ステータスコード）は不変
- `GET /bot/board` は `/bot/board`（単一ギルド版）と `/app/board`（横断版）で同じ除外ロジック（共有可視・ブロック）を共有
