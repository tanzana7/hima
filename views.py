"""UI parts for the Atsumaro bot (thin client over the Atsumaro API)."""
from __future__ import annotations

import functools
import logging
from typing import TYPE_CHECKING, Any

import discord
from discord import ui

from api_client import ApiConnectionError, ApiHTTPError

if TYPE_CHECKING:
    from bot import HimaBot

log = logging.getLogger("atsumaro.views")

MOOD_EMOJI = {"fire": "🔥", "ok": "🙂", "moon": "🌙"}
MOOD_OPTIONS = [("ok", "🙂 誘われ待ち"), ("moon", "🌙 ひっそり（マッチング通知なし）")]  # fire は廃止
ACTIVITY_LABELS = {"game": "ゲーム", "chat": "雑談・通話", "work": "作業通話", "out": "外出", "any": "なんでもOK"}
RESULT_LABELS = {"accepted": "いいよ！", "later": "あとで", "passed": "今回はパス"}
KNOCK_TEMPLATES = ["ゲームしない？", "ちょっと話さない？", "作業通話しない？"]
DURATIONS = [(15, "15分"), (30, "30分"), (60, "1時間"), (180, "3時間")]  # 既定 30分
CUSTOM_DURATION_VALUE = "custom"  # 5つ目の選択肢「時間を指定する…」（任意の分数を入力）
DURATION_PLACEHOLDER = "時間：あとどれくらいヒマ？（既定30分）"
DEFAULT_MINUTES = 30
NOTE_MAX = 50
CANDIDATE_LIMIT = 25
INBOX_LIMIT = 5

CONNECTION_ERROR_TEXT = "APIサーバーに接続できませんでした。しばらくしてからもう一度試してください。"
ERROR_FOLLOWUP_TEXT = "エラーが発生しました。しばらくしてからもう一度試してください。"
TEMPLATE_NONE = "__none__"  # 「誘い文なし」の select value（Discord は value に 1〜100 文字を要求するため空文字は不可）

# API detail（英語）をそのまま見せないための対応表（knock 系の既知エラー）
DETAIL_TEXTS_JA = {
    "no shared visible guild": "共通のサーバーで見える状態がないみたい。しばらくしてからもう一度試してね",
    "target has no active session": "その人はいま募集していないみたい",
    "invalid action": "返答の種類が正しくないみたい。もう一度試してね",
}


def friendly_api_detail(detail: str) -> str:
    """API の英語 detail を日本語の案内に置き換える（既知外はそのまま）。"""
    return DETAIL_TEXTS_JA.get(str(detail), str(detail))


def sort_candidates_active_first(candidates: list[dict]) -> list[dict]:
    """宛先候補を「募集中（有効な宣言がある）」人が先頭になるよう並べ替える。

    active キーがないもの（掲示板の sessions 行＝宣言中のみ）は active 扱い。
    それ以外の人は入力順（＝Discord のメンバー順）を維持する（安定ソート）。
    """
    return sorted(
        candidates,
        key=lambda s: (not s.get("active", True)),
    )


async def send_api_error(target, exc: Exception) -> None:
    """Show a friendly ephemeral message for API errors (never crash the flow)."""
    log.warning("api error: %s: %s", type(exc).__name__, exc)
    if isinstance(exc, ApiConnectionError):
        content = CONNECTION_ERROR_TEXT
    elif isinstance(exc, ApiHTTPError):
        if exc.status_code == 409:
            content = "さっき送ったばかりだよ！5分待ってからもう一度ね。"
        elif exc.status_code == 403:
            content = "その人には送れません。"
        else:
            content = f"エラーが発生しました: {friendly_api_detail(exc.detail)}"
    else:
        content = "予期しないエラーが発生しました。しばらくしてからもう一度試してください。"
    if target.response.is_done():
        await target.followup.send(content, ephemeral=True)
    else:
        await target.response.send_message(content, ephemeral=True)


async def send_error_followup(interaction: discord.Interaction, error: Exception, where: str = "") -> None:
    """defer 済み（考え中…のまま）で後段が失敗したとき、framework に握られる前に利用者へエラーを返す。"""
    log.error("interaction error %s: %s: %r", where, type(error).__name__, error)
    try:
        if interaction.response.is_done():
            await interaction.followup.send(ERROR_FOLLOWUP_TEXT, ephemeral=True)
        else:
            await interaction.response.send_message(ERROR_FOLLOWUP_TEXT, ephemeral=True)
    except Exception:  # noqa: BLE001 - エラー応答の送信自体の失敗は握る（ログのみ）
        log.exception("failed to send error followup")


class ErrorFollowupView(ui.View):
    """View 共通 on_error：component callback の例外を握らず、defer 後は followup で利用者に通知する。"""

    async def on_error(self, interaction: discord.Interaction, error: Exception, item: ui.Item, /) -> None:
        await send_error_followup(
            interaction, error, f"{type(self).__name__}.{getattr(item, 'custom_id', type(item).__name__)}"
        )


def guarded(callback):
    """DynamicItem 用：callback の例外を framework が握る前に受け止め、利用者へエラーを返す。"""

    @functools.wraps(callback)
    async def wrapper(self, interaction: discord.Interaction) -> None:
        try:
            await callback(self, interaction)
        except Exception as error:  # noqa: BLE001
            await send_error_followup(interaction, error, type(self).__name__)

    return wrapper


# ------------------------------------------------------------------ board render


def render_board(data: dict) -> list[discord.Embed]:
    sessions = data.get("sessions", [])
    board = discord.Embed(
        title=f"📜 掲示板（いま{len(sessions)}人）",
        description=_session_lines(sessions),
        color=discord.Color.green() if sessions else discord.Color.dark_grey(),
    )
    inbox_lines = []
    for k in data.get("inbox", []):
        line = f"・**{k['from_display_name']}** さんが「{k['template']}」"
        if k.get("to_moon"):
            line += "（スルーしてOK）"
        inbox_lines.append(line)
    inbox = discord.Embed(
        title="📬 お返事受信箱",
        description="\n".join(inbox_lines) if inbox_lines else "今は届いていないよ",
        color=discord.Color.gold(),
    )
    result_lines = [
        f"・**{k['to_display_name']}** さんの返事：「{RESULT_LABELS.get(k['status'], k['status'])}」（{k['template']}）"
        for k in data.get("results", [])
    ]
    results = discord.Embed(
        title="🔔 お返事の結果",
        description="\n".join(result_lines) if result_lines else "まだ結果はないよ",
        color=discord.Color.green(),
    )
    return [board, inbox, results]


def _session_lines(sessions: list[dict]) -> str:
    lines = []
    for s in sessions:
        line = (
            f"{MOOD_EMOJI.get(s['mood'], '🙂')} **{s['display_name']}**｜"
            f"{ACTIVITY_LABELS.get(s['activity'], s['activity'])}"
        )
        if s.get("note"):
            line += f"｜{s['note']}"
        line += f"｜あと{s['remaining_minutes']}分"
        lines.append(line)
    return "\n".join(lines) if lines else "今ヒマな人はいません"


def _empty_board_data() -> dict:
    return {
        "guild_id": 0,
        "viewer_id": 0,
        "viewer": {"user_id": 0, "notify_on_hima": False},
        "sessions": [],
        "inbox": [],
        "results": [],
    }


# ------------------------------------------------------------------ dynamic items


class KnockReplyButton(ui.DynamicItem, template=r"atsumaro:knockreply:(?P<knock_id>\d+):(?P<action>accept|later|pass)"):
    """返答ボタン（いいよ！／あとで／パス）。custom_id にノックIDを埋め込み再起動後も有効。"""

    def __init__(self, knock_id: int, action: str, row: int | None = None, label: str | None = None) -> None:
        super().__init__(
            ui.Button(
                label=label or RESULT_LABELS.get({"accept": "ok", "later": "later", "pass": "pass"}.get(action, action), action),
                style=discord.ButtonStyle.success if action == "accept" else discord.ButtonStyle.secondary,
                custom_id=f"atsumaro:knockreply:{knock_id}:{action}",
                row=row,
            )
        )
        self.knock_id = knock_id
        self.action = action

    @classmethod
    async def from_custom_id(cls, interaction: discord.Interaction, item: ui.Item, match: Any) -> "KnockReplyButton":
        return cls(int(match["knock_id"]), match["action"])

    @guarded
    async def callback(self, interaction: discord.Interaction) -> None:
        bot = interaction.client  # type: ignore[union-attr]
        is_dm = interaction.guild_id is None  # お返事着信 DM 上のボタン（痕跡を残さない）
        if is_dm:
            await interaction.response.defer()
        else:
            await interaction.response.defer(ephemeral=True, thinking=True)
        try:
            await bot.api.reply_knock(self.knock_id, user_id=interaction.user.id, action=self.action)
        except ApiHTTPError as exc:
            if exc.status_code == 409:
                if not is_dm:
                    await interaction.followup.send("返事はもう送ったよ！", ephemeral=True)
                return
            await send_api_error(interaction, exc)
            return
        except Exception as exc:  # noqa: BLE001
            await send_api_error(interaction, exc)
            return
        if is_dm:
            # 返せたら DM は削除する（痕跡を残さない）。409（既に返答済み）のときは DM を残す
            try:
                if interaction.message is not None:
                    await interaction.message.delete()
            except Exception as exc:  # noqa: BLE001
                print(f"[hima-bot] お返事着信 DM の削除に失敗しました（無視します）: {exc}")
            return
        label = RESULT_LABELS[{"accept": "accepted", "later": "later", "pass": "passed"}[self.action]]
        await interaction.followup.send(f"「{label}」を返したよ！（送り主は /panel 確認 の結果欄で確認できるよ）", ephemeral=True)


class SuggestDeclareButton(ui.DynamicItem, template=r"atsumaro:suggest:declare"):
    """提案 DM の「このまま宣言する」。押すと source=suggested / 30分 / auto_mood で宣言。"""

    def __init__(self, row: int | None = 0) -> None:
        super().__init__(
            ui.Button(
                label="このまま宣言する",
                style=discord.ButtonStyle.success,
                custom_id="atsumaro:suggest:declare",
                row=row,
            )
        )

    @classmethod
    async def from_custom_id(cls, interaction: discord.Interaction, item: ui.Item, match: Any) -> "SuggestDeclareButton":
        return cls()

    @guarded
    async def callback(self, interaction: discord.Interaction) -> None:
        bot = interaction.client  # type: ignore[union-attr]
        await interaction.response.defer(ephemeral=True, thinking=True)
        try:
            data = await bot.api.suggest_declare(interaction.user.id)
        except ApiConnectionError as exc:
            await send_api_error(interaction, exc)
            return
        except Exception as exc:  # noqa: BLE001
            await send_api_error(interaction, exc)
            return
        if data.get("created"):
            await interaction.followup.send(
                "宣言したよ！（あと30分・提案ボタンからの宣言）", ephemeral=True
            )
        else:
            await interaction.followup.send(
                "もう宣言中だったので、あと30分に延長したよ！", ephemeral=True
            )


# ------------------------------------------------------------------ board view


class BoardView(ErrorFollowupView):
    """個人用掲示板（ephemeral）。ヒマ宣言/ブロックのボタン＋受信箱の返答ボタン。

    掲示板が 0人のときは「お返事する」ボタンを表示しない（宛先候補が作れないため）。
    宣言の取り消しは /panel 取り消し に一本化（掲示板の「やめる」ボタンは廃止）。
    """

    def __init__(self, bot: "HimaBot", data: dict) -> None:
        super().__init__(timeout=None)
        self.bot = bot
        self.data = data
        if not data.get("sessions"):
            self.remove_item(self.knock)  # 0人なら「お返事する」を出さない
        # お知らせ（watch）トグルは廃止
        inbox = data.get("inbox", [])[:INBOX_LIMIT]
        flat = []
        for k in inbox:
            short_name = k["from_display_name"][:8]
            for action in ("accept", "later", "pass"):
                label = f"{RESULT_LABELS[{'accept': 'accepted', 'later': 'later', 'pass': 'passed'}[action]]}·{short_name}"
                flat.append((int(k["id"]), action, label))
        for index, (knock_id, action, label) in enumerate(flat):
            self.add_item(KnockReplyButton(knock_id, action, row=1 + index // 5, label=label))

    @ui.button(label="ヒマ宣言する", style=discord.ButtonStyle.success, custom_id="board:declare", emoji="🙋", row=0)
    async def declare(self, interaction: discord.Interaction, _: ui.Button) -> None:
        await interaction.response.send_message(
            view=JoinView(self.bot, interaction.guild_id, interaction.user, interaction.guild), ephemeral=True
        )

    @ui.button(label="お返事する", style=discord.ButtonStyle.primary, custom_id="board:knock", emoji="🚪", row=0)
    async def knock(self, interaction: discord.Interaction, _: ui.Button) -> None:
        guild_id = interaction.guild_id
        assert guild_id is not None
        await interaction.response.defer(ephemeral=True, thinking=True)
        try:
            data = await self.bot.api.get_board(
                guild_id, interaction.user.id, display_name=interaction.user.display_name,
                guild_name=interaction.guild.name if interaction.guild else None,
            )
        except Exception as exc:  # noqa: BLE001
            await send_api_error(interaction, exc)
            return
        # 募集中（宣言中）の人が先頭、それ以外の人（サーバーメンバー）が後続の宛先候補
        sessions = [s for s in data.get("sessions", []) if s["user_id"] != interaction.user.id]
        active_ids = {s["user_id"] for s in sessions}
        others: list[dict] = []
        try:
            async for member in interaction.guild.fetch_members(limit=200):  # type: ignore[union-attr]
                if member.bot or member.id == interaction.user.id or member.id in active_ids:
                    continue
                others.append({"user_id": member.id, "display_name": member.display_name, "active": False})
        except Exception as exc:  # noqa: BLE001 - メンバー一覧が取れない場合は宣言中の人だけで構わない
            log.warning("fetch_members failed (ignored): %r", exc)
        candidates = [dict(s, active=True) for s in sessions] + others[:CANDIDATE_LIMIT]
        if not candidates:
            await interaction.followup.send(
                "お返事できる人がいないよ。自分が募集してみよう！", ephemeral=True
            )
            return
        await interaction.followup.send(
            view=KnockSendView(self.bot, interaction.user, candidates), ephemeral=True
        )

    @ui.button(label="ブロック設定", style=discord.ButtonStyle.secondary, custom_id="board:blocks", row=0)
    async def blocks(self, interaction: discord.Interaction, _: ui.Button) -> None:
        guild_id = interaction.guild_id
        assert guild_id is not None
        await interaction.response.defer(ephemeral=True, thinking=True)
        try:
            data = await self.bot.api.list_blocks(interaction.user.id)
        except Exception as exc:  # noqa: BLE001
            await send_api_error(interaction, exc)
            return
        blocked = data.get("blocked", [])
        await interaction.followup.send(
            embed=_block_embed(blocked),
            view=BlockManageView(self.bot, interaction.user, blocked),
            ephemeral=True,
        )

async def _build_board(
    bot: "HimaBot", interaction: discord.Interaction
) -> tuple[list[discord.Embed] | None, ui.View | None, bool]:
    """掲示板データを取得して描画する。（embeds, view, 未確認の結果があったか）を返す。"""
    guild_id = interaction.guild_id
    assert guild_id is not None
    try:
        data = await bot.api.get_board(
            guild_id, interaction.user.id, display_name=interaction.user.display_name,
            guild_name=interaction.guild.name if interaction.guild else None,
        )
    except Exception as exc:  # noqa: BLE001
        await send_api_error(interaction, exc)
        return None, None, False
    view = BoardView(bot, data)
    return render_board(data), view, bool(data.get("results"))


# ------------------------------------------------------------------ panel view


class AtsumaroPanelView(ErrorFollowupView):
    """共有パネル（API が投稿する atsumaro:* ボタン）への応答。永続登録済み。"""

    def __init__(self, bot: "HimaBot") -> None:
        super().__init__(timeout=None)
        self.bot = bot

    @ui.button(label="掲示板を見る", style=discord.ButtonStyle.primary, custom_id="atsumaro:board", emoji="📜", row=0)
    async def board_btn(self, interaction: discord.Interaction, _: ui.Button) -> None:
        await interaction.response.defer(ephemeral=True, thinking=True)
        embeds, view, has_results = await _build_board(self.bot, interaction)
        if embeds is None:
            return
        await interaction.followup.send(embeds=embeds, view=view, ephemeral=True)
        if has_results:
            # 結果を表示できたら確認済みにする。失敗時は掲示板表示を壊さず、次回もう一度表示される
            try:
                await self.bot.api.results_seen(interaction.user.id)
            except Exception:  # noqa: BLE001
                log.warning("results_seen failed (results will be shown again)", exc_info=True)

    @ui.button(label="今ヒマ！", style=discord.ButtonStyle.success, custom_id="atsumaro:join", emoji="🙋", row=0)
    async def join_btn(self, interaction: discord.Interaction, _: ui.Button) -> None:
        await interaction.response.send_message(
            view=JoinView(self.bot, interaction.guild_id, interaction.user, interaction.guild), ephemeral=True
        )

    @ui.button(label="やめる", style=discord.ButtonStyle.secondary, custom_id="atsumaro:leave", row=0)
    async def leave_btn(self, interaction: discord.Interaction, _: ui.Button) -> None:
        await interaction.response.defer(ephemeral=True, thinking=True)
        try:
            data = await self.bot.api.end_session(interaction.user.id)
        except Exception as exc:  # noqa: BLE001
            await send_api_error(interaction, exc)
            return
        await interaction.followup.send(
            "やめたよ！また誘ってね。" if data.get("ended") else "今は宣言していないよ。", ephemeral=True
        )


# ------------------------------------------------------------------ join view


class JoinView(ErrorFollowupView):
    """登録ビュー（時間/温度感/やりたいことのセレクト＋ひとことModal＋確定）。"""

    def __init__(self, bot: "HimaBot", guild_id: int | None, user: discord.abc.User, guild: discord.Guild | None = None) -> None:
        super().__init__(timeout=300)
        self.bot = bot
        self.guild_id = guild_id
        self.guild_name: str | None = guild.name if guild is not None else None
        self.user = user
        self.duration_min: int = DEFAULT_MINUTES
        self.mood: str = "ok"
        self.activity: str = "any"
        self.note: str = ""

    @ui.select(
        placeholder=DURATION_PLACEHOLDER,
        options=[
            discord.SelectOption(label=label, value=str(minutes), default=(minutes == DEFAULT_MINUTES))
            for minutes, label in DURATIONS
        ]
        + [discord.SelectOption(label="時間を指定する…", value=CUSTOM_DURATION_VALUE, emoji="⏱️")],
        row=0,
    )
    async def duration(self, interaction: discord.Interaction, select: ui.Select) -> None:
        if select.values[0] == CUSTOM_DURATION_VALUE:
            await interaction.response.send_modal(JoinMinutesModal(self))
            return
        self.duration_min = int(select.values[0])
        self.duration.placeholder = DURATION_PLACEHOLDER  # カスタム表示をリセット
        for opt in select.options:
            opt.default = opt.value == select.values[0]
        await interaction.response.defer()

    @ui.select(
        placeholder="温度感（既定：🙂 誘われ待ち）",
        options=[discord.SelectOption(label=label, value=value, default=(value == "ok")) for value, label in MOOD_OPTIONS],
        row=1,
    )
    async def mood(self, interaction: discord.Interaction, select: ui.Select) -> None:
        self.mood = select.values[0]
        await interaction.response.defer()

    @ui.select(
        placeholder="やりたいこと（既定：✨ なんでもOK）",
        options=[
            discord.SelectOption(label=label, value=value, default=(value == "any"))
            for value, label in ACTIVITY_LABELS.items()
        ],
        row=2,
    )
    async def activity(self, interaction: discord.Interaction, select: ui.Select) -> None:
        self.activity = select.values[0]
        await interaction.response.defer()

    @ui.button(label="ひとことを追加（任意）", style=discord.ButtonStyle.secondary, row=3, emoji="✏️")
    async def note_button(self, interaction: discord.Interaction, _: ui.Button) -> None:
        await interaction.response.send_modal(JoinNoteModal(self))

    @ui.button(label="確定", style=discord.ButtonStyle.success, row=4)
    async def decide(self, interaction: discord.Interaction, _: ui.Button) -> None:
        if self.guild_id is None:
            await interaction.response.send_message("サーバー内でのみ使えるよ。", ephemeral=True)
            return
        await interaction.response.defer(ephemeral=True, thinking=True)
        try:
            data = await self.bot.api.declare_session(
                user_id=self.user.id,
                display_name=self.user.display_name,
                guild_id=self.guild_id,
                guild_name=self.guild_name,
                mood=self.mood,
                activity=self.activity,
                note=self.note,
                minutes=self.duration_min,
            )
        except Exception as exc:  # noqa: BLE001
            await send_api_error(interaction, exc)
            return
        kind = "掲示板に載せたよ！" if data.get("created") else "延長したよ！"
        suffix = f"（ひとこと：{self.note}）" if self.note else ""
        await interaction.followup.send(
            f"{kind} あと{self.duration_min}分ヒマ宣言中。マッチしたらDMが届くよ🚀{suffix}", ephemeral=True
        )


class JoinMinutesModal(ui.Modal):
    """ヒマ時間のカスタム指定（5〜720分の整数）。時間セレクトの「時間を指定する…」から開く。"""

    minutes_input = ui.TextInput(
        label="ヒマな時間（分・5〜720）",
        max_length=4,
        required=True,
        style=discord.TextStyle.short,
    )

    def __init__(self, join_view: JoinView) -> None:
        super().__init__(title="時間を指定する", timeout=300)
        self.join_view = join_view

    async def on_submit(self, interaction: discord.Interaction) -> None:
        raw = str(self.minutes_input.value or "").strip()
        try:
            minutes = int(raw)
        except ValueError:
            await interaction.response.send_message(
                "時間は半角数字（分）で入れてね。例：45", ephemeral=True
            )
            return
        if not 5 <= minutes <= 720:
            await interaction.response.send_message(
                "時間は 5〜720 分の間で指定してね。", ephemeral=True
            )
            return
        self.join_view.duration_min = minutes
        # セレクトの表示に選択した分数を出す（例：時間：あと555分）
        self.join_view.duration.placeholder = f"時間：あと{minutes}分（「時間を指定する…」で変更可）"
        for opt in self.join_view.duration.options:
            opt.default = opt.value == str(minutes)
        await interaction.response.edit_message(view=self.join_view)


class JoinNoteModal(ui.Modal):
    note_input = ui.TextInput(
        label="ひとこと（ゲーム名など・50文字まで）",
        max_length=NOTE_MAX,
        required=False,
        style=discord.TextStyle.short,
    )

    def __init__(self, join_view: JoinView) -> None:
        super().__init__(title="ひとこと追加", timeout=300)
        self.join_view = join_view

    async def on_submit(self, interaction: discord.Interaction) -> None:
        self.join_view.note = str(self.note_input.value or "").strip()
        # ボタンの表示に反映（時間指定と同じインライン方式・2つ目のメッセージは出さない）
        self.join_view.note_button.label = (
            f"ひとこと：{self.join_view.note}（変更）" if self.join_view.note else "ひとことを追加（任意）"
        )
        await interaction.response.edit_message(view=self.join_view)


# ------------------------------------------------------------------ knock send view


class KnockSendView(ErrorFollowupView):
    """お返事送信画面（相手と誘い文を選んで POST /bot/knocks）。"""

    def __init__(self, bot: "HimaBot", user: discord.abc.User, candidates: list[dict]) -> None:
        super().__init__(timeout=300)
        self.bot = bot
        self.user = user
        self.template: str | None = None  # 誘い文なしでも送れる
        # 募集中（有効な宣言がある）人が先頭。それ以外の人は入力順を維持
        ordered = sort_candidates_active_first(list(candidates))[:CANDIDATE_LIMIT]
        self.candidates_by_id = {str(s["user_id"]): s for s in ordered}
        self.user_select.options = [
            discord.SelectOption(
                label=s["display_name"],
                value=str(s["user_id"]),
                description=f"{MOOD_EMOJI.get(s['mood'], '🙂')} {ACTIVITY_LABELS.get(s['activity'], s['activity'])}"
                if s.get("active", True)
                else None,
            )
            for s in ordered
        ]
        # max_values は選択肢数を超えられない
        self.user_select.max_values = min(CANDIDATE_LIMIT, max(1, len(ordered)))

    @ui.select(placeholder="誰にお返事する？（最大25人まで）", min_values=1, max_values=CANDIDATE_LIMIT, row=0)
    async def user_select(self, interaction: discord.Interaction, select: ui.Select) -> None:
        await interaction.response.defer()

    @ui.select(
        placeholder="誘い文はどれ？（なしでも送れるよ）",
        options=[discord.SelectOption(label="誘い文なし", value=TEMPLATE_NONE)] +
                 [discord.SelectOption(label=text, value=text) for text in KNOCK_TEMPLATES],
        row=1,
    )
    async def template_select(self, interaction: discord.Interaction, select: ui.Select) -> None:
        self.template = None if select.values[0] == TEMPLATE_NONE else select.values[0]
        await interaction.response.defer()

    @ui.button(label="お返事を送る", style=discord.ButtonStyle.primary, row=2, emoji="🚪")
    async def send(self, interaction: discord.Interaction, _: ui.Button) -> None:
        if not self.user_select.values:
            await interaction.response.send_message("先にお返事する相手を選んでね！", ephemeral=True)
            return
        await interaction.response.defer(ephemeral=True, thinking=True)
        parts = []
        for uid in self.user_select.values:
            name = self.candidates_by_id.get(str(uid), {}).get("display_name") or f"discord:{uid}"
            try:
                await self.bot.api.create_knock(
                    from_user=self.user.id, to_user=int(uid), template=self.template,
                    display_name=self.user.display_name,
                )
            except ApiHTTPError as exc:
                if exc.status_code == 409:
                    parts.append(f"⏳ {name}: さっき送ったばかりだよ")
                elif exc.status_code == 403:
                    parts.append(f"🚫 {name}: その人には送れません")
                else:
                    parts.append(f"⚠️ {name}: {friendly_api_detail(exc.detail)}")
            except ApiConnectionError:
                parts.append(f"⚠️ {name}: {CONNECTION_ERROR_TEXT}")
            else:
                parts.append(f"✅ {name}: 届けたよ！（相手の受信箱と DM に届くよ）")
        await interaction.followup.send("\n".join(parts), ephemeral=True)


class KnockTemplateView(ErrorFollowupView):
    """誘い文選択（なし / game / chat / work）→ 指定した相手にお返事を送る。/panel 参加 から使う。"""

    def __init__(self, bot: "HimaBot", user: discord.abc.User, target: discord.abc.User) -> None:
        super().__init__(timeout=180)
        self.bot = bot
        self.user = user
        self.target = target

    async def _knock(self, interaction: discord.Interaction, template: str) -> None:
        try:
            await self.bot.api.create_knock(
                from_user=self.user.id, to_user=self.target.id, template=template,
                display_name=self.user.display_name,
            )
        except ApiHTTPError as exc:
            if exc.status_code == 409:
                content = "⏳ さっき送ったばかりだよ。5分待ってからもう一度ね。"
            elif exc.status_code == 403:
                content = "🚫 その人には送れません。"
            else:
                content = f"⚠️ {friendly_api_detail(exc.detail)}"
        except ApiConnectionError:
            content = f"⚠️ {CONNECTION_ERROR_TEXT}"
        else:
            content = f"✅ {self.target.display_name} さんにお返事を送ったよ！（相手の受信箱と DM に届くよ）"
        await interaction.response.defer()  # 3秒制限: 先に ACK
        await interaction.edit_original_response(content=content, view=None)

    @ui.button(label="✉️ 誘い文なし", style=discord.ButtonStyle.secondary, row=0)
    async def none_template(self, interaction: discord.Interaction, _: ui.Button) -> None:
        await self._knock(interaction, None)

    @ui.button(label="🎮 ゲームしない？", style=discord.ButtonStyle.primary, row=0)
    async def game(self, interaction: discord.Interaction, _: ui.Button) -> None:
        await self._knock(interaction, KNOCK_TEMPLATES[0])

    @ui.button(label="💬 ちょっと話さない？", style=discord.ButtonStyle.primary, row=0)
    async def chat(self, interaction: discord.Interaction, _: ui.Button) -> None:
        await self._knock(interaction, KNOCK_TEMPLATES[1])

    @ui.button(label="💻 作業通話しない？", style=discord.ButtonStyle.primary, row=0)
    async def work(self, interaction: discord.Interaction, _: ui.Button) -> None:
        await self._knock(interaction, KNOCK_TEMPLATES[2])


# ------------------------------------------------------------------ block manage view


def _block_embed(blocked: list[int]) -> discord.Embed:
    lines = [f"・ID: {uid}" for uid in blocked]
    return discord.Embed(
        title="🚫 ブロック設定",
        description="\n".join(lines) if lines else "ブロック中のユーザーはいないよ",
        color=discord.Color.red() if lines else discord.Color.dark_grey(),
    )


class BlockManageView(ErrorFollowupView):
    """ブロック追加（ユーザーセレクト）と解除（文字セレクト）。相手には知らせない。"""

    def __init__(self, bot: "HimaBot", user: discord.abc.User, blocked: list[int]) -> None:
        super().__init__(timeout=300)
        self.bot = bot
        self.user = user
        self.blocked = blocked
        if blocked:
            self.remove_select.options = [
                discord.SelectOption(label=f"ID: {uid}", value=str(uid)) for uid in blocked
            ]
        else:
            self.remove_item(self.remove_select)

    @ui.select(cls=ui.UserSelect, placeholder="ブロックに追加するユーザー", min_values=1, max_values=20, row=0)
    async def add_select(self, interaction: discord.Interaction, select: ui.UserSelect) -> None:
        await interaction.response.defer()  # 3秒制限: 先に ACK
        errors = []
        for member in select.values:
            try:
                await self.bot.api.add_block(self.user.id, member.id)
            except Exception as exc:  # noqa: BLE001
                errors.append(f"{member.display_name}: {getattr(exc, 'detail', exc)}")
        try:
            data = await self.bot.api.list_blocks(self.user.id)
        except Exception as exc:  # noqa: BLE001
            await send_api_error(interaction, exc)
            return
        self.blocked = data.get("blocked", [])
        note = ("\n" + "\n".join(errors)) if errors else ""
        await interaction.edit_original_response(
            embed=_block_embed(self.blocked), view=BlockManageView(self.bot, self.user, self.blocked)
        )
        if note:
            await interaction.followup.send(note, ephemeral=True)

    @ui.select(placeholder="ブロックを解除するユーザー", min_values=1, max_values=1, row=1)
    async def remove_select(self, interaction: discord.Interaction, select: ui.Select) -> None:
        await interaction.response.defer()  # 3秒制限: 先に ACK
        uid = int(select.values[0])
        try:
            await self.bot.api.remove_block(self.user.id, uid)
        except Exception as exc:  # noqa: BLE001
            await send_api_error(interaction, exc)
            return
        try:
            data = await self.bot.api.list_blocks(self.user.id)
        except Exception as exc:  # noqa: BLE001
            await send_api_error(interaction, exc)
            return
        self.blocked = data.get("blocked", [])
        await interaction.edit_original_response(
            embed=_block_embed(self.blocked), view=BlockManageView(self.bot, self.user, self.blocked)
        )
