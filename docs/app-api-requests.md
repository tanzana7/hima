# アプリから API への追加お願い

正本は `docs/api-contract.md`。この文書は、Flutter アプリ（`app/`）をつなぐうえで正本に足りないものだけをまとめた依頼リスト。
採用されたら正本へ移し、この文書からは消す。

アプリ側は、ここに書いた形を前提に実装する。エンドポイントがまだ無い間（404 のとき）は、既存の `/app/me` と `/app/board` から作れる範囲で表示する。

## 1. 不具合：`POST /app/knocks/{id}/reply` が `user_id` を必須にしている（優先度 高）

- アプリ用のルートが、Bot 用の `ReplyIn`（`user_id` と `action`）を使い回している。そのため、契約どおり `{action}` だけを送ると 422 になる。
- お願い：アプリ用に `{action}` だけを受ける入力スキーマを作る。Bot 側は `body.user_id` を使っているので、共用の `ReplyIn` は変えない。
- それまでの間、アプリは自分の `user_id` も一緒に送る（API は JWT のユーザーを使うので、送った値は無視される想定）。

## 2. `GET /app/members`：共有サーバーのメンバー一覧（優先度 高）

- 使う場所：友達タブ（ひまじゃない人も含めて、サーバーごとに表示する）と、ブロックを追加するときの相手の候補。
- `/app/board` には宣言中の人しか出ないので、この2つの画面を作れない。
- 対象は `memberships` にいる人（Bot かアプリを一度でも使った人）でかまわない。Discord サーバーの全員を取る必要はない。
- 自分と、ブロック関係（どちら向きでも）にある人は含めない。

```json
{
  "guilds": [
    {
      "guild_id": 123,
      "name": "いつものメンバー",
      "visible": true,
      "members": [
        { "user_id": 456, "display_name": "あき", "avatar": "https://cdn.discordapp.com/avatars/..." }
      ]
    }
  ]
}
```

- 宣言中かどうかは、アプリが `/app/board` と `user_id` で突き合わせるので、ここには含めなくてよい。
- `visible=false` のサーバーも返す。アプリ側で「非表示」と表示する。

## 3. `GET /app/blocks` に相手の名前とアイコンを付ける（優先度 中）

- 今は ID の配列だけ返している。ブロックした相手は掲示板にも出ないので、アプリでは名前を表示できない。
- お願い：`{"blocked": [{"user_id", "display_name", "avatar"}]}` の形にする。今の `blocked: [id]` をどう変えるかは、Bot に影響しない形で決めてください。

## 4. `GET /app/knocks/sent`：自分が送ったノックの履歴（優先度 中）

- 使う場所：ノック画面の「送信」タブ。今の `/app/board` の `results` は「返答済みで未読」のものしか返さないので、返事待ちや既読のノックが見えない。
- 範囲は直近24時間か最新20件くらいで十分。

```json
{
  "knocks": [
    {
      "id": 1, "to_user_id": 456, "to_display_name": "あき", "to_avatar": null,
      "template": "ゲームしない？", "status": "sent",
      "created_at": "2026-11-17T12:00:00+09:00", "responded_at": null, "result_seen_at": null
    }
  ]
}
```

## 5. `/app/board` の行と受信箱に `avatar` を付ける（優先度 低）

- 友達カードやノックにアイコンを出すため。今はアプリが頭文字で代わりに表示している。

## 頼まないこと（アプリ側で対応する）

- **マッチングカード**：`/app/me` の自分の宣言と、`/app/board` の行の mood から、アプリで組み立てる（🌙 は除く）。
- **返答結果の既読**：アプリは `results` を受け取った時点で手元のキューに入れ、`POST /app/knocks/results/seen`（一括）を呼ぶ。キューから1件ずつお祝い表示を出すので、ID ごとに既読にする API は要らない。
- **自動宣言**：今回は設定の保存（`auto_mode` / `auto_mood`）までにする。実際に宣言するのは、Android での X 利用の検出を作るときに、アプリから `source=auto` で `POST /app/sessions` を呼ぶ。サーバー側で regular_slots をもとに自動で宣言する機能は、今はいらない。
- **activity を選ばなかったとき**：アプリが `any` として送る。
