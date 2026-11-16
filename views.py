"""UI parts for the Atsumaro bot (thin client over the Atsumaro API)."""
from __future__ import annotations

import logging
from typing import TYPE_CHECKING, Any

import discord
from discord import ui

from api_client import ApiConnectionError, ApiHTTPError

if TYPE_CHECKING:
    from bot import HimaBot

log = logging.getLogger("atsumaro.views")

MOOD_EMOJI = {"fire": "🔥", "ok": "🙂", "moon": "🌙"}
MOOD_OPTIONS = [("fire", "🔥 誘う人（自分から誘う）"), ("ok", "🙂 誘われ待ち"), ("moon", "🌙 静か（マッチング通知なし）")]
ACTIVITY_LABELS = {"game": "ゲーム", "chat": "雑談・通話", "work": "作業通話", "out": "外出", "any": "なんでもOK"}
RESULT_LABELS = {"accepted": "いいよ！", "later": "あとで", "passed": "今回はパス"}
KNOCK_TEMPLATES = ["ゲームしない？", "ちょっと話さない？", "作業通話しない？"]
DURATIONS = [(5, "5分"), (15, "15分"), (30, "30分"), (60, "1時間"), (180, "3時間")]
DEFAULT_MINUTES = 30
NOTE_MAX = 50
CANDIDATE_LIMIT = 25
INBOX_LIMIT = 5

CONNECTION_ERROR_TEXT = "APIサーバーに接続できませんでした。しばらくしてからもう一度試してください。"


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
            content = f"エラーが発生しました: {exc.detail}"
    else:
        content = "予期しないエラーが発生しました。しばらくしてからもう一度試してください。"
    if target.response.is_done():
        await target.followup.send(content, ephemeral=True)
    else:
        await target.response.send_message(content, ephemeral=True)


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
        title="📬 ノック受信箱",
        description="\n".join(inbox_lines) if inbox_lines else "今は届いていないよ",
        color=discord.Color.gold(),
    )
    result_lines = [
        f"・**{k['to_display_name']}** さんの返事：「{RESULT_LABELS.get(k['status'], k['status'])}」（{k['template']}）"
        for k in data.get("results", [])
    ]
    results = discord.Embed(
        title="🔔 ノックの結果",
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

    async def callback(self, interaction: discord.Interaction) -> None:
        bot = interaction.client  # type: ignore[union-attr]
        try:
            await bot.api.reply_knock(self.knock_id, user_id=interaction.user.id, action=self.action)
        except ApiHTTPError as exc:
            if exc.status_code == 409:
                await interaction.response.send_message("返事はもう送ったよ！", ephemeral=True)
                return
            await send_api_error(interaction, exc)
            return
        except Exception as exc:  # noqa: BLE001
            await send_api_error(interaction, exc)
            return
        label = RESULT_LABELS[{"accept": "accepted", "later": "later", "pass": "passed"}[self.action]]
        await interaction.response.send_message(f"「{label}」を返したよ！（送り主は /board の結果欄で確認できるよ）", ephemeral=True)


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

    async def callback(self, interaction: discord.Interaction) -> None:
        bot = interaction.client  # type: ignore[union-attr]
        try:
            data = await bot.api.suggest_declare(interaction.user.id)
        except ApiConnectionError as exc:
            await send_api_error(interaction, exc)
            return
        except Exception as exc:  # noqa: BLE001
            await send_api_error(interaction, exc)
            return
        if data.get("created"):
            await interaction.response.send_message(
                "宣言したよ！（あと30分・提案ボタンからの宣言）", ephemeral=True
            )
        else:
            await interaction.response.send_message(
                "もう宣言中だったので、あと30分に延長したよ！", ephemeral=True
            )


class WatchToggle(ui.DynamicItem, template=r"atsumaro:watchtoggle:(?P<state>[01])"):
    """見守り ON/OFF トグル。custom_id に現在の状態を埋め込む。"""

    def __init__(self, state: bool, row: int | None = 0) -> None:
        self.state = bool(state)
        super().__init__(
            ui.Button(
                label=f"見守り: {'ON' if state else 'OFF'}",
                style=discord.ButtonStyle.success if state else discord.ButtonStyle.secondary,
                custom_id=f"atsumaro:watchtoggle:{1 if state else 0}",
                row=row,
            )
        )

    @classmethod
    async def from_custom_id(cls, interaction: discord.Interaction, item: ui.Item, match: Any) -> "WatchToggle":
        return cls(match["state"] == "1")

    async def callback(self, interaction: discord.Interaction) -> None:
        bot = interaction.client  # type: ignore[union-attr]
        new_state = not self.state
        try:
            await bot.api.update_settings(interaction.user.id, notify_on_hima=new_state)
        except Exception as exc:  # noqa: BLE001
            await send_api_error(interaction, exc)
            return
        embeds, view = await _build_board(bot, interaction)
        if embeds is None:
            return
        await interaction.response.edit_message(embeds=embeds, view=view)


# ------------------------------------------------------------------ board view


class BoardView(ui.View):
    """個人用掲示板（ephemeral）。ヒマ宣言/ノック/ブロック/見守り/やめるのボタン＋受信箱の返答ボタン。"""

    def __init__(self, bot: "HimaBot", data: dict) -> None:
        super().__init__(timeout=None)
        self.bot = bot
        self.data = data
        self.add_item(WatchToggle(bool((data.get("viewer") or {}).get("notify_on_hima"))))
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
            view=JoinView(self.bot, interaction.guild_id, interaction.user), ephemeral=True
        )

    @ui.button(label="ノックする", style=discord.ButtonStyle.primary, custom_id="board:knock", emoji="🚪", row=0)
    async def knock(self, interaction: discord.Interaction, _: ui.Button) -> None:
        guild_id = interaction.guild_id
        assert guild_id is not None
        try:
            data = await self.bot.api.get_board(guild_id, interaction.user.id)
        except Exception as exc:  # noqa: BLE001
            await send_api_error(interaction, exc)
            return
        candidates = [s for s in data.get("sessions", []) if s["user_id"] != interaction.user.id][:CANDIDATE_LIMIT]
        if not candidates:
            await interaction.response.send_message(
                "今ヒマな人はいないよ。自分が宣言してみよう！", ephemeral=True
            )
            return
        await interaction.response.send_message(
            view=KnockSendView(self.bot, interaction.user, candidates), ephemeral=True
        )

    @ui.button(label="ブロック設定", style=discord.ButtonStyle.secondary, custom_id="board:blocks", row=0)
    async def blocks(self, interaction: discord.Interaction, _: ui.Button) -> None:
        guild_id = interaction.guild_id
        assert guild_id is not None
        try:
            data = await self.bot.api.list_blocks(interaction.user.id)
        except Exception as exc:  # noqa: BLE001
            await send_api_error(interaction, exc)
            return
        blocked = data.get("blocked", [])
        await interaction.response.send_message(
            embed=_block_embed(blocked),
            view=BlockManageView(self.bot, interaction.user, blocked),
            ephemeral=True,
        )

    @ui.button(label="やめる", style=discord.ButtonStyle.secondary, custom_id="board:leave", emoji="👋", row=0)
    async def leave(self, interaction: discord.Interaction, _: ui.Button) -> None:
        try:
            data = await self.bot.api.end_session(interaction.user.id)
        except Exception as exc:  # noqa: BLE001
            await send_api_error(interaction, exc)
            return
        if not data.get("ended"):
            await interaction.response.send_message("今は宣言していないよ。", ephemeral=True)
            return
        embeds, view = await _build_board(self.bot, interaction)
        if embeds is None:
            return
        await interaction.response.edit_message(embeds=embeds, view=view)


async def _build_board(bot: "HimaBot", interaction: discord.Interaction) -> tuple[list[discord.Embed] | None, ui.View | None]:
    guild_id = interaction.guild_id
    assert guild_id is not None
    try:
        data = await bot.api.get_board(guild_id, interaction.user.id)
    except Exception as exc:  # noqa: BLE001
        await send_api_error(interaction, exc)
        return None, None
    view = BoardView(bot, data)
    return render_board(data), view


# ------------------------------------------------------------------ panel view


class AtsumaroPanelView(ui.View):
    """共有パネル（API が投稿する atsumaro:* ボタン）への応答。永続登録済み。"""

    def __init__(self, bot: "HimaBot") -> None:
        super().__init__(timeout=None)
        self.bot = bot

    @ui.button(label="掲示板を見る", style=discord.ButtonStyle.primary, custom_id="atsumaro:board", emoji="📜", row=0)
    async def board_btn(self, interaction: discord.Interaction, _: ui.Button) -> None:
        embeds, view = await _build_board(self.bot, interaction)
        if embeds is None:
            return
        await interaction.response.send_message(embeds=embeds, view=view, ephemeral=True)

    @ui.button(label="今ヒマ！", style=discord.ButtonStyle.success, custom_id="atsumaro:join", emoji="🙋", row=0)
    async def join_btn(self, interaction: discord.Interaction, _: ui.Button) -> None:
        await interaction.response.send_message(
            view=JoinView(self.bot, interaction.guild_id, interaction.user), ephemeral=True
        )

    @ui.button(label="やめる", style=discord.ButtonStyle.secondary, custom_id="atsumaro:leave", row=0)
    async def leave_btn(self, interaction: discord.Interaction, _: ui.Button) -> None:
        try:
            data = await self.bot.api.end_session(interaction.user.id)
        except Exception as exc:  # noqa: BLE001
            await send_api_error(interaction, exc)
            return
        await interaction.response.send_message(
            "やめたよ！また誘ってね。" if data.get("ended") else "今は宣言していないよ。", ephemeral=True
        )


# ------------------------------------------------------------------ join view


class JoinView(ui.View):
    """登録ビュー（時間/温度感/やりたいことのセレクト＋ひとことModal＋確定）。"""

    def __init__(self, bot: "HimaBot", guild_id: int | None, user: discord.abc.User) -> None:
        super().__init__(timeout=300)
        self.bot = bot
        self.guild_id = guild_id
        self.user = user
        self.duration_min: int = DEFAULT_MINUTES
        self.mood: str = "ok"
        self.activity: str = "any"
        self.note: str = ""

    @ui.select(
        placeholder="時間：あとどれくらいヒマ？（既定30分）",
        options=[
            discord.SelectOption(label=label, value=str(minutes), default=(minutes == DEFAULT_MINUTES))
            for minutes, label in DURATIONS
        ],
        row=0,
    )
    async def duration(self, interaction: discord.Interaction, select: ui.Select) -> None:
        self.duration_min = int(select.values[0])
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
        try:
            data = await self.bot.api.declare_session(
                user_id=self.user.id,
                display_name=self.user.display_name,
                guild_id=self.guild_id,
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
        await interaction.response.send_message(
            f"{kind} あと{self.duration_min}分ヒマ宣言中。マッチした相手にはDMが届くよ🚀{suffix}", ephemeral=True
        )


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
        self.join_view.note = str(self.note_input.value or "")
        if self.join_view.note:
            await interaction.response.send_message(
                f"ひとことを設定したよ：「{self.join_view.note}」。あとは「確定」を押してね！", ephemeral=True
            )
        else:
            await interaction.response.send_message("ひとことを空にしたよ。そのまま「確定」できるよ！", ephemeral=True)


# ------------------------------------------------------------------ knock send view


class KnockSendView(ui.View):
    """ノック送信画面（相手とテンプレを選んで POST /bot/knocks）。"""

    def __init__(self, bot: "HimaBot", user: discord.abc.User, candidates: list[dict]) -> None:
        super().__init__(timeout=300)
        self.bot = bot
        self.user = user
        self.template = KNOCK_TEMPLATES[0]
        self.user_select.options = [
            discord.SelectOption(
                label=s["display_name"],
                value=str(s["user_id"]),
                description=f"{MOOD_EMOJI.get(s['mood'], '🙂')} {ACTIVITY_LABELS.get(s['activity'], s['activity'])}",
            )
            for s in candidates
        ]

    @ui.select(cls=ui.UserSelect, placeholder="誰にノックする？（最大25人まで）", min_values=1, max_values=CANDIDATE_LIMIT, row=0)
    async def user_select(self, interaction: discord.Interaction, select: ui.UserSelect) -> None:
        await interaction.response.defer()

    @ui.select(
        placeholder="誘い文はどれ？",
        options=[discord.SelectOption(label=text, value=text) for text in KNOCK_TEMPLATES],
        row=1,
    )
    async def template_select(self, interaction: discord.Interaction, select: ui.Select) -> None:
        self.template = select.values[0]
        await interaction.response.defer()

    @ui.button(label="ノックを送る", style=discord.ButtonStyle.primary, row=2, emoji="🚪")
    async def send(self, interaction: discord.Interaction, _: ui.Button) -> None:
        if not self.user_select.values:
            await interaction.response.send_message("先にノックする相手を選んでね！", ephemeral=True)
            return
        parts = []
        for member in self.user_select.values:
            try:
                await self.bot.api.create_knock(
                    from_user=self.user.id, to_user=member.id, template=self.template
                )
            except ApiHTTPError as exc:
                if exc.status_code == 409:
                    parts.append(f"⏳ {member.display_name}: さっき送ったばかりだよ")
                elif exc.status_code == 403:
                    parts.append(f"🚫 {member.display_name}: その人には送れません")
                else:
                    parts.append(f"⚠️ {member.display_name}: {exc.detail}")
            except ApiConnectionError:
                parts.append(f"⚠️ {member.display_name}: {CONNECTION_ERROR_TEXT}")
            else:
                parts.append(f"✅ {member.display_name}: 届けたよ！（相手の /board 受信箱に表示されるよ）")
        await interaction.response.send_message("\n".join(parts), ephemeral=True)


# ------------------------------------------------------------------ block manage view


def _block_embed(blocked: list[int]) -> discord.Embed:
    lines = [f"・ID: {uid}" for uid in blocked]
    return discord.Embed(
        title="🚫 ブロック設定",
        description="\n".join(lines) if lines else "ブロック中のユーザーはいないよ",
        color=discord.Color.red() if lines else discord.Color.dark_grey(),
    )


class BlockManageView(ui.View):
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
        await interaction.response.edit_message(
            embed=_block_embed(self.blocked), view=BlockManageView(self.bot, self.user, self.blocked)
        )
        if note:
            await interaction.followup.send(note, ephemeral=True)

    @ui.select(placeholder="ブロックを解除するユーザー", min_values=1, max_values=1, row=1)
    async def remove_select(self, interaction: discord.Interaction, select: ui.Select) -> None:
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
        await interaction.response.edit_message(
            embed=_block_embed(self.blocked), view=BlockManageView(self.bot, self.user, self.blocked)
        )
