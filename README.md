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

### デモモード

アプリの中から、すべての画面・シート・状態をモックデータで試せる開発者向けのモードです。ログイン画面の **「デモで見る」**、またはログイン後の **設定 → 「デモモード」** で入ります。デモ中は画面右下の丸いボタン（読み上げ名「デモパネルを開く」）からいつでも一覧を開けます（撮影モード中は出ません）。

- **サーバーには一切つながりません。** ログインはアプリ内のモックで、Discord の認可画面もトークンの保存・削除も行いません。
- **端末の実際の自動ひま提案の設定は変えません。** 有効・対象アプリ・宣言の期限・よくひまな時間はデモ用のメモリ上だけに保持され、終了時に破棄されます。
- デモパネルから出せる通知はデモ専用で、本文は実際の提案と同じまま「デモ」と表示されます。デモを終えると通知は取り消されます（予約した通知も含みます）。
- パネルの「通信エラー」は、友達リストを空にした状態で読み込みを失敗させるので、ホームのエラー表示がそのまま出ます。「遅い通信」で読み込み中の見た目も確認できます。
- **撮影モード**（パネルの「撮影」）はプロモーション動画の収録用です。オンにするとパネルが閉じてホームに戻り、右下の丸いボタンが消え、デモ通知の「デモ」表示も消えます（予約済みの通知も、すでに出ている通知も「デモ」なしに入れ替わります）。終えるときは画面左上（ロゴのあたり）を長押しします（読み上げ名「撮影モードを終える」）。ふだんのタップやスクロールは妨げません。
- 「10秒後に出す」をオンにすると、通知が10秒後に届くので、その間に YouTube などを開けます。予約は Android 側のタイマーで動くので、アプリを背面に回しても届きます（アプリを終了すると届きません）。
- リリースビルド（`API_BASE_URL` あり）ではデモの入口は表示されません。デバッグ・プロファイルビルドと、モックで動くビルドだけで使えます。

### 自動ひま提案（Android のみ）

設定でオンにすると、15分ごとのバックグラウンド確認で「いまひまじゃない？」とローカル通知を出します。宣言はしません。通知が出るのは、対象アプリ（既定は X と YouTube。追加・削除できます）を設定した利用時間以上使ったときと、いつものひまな時間帯（サーバーの予測と、端末が対象アプリの利用から学習した枠）に入ったときです。iOS では動きません。

対象アプリの提案は、直近「通知までの利用時間＋15分」の中で対象アプリが前面にあった時間の合計が、その利用時間（5分／15分／30分／1時間、既定は5分）以上になったときに出ます。複数の対象アプリを使っていれば合計します。開いた直後や、その範囲より前に終わった利用だけでは出ません。本文には、最後に使っていた対象アプリの名前が入ります。

使う権限は 2 つです。

- **使用状況へのアクセス**（`PACKAGE_USAGE_STATS`）: 対象アプリの利用時間を読むため。設定 → アプリ → 特別なアクセス権 → 使用状況へのアクセス で許可します。テスト中は `adb shell appops set jp.atsumaro.atsumaro GET_USAGE_STATS allow` でも許可できます。
- **通知**: Android 13 以降は実行時に許可を求めます。

Doze やメーカー独自のバッテリー制限で配信が遅れることがあります（フォアグラウンドサービスや正確なアラームは使わず、15分ごとの定期実行だけに頼っています）。Xiaomi / HyperOS では、設定で自動起動を許可し、バッテリーの制限を「制限なし」にしてください。

ワーカーは 15 分ごとの WorkManager の定期実行です。すぐに動きを確かめたいときは、JobScheduler に登録されたジョブを探して強制実行します。

```bash
# ジョブを探す（JOB androidx.work.systemjobscheduler:u0a533/4: ... jp.atsumaro.atsumaro の行に出ます）
adb shell dumpsys jobscheduler | grep -A3 jp.atsumaro.atsumaro

# Android 14 以降（WorkManager 2.10 以降）は名前空間付きのジョブなので -n が要ります
adb shell cmd jobscheduler run -f -n androidx.work.systemjobscheduler jp.atsumaro.atsumaro <job-id>

# Android 13 以前は名前空間がないので -n を付けません
adb shell cmd jobscheduler run -f jp.atsumaro.atsumaro <job-id>
```

実際に確かめた挙動は次のとおりです。

- ジョブは `SystemJobService` に登録されます。`<job-id>` は WorkManager が登録し直すたびに変わる（0 → 1 → 3 …）ので、毎回 `dumpsys` から読み直してください。`-n` を付けずに実行すると `Could not find job ...` になります。
- `run -f` は JobScheduler のジョブを即時起動しますが、**15 分の周期に達していない定期ワーカーは WorkManager 側が実行を見送ります**（logcat に `WM-WorkerWrapper: Delaying execution ... because it is being executed before schedule`）。実際に走るのは周期が来てからです。設定をオンにした直後の初回だけはすぐに実行されます。
- 実行されたかは `adb logcat -s WM-WorkerWrapper` と、デバッグビルドなら `adb shell run-as jp.atsumaro.atsumaro cat shared_prefs/hima_suggest.xml` の `lastRunAt` で確認できます。

見出し用フォント M PLUS Rounded 1c（SIL OFL 1.1）は `app/assets/fonts/` に同梱しており、実行時のフォント取得は行いません。ライセンスは同ディレクトリの `OFL.txt` です。
