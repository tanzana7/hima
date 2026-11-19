<p align="center"><img src="docs/images/icon.png" width="140" alt="hima. のアイコン"></p>

<h1 align="center">hima.</h1>
<p align="center"><b>いま、ひま？</b>　ひまを友達と共有して、気軽に遊びに誘えるアプリ</p>

「遊びたいけど、誘って断られたらどうしよう」「今は忙しいかも」。hima. は、そんな迷いをなくすためのアプリです。ひまなときに「いま、ひま」と宣言しておけば、同じくひまな友達が見つかり、そのまま気軽に誘えます。スマホアプリと Discord Bot のどちらからでも使え、状態は共有されます。

| ひまを宣言 | ひまの状態 | やりたいこと | ひまの長さ |
|:---:|:---:|:---:|:---:|
| <img src="docs/images/screen-off.png" width="190"> | <img src="docs/images/screen-on.png" width="190"> | <img src="docs/images/screen-activity.png" width="190"> | <img src="docs/images/screen-duration.png" width="190"> |

| 自動ひま提案の通知 | 自動ひま提案の設定 |
|:---:|:---:|
| <img src="docs/images/screen-notification.png" width="400"> | <img src="docs/images/screen-settings.png" width="190"> |

## 特徴
1. **誘う心理的なハードルを下げる**：ひまを共有している友達なら、断られる心配が少なく声をかけやすくなります。遊びたいのに誘えない問題を解消します。
2. **宣言の手間まで減らす（自動ひま提案）**：YouTube や X などを一定時間使い続けたときや、いつものひまな時間に、アプリが「いまひまじゃない？」と通知で提案します。通知の「ひまにする」ボタンひとつで宣言できます（Android）。
3. **Discord の友達とそのままつながる**：Discord でログインし、同じサーバーの仲間がそのまま友達になります。友達関係をゼロから作る必要はありません。
4. **Discord Bot からも使える**：普段使っている Discord から、ひまの宣言や確認ができます。
5. **「さそう」で気軽に誘える**：ひまな友達に「ゲームしない？」などを送るだけ。相手は「いいよ！ ／ あとで ／ パス」で返事します。見つけてから誘うまでがつながっています。
6. **アプリと Discord の両方に対応**：わかりやすいアプリと、手軽な Bot から、自分に合う方法を選べます。
7. **偶然の遊びの機会を増やす**：予定を立てるほどでもない「ちょっと遊ぼう」のきっかけを作ります。

## できること
### アプリ
- **ひまの宣言**：ホームの「いま、ひま？」で「ひまを宣言」。長押しで温度感を選べます（🙂 誘われたら行く ／ 🌙 ひっそり暇）。
- **やりたいこと**：ゲーム、雑談・通話、作業通話、外出、なんでもOK から選べます。
- **ひまの長さ**：15分〜12時間から選べます。時間が来るか「おわる」で終わります。
- **ひまな友達**：今ひまな友達と、その残り時間・やりたいことが並びます。サーバーごとに、自分を見せるかを選べます。
- **さそう**：ひまな友達に誘いを送れます。誘いは Discord の DM にも届き、DM のボタンからも返事ができます。
- **マッチ**：🙂同士がひまになると「お互い誘われ待ちだよ」と知らせます（アプリと Discord の DM）。
- **自動ひま提案（Android）**：対象アプリ（既定は X と YouTube。追加・削除できます）を設定した時間（5分・15分・30分・1時間）使い続けたときと、いつものひまな時間に通知します。勝手に宣言はしません。Discord の提案 DM と重ならないよう、「Discordでも受け取る」を選べます。
- **デモモード**：ログインなしで、全画面をモックのデータで試せます（下の「デモモード」）。

### Discord Bot
| コマンド・操作 | できること |
|---|---|
| `/panel 募集` | ひまを宣言します（時間・温度感・やりたいこと・ひとこと） |
| `/panel 確認` | 今ひまな人と自分の状態を見ます |
| `/panel 参加` | ひまな人に参加を申し込みます（誘い） |
| `/panel 取り消し` | 宣言を取り消します |
| 掲示板のボタン | 「ヒマ宣言する」「お返事する」「ブロック設定」 |
| DM | 誘いの着信（「いいよ！ ／ あとで ／ パス」で返事）、マッチのお知らせ、いつもの時間の提案（「このまま宣言する」） |

Bot の応答は、すべて自分だけに表示されます。

## 構成
```
Flutter アプリ ──┐
                 ├── API（FastAPI） ── PostgreSQL
Discord Bot ─────┘        └── ワーカー（期限切れ・マッチ・提案の DM）
```

| 場所 | 役割 |
|---|---|
| `app/` | Flutter アプリ（Android / iOS、表示名 `hima.`）。自動ひま提案は Android のネイティブ（Kotlin、WorkManager） |
| `api/` | FastAPI のサーバー。DB は PostgreSQL（SQLAlchemy、Alembic）。ワーカーも API のプロセス内で動く |
| `bot.py`、`views.py`、`api_client.py` | Discord Bot（discord.py）。API を通して状態を読み書きする |
| `docs/` | [API 契約書](docs/api-contract.md)、[アプリが必要とする API](docs/app-api-requests.md)、[デザイン仕様](docs/design/Design.md) |

## 動かし方（サーバーと Bot）
### 1. Discord の準備
[Discord Developer Portal](https://discord.com/developers/applications) でアプリケーションを作り、次を用意します。
- Bot のトークン（Privileged Intent はすべてオフで動きます）
- OAuth2 のクライアント ID とシークレット
- アプリのログイン用リダイレクト URI：`discord-<アプリケーションID>:/authorize/callback`
- `bot` と `applications.commands` のスコープを付けて、サーバーに Bot を招待する

### 2. データベース
```bash
docker compose up -d db
```

### 3. API
```bash
python -m venv .venv
# Windows: .venv\Scripts\activate / macOS・Linux: source .venv/bin/activate
pip install -r requirements.txt httpx fastapi "uvicorn[standard]" sqlalchemy "psycopg[binary]" alembic pydantic-settings "pyjwt[crypto]"
```

`api/.env` を作ります。

| 変数 | 説明 |
|---|---|
| `DATABASE_URL` | 既定は `postgresql+psycopg://postgres:postgres@localhost:5432/atsumaro` |
| `BOT_API_SECRET` | Bot と API の共有シークレット（ルートの `.env` と同じ値） |
| `API_JWT_SECRET` | アプリのログイン用 JWT の署名シークレット |
| `DISCORD_BOT_TOKEN` | Bot のトークン（DM の送信に使う） |
| `DISCORD_CLIENT_ID` / `DISCORD_CLIENT_SECRET` | OAuth2 のクライアント情報 |
| `FCM_SERVICE_ACCOUNT_JSON` | 任意。未設定ならプッシュ通知はログだけ（dry-run） |

```bash
cd api && alembic upgrade head && cd ..
uvicorn api.main:app --host 0.0.0.0 --port 8000
```

### 4. Discord Bot
`.env.example` をコピーして `.env` を作り、`DISCORD_TOKEN`、`API_BASE_URL`（例：`http://127.0.0.1:8000`）、`BOT_API_SECRET` を設定します。`DEV_GUILD_ID` を設定すると、そのサーバーにスラッシュコマンドがすぐ反映されます。

```bash
python bot.py
```

## アプリ（Flutter）

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
- **端末の実際の自動ひま提案の設定は変えません。** 有効・対象アプリ・宣言の期限・よくひまな時間はデモ用のメモリ上だけに保持され、終了時に破棄されます。「Discordでも受け取る」もモックの設定だけを変え、実際のアカウントには影響しません。
- デモパネルから出せる通知はデモ専用で、本文は実際の提案と同じまま「デモ」と表示されます。デモを終えると通知は取り消されます（予約した通知も含みます）。ボタンも本物と同じで、「ひまにする」はデモの状態のまま宣言し、「今はいい」は通知を消すだけです。デモは端末の実際の提案を止めません。
- パネルの「通信エラー」は、友達リストを空にした状態で読み込みを失敗させるので、ホームのエラー表示がそのまま出ます。「遅い通信」で読み込み中の見た目も確認できます。
- **撮影モード**（パネルの「撮影」）はプロモーション動画の収録用です。オンにしてパネルを閉じると右下の丸いボタンが消え、デモ通知の「デモ」表示も消えます（予約済みの通知も、すでに出ている通知も「デモ」なしに入れ替わります）。終えるときは画面左上（ロゴのあたり）を長押しします（読み上げ名「撮影モードを終える」）。ふだんのタップやスクロールは妨げません。
- 「10秒後に出す」をオンにすると、通知が10秒後に届くので、その間に YouTube などを開けます。予約は Android 側のタイマーで動くので、アプリを背面に回しても届きます（アプリを終了すると届きません）。
- リリースビルド（`API_BASE_URL` あり）ではデモの入口は表示されません。デバッグ・プロファイルビルドと、モックで動くビルドだけで使えます。

### 自動ひま提案（Android のみ）

設定でオンにすると、15分ごとのバックグラウンド確認で「いまひまじゃない？」とローカル通知を出します。宣言はしません。通知が出るのは、対象アプリ（既定は X と YouTube。追加・削除できます）を設定した利用時間以上使ったときと、いつものひまな時間帯（サーバーの予測と、端末が対象アプリの利用から学習した枠）に入ったときです。iOS では動きません。本文は、アプリ利用のときが「〈アプリ名〉 見てる？ 友達に知らせよう」、いつもの時間のときが「いつものひまな時間だよ。友達に知らせよう」です。

通知には **「ひまにする」** と **「今はいい」** の 2 つのボタンがあります。通知そのものをタップしたときは、これまでどおりアプリが開いて温度感を選んでから宣言します。

- **「ひまにする」**: アプリを開いて、選ばずにそのまま宣言します。温度感・活動・長さはホームのボタンと同じ既定（前回使った温度感（未選択なら 🙂）・選んでいる活動・既定の長さ）で、`source=suggested` です。宣言できたときはホームが宣言済みの表示になり、成功の知らせ（振動）も返ります。失敗したときは温度感の選択を開いて選び直せます。失敗したことは、その選択を閉じたあとに知らせます（選択のシートが画面下を覆うので、シートより先に出すと読まれません）。失敗しても通知は残るので、そのまま押し直すこともできます。すでに宣言中のときは何もしません。
- **「今はいい」**: アプリを開かずに通知を消し、2 時間すべての提案を止めます。止めているあいだも対象アプリの利用の学習は続くので、いつものひまな時間帯は失われません。

宣言が済むと、出ていた通知は取り下げます。通知は 30 分で自動的に消えるので、その時刻を過ぎた提案が残ることはありません。

自動ひま提案をオンにしているときだけ、設定に **「Discordでも受け取る」** が出ます。オフにすると、サーバーからの提案（Discord の DM とプッシュ通知）が届かなくなります。自動ひま提案をオンにしたときは同じ提案が二重に届かないよう既定でオフになり、自動ひま提案をオフに戻すとオンに戻ります。

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
