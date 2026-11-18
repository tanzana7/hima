# hima-bot（MVP）

サーバーの友達同士で「今ヒマ」を共有する Discord Bot。
パネルからヒマ宣言を登録すると、一覧メッセージが常に最新に保たれ、「ノック」でヒマな人をDMで誘えます。

> Botの表示名はDiscord Developer Portal側で設定されるため、コード内に製品名はハードコードしていません。
> パネル見出し等の表示名は `.env` の `BOT_DISPLAY_NAME`（未設定時は「今ヒマ！」）から読み込みます。

## 構成

| ファイル | 役割 |
| --- | --- |
| `bot.py` | 起動・スラッシュコマンド定義・30秒間隔の期限切れクリーンアップ |
| `storage.py` | SQLite（標準ライブラリ `sqlite3`）でのデータ操作 |
| `views.py` | パネルの永続View・登録画面・ノック画面・DM返答ボタン・Modal |
| `requirements.txt` | 依存パッケージ |
| `.env.example` | 環境変数のテンプレート |

- Python 3.11以上 / discord.py 2.x / python-dotenv
- Privileged Intent（Presence / Server Members / Message Content）は**すべてOFFで動作**します
- 外部DB・Web管理画面・Dockerは不要。DBはローカルの `data.db` のみ

## セットアップ

1. [Discord Developer Portal](https://discord.com/developers/applications) でアプリケーションを作成し、Botタブでトークンを取得する
   - **Privileged Intent はすべてOFFのままでOK**
2. OAuth2 > URL Generator で `bot` + `applications.commands` スコープを付け、サーバーに招待する
3. リポジトリ直下で依存をインストールする

   ```bash
   python -m pip install -r requirements.txt
   ```

4. `.env.example` をコピーして `.env` を作り、トークンを書く

   ```bash
   cp .env.example .env
   # .env を編集して DISCORD_TOKEN を設定
   ```

   | 変数 | 必須 | 説明 |
   | --- | --- | --- |
   | `DISCORD_TOKEN` | ✅ | Botトークン |
   | `DEV_GUILD_ID` | 任意 | 設定するとそのギルドへスラッシュコマンドを即時同期。未設定はグローバル同期（反映に最大1時間） |
   | `BOT_DISPLAY_NAME` | 任意 | パネル見出し等の表示名。未設定は「今ヒマ！」 |

5. 起動する

   ```bash
   python bot.py
   ```

   トークン未設定で起動すると、Tracebackではなく `DISCORD_TOKENが未設定です` と表示して終了します。

## 使い方

1. サーバー管理権限のある人が `/panel_setup` を実行 → 実行したチャンネルに「パネル」と「一覧」の2つのメッセージが投稿され、IDが保存される
2. パネルの **「今ヒマ！」**（または `/hima`）を押す → 自分だけに見える操作画面で
   - 時間：5分／15分／30分／1時間／3時間
   - 温度感：🔥今すぐ遊びたい／🙂誘われたら行く／🌙ひっそり暇
   - やりたいこと：🎮ゲーム／💬雑談・通話／💻作業通話／🚶外出／✨なんでもOK
   - 任意の「ひとこと追加」（50文字まで。ゲーム名などの用途）→ Modal

   を選び **「決定」** で登録。登録済みの人が再登録すると上書き（延長）される
3. 一覧メッセージはBotが編集して常に最新に保つ（表示名／温度感／やりたいこと／ひとこと／あと◯分。0人なら「今ヒマな人はいません」）
4. 期限が来るとバックグラウンドループ（30秒間隔）が登録を削除して一覧を更新する
5. **「やめる」** ボタンまたは `/hima_off` で自分の登録を解除。`/hima_list` で一覧をephemeral表示
6. パネルの **「ノックする」** を押す → ephemeral画面で
   - 今ヒマな相手（自分以外、最大25人）
   - 誘い文テンプレ（ゲームしない？／ちょっと話さない？／作業通話しない？）

   を選んで送信 → 相手へDMでノックが届き、DMには返答ボタン **「いいよ！／あとで／今回はパス」** が付く。押すとノックした人へDMで結果が通知され、`knock_log` の status も更新される
   - 同一ペアのノックは5分に1回まで（連打防止）
   - 相手のDMが閉じられている場合は送った人にその旨を通知

## データベーススキーマ（SQLite: `data.db`）

- `guild_config(guild_id PRIMARY KEY, channel_id, panel_message_id, list_message_id)`
- `hima_status(guild_id, user_id, display_name, started_at, expires_at, mood, activity, note, PRIMARY KEY(guild_id, user_id))`
- `knock_log(id INTEGER PRIMARY KEY AUTOINCREMENT, guild_id, from_user_id, to_user_id, template, status, created_at)`

## MVPでやらないこと

こっそりマッチング、同じゲーム同士の自動マッチング、人数募集、プレイ中ゲーム連携、よく暇になる時間帯の登録、複数サーバーをまたいだ友達リスト、課金・有料機能。

## Flutterアプリ

`app/` に Android / iOS 向け Flutter アプリ（表示名 `hima.`）があります。見た目と操作の仕様は [デザイン仕様](docs/design/Design.md)、API の契約は [API 契約書](docs/api-contract.md) を参照してください。

### モックで動かす

`--dart-define` を付けなければ、通信はすべてアプリ内のモックが返します（サーバー不要）。

```bash
cd app
flutter run
```

### 実 API につなぐ

`API_BASE_URL`（サーバーのルート）と `DISCORD_CLIENT_ID` を渡します。

```bash
# Android エミュレータ（ホストの localhost は 10.0.2.2）
flutter run \
  --dart-define=API_BASE_URL=http://10.0.2.2:8000 \
  --dart-define=DISCORD_CLIENT_ID=123456789012345678

# 実機（同じネットワークの PC かトンネル URL を指定）
flutter run \
  --dart-define=API_BASE_URL=https://xxxx.ngrok-free.app \
  --dart-define=DISCORD_CLIENT_ID=123456789012345678
```

ログインは Discord の認可コード + PKCE（S256）です。Developer Portal の OAuth2 > Redirects に次の URL を登録してください（`<CLIENT_ID>` は自分のクライアント ID）。

```
discord-<CLIENT_ID>:/authorize/callback
```

Android のコールバック用スキームは Gradle が `DISCORD_CLIENT_ID` から埋め込みます（`android/app/build.gradle.kts` の manifest placeholder）。iOS は `flutter_web_auth_2` が `ASWebAuthenticationSession` を使うため Info.plist への追加は不要です。取得したトークンは `flutter_secure_storage` に保存し、次回起動時に `/app/me` が通ればそのままメイン画面を開きます。

### 自動ひま提案（Android のみ）

設定でオンにすると、15分ごとのバックグラウンド確認で「いまひまじゃない？」とローカル通知を出します。宣言はしません。通知が出るのは、対象アプリ（既定は X と YouTube。追加・削除できます）を使っているときと、いつものひまな時間帯（サーバーの予測と、端末が対象アプリの利用から学習した枠）に入ったときです。iOS では動きません。

使う権限は 2 つです。

- **使用状況へのアクセス**（`PACKAGE_USAGE_STATS`）: 対象アプリの利用時間を読むため。設定 → アプリ → 特別なアクセス権 → 使用状況へのアクセス で許可します。テスト中は `adb shell appops set jp.atsumaro.atsumaro GET_USAGE_STATS allow` でも許可できます。
- **通知**: Android 13 以降は実行時に許可を求めます。

Doze やメーカー独自のバッテリー制限で配信が遅れることがあります（フォアグラウンドサービスや正確なアラームは使わず、15分ごとの定期実行だけに頼っています）。Xiaomi / HyperOS では、設定で自動起動を許可し、バッテリーの制限を「制限なし」にしてください。

ワーカーをすぐ実行して確かめるには、JobScheduler のジョブ ID を調べて強制実行します。WorkManager は定期ワーカーを JobScheduler のジョブとして登録する（サービスは `SystemJobService`）ので、この方法で即時に走ります。

```bash
# job-id を探す（JOB #u0a123/42: ... jp.atsumaro.atsumaro のような行に出ます）
adb shell dumpsys jobscheduler | grep -A3 jp.atsumaro.atsumaro
adb shell cmd jobscheduler run -f jp.atsumaro.atsumaro <job-id>
```

`run -f` は制約や遅延を無視して実行するので、条件が揃っていればこのタイミングで通知が出ます。ジョブが見つからないときは、設定で一度オンにしてから（`setEnabled` が WorkManager に登録します）確認し直してください。

見出し用フォント M PLUS Rounded 1c（SIL OFL 1.1）は `app/assets/fonts/` に同梱しており、実行時のフォント取得は行いません。ライセンスは同ディレクトリの `OFL.txt` です。
