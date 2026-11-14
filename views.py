"""UI parts (persistent panel view, ephemeral join/knock views, modal, DM reply buttons)."""
from __future__ import annotations

import time
from datetime import datetime
from typing import TYPE_CHECKING, Any, Dict, List

import discord
from discord import ui

import storage

if TYPE_CHECKING:
    from bot import HimaBot


# ------------------------------------------------------------------ constants

DURATIONS = [(5, "5分"), (15, "15分"), (30, "30分"), (60, "1時間"), (180, "3時間")]

MOODS = [("fire", "🔥 今すぐ遊びたい"), ("ok", "🙂 誘われたら行く"), ("quiet", "🌙 ひっそり暇")]
MOOD_SHORT: Dict[str, str] = {"fire": "🔥", "ok": "🙂", "quiet": "🌙"}

ACTIVITIES = [
    ("game", "🎮 ゲーム"),
    ("chat", "💬 雑談・通話"),
    ("work", "💻 作業通話"),
    ("out", "🚶 外出"),
    ("any", "✨ なんでもOK"),
]
ACTIVITY_SHORT: Dict[str, str] = {
    "game": "ゲーム",
    "chat": "雑談・通話",
    "work": "作業通話",
    "out": "外出",
    "any": "なんでもOK",
}

ANNOUNCE_OPTIONS = [
    ("silent", "🔕 静かに登録（何も流さない）"),
    ("message", "💬 メッセージで流す"),
    ("mention", "📣 メンション付きで流す"),
]

KNOCK_TEMPLATES = ["ゲームしない？", "ちょっと話さない？", "作業通話しない？"]

REPLY_LABELS = {"ok": "いいよ！", "later": "あとで", "pass": "今回はパス"}
REPLY_STATUS = {"ok": "accepted", "later": "later", "pass": "passed"}


def remaining_text(expires_at: int, now: int) -> str:
    minutes = max(1, (expires_at - now) // 60)
    return f"あと{minutes}分"


def build_panel_embed(display_name: str) -> discord.Embed:
    embed = discord.Embed(
        title=display_name,
        description=(
            "ヒマをそっと置いておく掲示板だよ。\n"
            "暇だなと思ったときに見に来て、誰かいたら気が向いたほうから声をかけてね。\n\n"
            "・**今ヒマ！** … 自分のヒマを掲示板に置く\n"
            "・**やめる** … 置いたものを下ろす\n"
            "・**ノックする** … 掲示板の人にDMで声をかける"
        ),
        color=discord.Color.green(),
    )
    return embed


def build_list_embed(rows: List[Any], display_name: str) -> discord.Embed:
    now = int(time.time())
    title = f"📜 {display_name} 掲示板（いま{len(rows)}人）"
    if not rows:
        description = "今ヒマな人はいません"
    else:
        lines = []
        for row in rows:
            end_time = datetime.fromtimestamp(row["expires_at"]).strftime("%H:%M")
            line = f"**{row['display_name']}**｜{row['mood']}｜{row['activity']}"
            if row["note"]:
                line += f"｜{row['note']}"
            line += f"｜{remaining_text(row['expires_at'], now)}（{end_time}まで）"
            lines.append(line)
        description = "\n".join(lines)
    embed = discord.Embed(title=title, description=description)
    embed.color = discord.Color.green() if rows else discord.Color.dark_grey()
    return embed


# ------------------------------------------------------- persistent panel view


class HimaPanelView(ui.View):
    """Persistent panel (timeout=None, fixed custom_ids) so buttons survive restarts."""

    def __init__(self, bot: "HimaBot") -> None:
        super().__init__(timeout=None)
        self.bot = bot

    @ui.button(label="今ヒマ！", style=discord.ButtonStyle.success, custom_id="hima:join", emoji="🙋")
    async def join(self, interaction: discord.Interaction, _: ui.Button) -> None:
        await interaction.response.send_message(view=HimaJoinView(self.bot), ephemeral=True)

    @ui.button(label="やめる", style=discord.ButtonStyle.secondary, custom_id="hima:leave")
    async def leave(self, interaction: discord.Interaction, _: ui.Button) -> None:
        guild_id = interaction.guild_id
        assert guild_id is not None
        if storage.delete_hima(guild_id, interaction.user.id):
            await self.bot.refresh_guild_list(guild_id)
            await interaction.response.send_message("登録をやめたよ！また誘ってね。", ephemeral=True)
        else:
            await interaction.response.send_message("今はヒマ登録されていないよ。", ephemeral=True)

    @ui.button(label="ノックする", style=discord.ButtonStyle.primary, custom_id="hima:knock", emoji="🚪")
    async def knock(self, interaction: discord.Interaction, _: ui.Button) -> None:
        guild_id = interaction.guild_id
        assert guild_id is not None
        rows = [r for r in storage.list_hima(guild_id, int(time.time())) if r["user_id"] != interaction.user.id]
        others = rows[:25]
        if not others:
            await interaction.response.send_message(
                "今ヒマな人はいないよ。自分が「今ヒマ！」で登録してみよう！", ephemeral=True
            )
            return
        await interaction.response.send_message(view=KnockView(self.bot, others), ephemeral=True)


# --------------------------------------------------------- join view (ephemeral)


class HimaJoinView(ui.View):
    """Ephemeral registration screen shown only to the person who pressed the button."""

    def __init__(self, bot: "HimaBot") -> None:
        super().__init__(timeout=300)
        self.bot = bot
        self.duration_min = 30
        self.mood = "ok"
        self.activity = "any"
        self.announce = "silent"
        self.note = ""

    @ui.select(
        placeholder="時間：あとどれくらいヒマ？",
        options=[
            discord.SelectOption(label=label, value=str(minutes), default=(minutes == 30))
            for minutes, label in DURATIONS
        ],
        row=0,
    )
    async def duration(self, interaction: discord.Interaction, select: ui.Select) -> None:
        self.duration_min = int(select.values[0])
        await interaction.response.defer()

    @ui.select(
        placeholder="温度感は？",
        options=[
            discord.SelectOption(label=label, value=value, default=(value == "ok"))
            for value, label in MOODS
        ],
        row=1,
    )
    async def mood(self, interaction: discord.Interaction, select: ui.Select) -> None:
        self.mood = select.values[0]
        await interaction.response.defer()

    @ui.select(
        placeholder="やりたいことは？",
        options=[
            discord.SelectOption(label=label, value=value, default=(value == "any"))
            for value, label in ACTIVITIES
        ],
        row=2,
    )
    async def activity(self, interaction: discord.Interaction, select: ui.Select) -> None:
        self.activity = select.values[0]
        await interaction.response.defer()

    @ui.select(
        placeholder="みんなへのお知らせ",
        options=[
            discord.SelectOption(label=label, value=value, default=(value == "silent"))
            for value, label in ANNOUNCE_OPTIONS
        ],
        row=3,
    )
    async def announce_select(self, interaction: discord.Interaction, select: ui.Select) -> None:
        self.announce = select.values[0]
        await interaction.response.defer()

    @ui.button(label="ひとことを追加（任意）", style=discord.ButtonStyle.secondary, row=4, emoji="✏️")
    async def note_button(self, interaction: discord.Interaction, _: ui.Button) -> None:
        await interaction.response.send_modal(NoteModal(self))

    @ui.button(label="決定", style=discord.ButtonStyle.success, row=4)
    async def decide(self, interaction: discord.Interaction, _: ui.Button) -> None:
        if self.duration_min is None or self.mood is None or self.activity is None:
            await interaction.response.send_message(
                "時間・温度感・やりたいことをぜんぶ選んでね！", ephemeral=True
            )
            return
        guild_id = interaction.guild_id
        assert guild_id is not None
        now = int(time.time())
        storage.upsert_hima(
            guild_id=guild_id,
            user_id=interaction.user.id,
            display_name=interaction.user.display_name,
            started_at=now,
            expires_at=now + self.duration_min * 60,
            mood=MOOD_SHORT[self.mood],
            activity=ACTIVITY_SHORT[self.activity],
            note=self.note,
        )
        await self.bot.refresh_guild_list(guild_id)
        mood_label = dict(MOODS)[self.mood]
        activity_label = ACTIVITY_SHORT[self.activity]
        await self.bot.announce_hima(
            guild_id=guild_id,
            display_name=interaction.user.display_name,
            minutes=self.duration_min,
            mood_label=mood_label,
            activity=activity_label,
            note=self.note,
            method=self.announce,
        )
        suffix = f"（{self.note}）" if self.note else ""
        await interaction.response.send_message(
            f"掲示板に載せたよ！ あと{self.duration_min}分ヒマ宣言中{suffix}", ephemeral=True
        )


class NoteModal(ui.Modal):
    note_input = ui.TextInput(
        label="ひとこと（ゲーム名など・50文字まで）",
        max_length=50,
        required=False,
        style=discord.TextStyle.short,
    )

    def __init__(self, join_view: HimaJoinView) -> None:
        super().__init__(title="ひとこと追加", timeout=300)
        self.join_view = join_view

    async def on_submit(self, interaction: discord.Interaction) -> None:
        self.join_view.note = str(self.note_input.value or "")
        if self.join_view.note:
            await interaction.response.send_message(
                f"ひとことを設定したよ：「{self.join_view.note}」。あとは「決定」を押してね！", ephemeral=True
            )
        else:
            await interaction.response.send_message("ひとことを空にしたよ。そのまま「決定」できるよ！", ephemeral=True)


# -------------------------------------------------------- knock view (ephemeral)


class KnockView(ui.View):
    """Ephemeral knock screen: pick targets and a template, then DM them."""

    def __init__(self, bot: "HimaBot", candidate_rows: List[Any]) -> None:
        super().__init__(timeout=300)
        self.bot = bot
        self.template = KNOCK_TEMPLATES[0]
        self.user_select.options = [
            discord.SelectOption(
                label=row["display_name"],
                value=str(row["user_id"]),
                description=f"{row['activity']}｜{row['mood']}",
            )
            for row in candidate_rows
        ]

    @ui.select(cls=ui.UserSelect, placeholder="誰にノックする？（最大25人まで）", min_values=1, max_values=25, row=0)
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
        guild_id = interaction.guild_id
        assert guild_id is not None
        sender = interaction.user
        now = int(time.time())
        sent: List[str] = []
        cooldown: List[str] = []
        failed: List[str] = []
        for value in self.user_select.values:
            target_id = int(value)
            target: discord.abc.User | None = interaction.guild.get_member(target_id)  # type: ignore[union-attr]
            if target is None:
                try:
                    target = await self.bot.fetch_user(target_id)
                except discord.HTTPException:
                    failed.append(f"ID {target_id}")
                    continue
            if storage.recent_knock_exists(guild_id, sender.id, target_id, now, window=300):
                cooldown.append(target.display_name)
                continue
            knock_id = storage.record_knock(guild_id, sender.id, target_id, self.template, "sent", now)
            try:
                dm = await target.create_dm()
                embed = discord.Embed(
                    title="🚪 ノックが届いたよ！",
                    description=f"**{sender.display_name}** さんが「{self.template}」って誘ってきた！",
                    color=discord.Color.gold(),
                )
                await dm.send(embed=embed, view=KnockReplyView(knock_id))
                sent.append(target.display_name)
            except discord.Forbidden:
                storage.update_knock_status(knock_id, "dm_closed")
                failed.append(target.display_name)
            except discord.HTTPException:
                storage.update_knock_status(knock_id, "dm_closed")
                failed.append(target.display_name)
        parts = []
        if sent:
            parts.append("✅ ノックを送ったよ: " + ", ".join(sent))
        if cooldown:
            parts.append("⏳ 同じ相手には5分に1回まで。ちょっと待ってね: " + ", ".join(cooldown))
        if failed:
            parts.append("🔒 DMが閉じられていて届かなかったよ: " + ", ".join(failed))
        await interaction.response.send_message("\n".join(parts), ephemeral=True)


# ------------------------------------------------------ DM reply (persistent)


class KnockReplyButton(ui.DynamicItem, template=r"hima:knockreply:(?P<knock_id>\d+):(?P<action>ok|later|pass)"):
    """Persistent DM reply button whose custom_id carries the knock_log id."""

    def __init__(self, knock_id: int, action: str) -> None:
        super().__init__(
            ui.Button(
                label=REPLY_LABELS[action],
                style=discord.ButtonStyle.success if action == "ok" else discord.ButtonStyle.secondary,
                custom_id=f"hima:knockreply:{knock_id}:{action}",
            )
        )
        self.knock_id = knock_id
        self.action = action

    @classmethod
    async def from_custom_id(
        cls, interaction: discord.Interaction, item: ui.Item, match: Any
    ) -> "KnockReplyButton":
        return cls(int(match["knock_id"]), match["action"])

    async def callback(self, interaction: discord.Interaction) -> None:
        knock = storage.get_knock(self.knock_id)
        if knock is None:
            await interaction.response.send_message("このノックはもう無効だよ。", ephemeral=True)
            return
        if knock["status"] != "sent":
            await interaction.response.send_message("返事はもう送ったよ！", ephemeral=True)
            return
        storage.update_knock_status(self.knock_id, REPLY_STATUS[self.action])
        label = REPLY_LABELS[self.action]
        try:
            sender = await interaction.client.fetch_user(knock["from_user_id"])  # type: ignore[union-attr]
            dm = await sender.create_dm()
            embed = discord.Embed(
                title="🔔 ノックの返事が届いたよ！",
                description=f"**{interaction.user.display_name}** さんの返事：「{label}」",
                color=discord.Color.green(),
            )
            await dm.send(embed=embed)
        except discord.HTTPException:
            pass
        await interaction.response.send_message(f"「{label}」を返したよ！", ephemeral=True)


class KnockReplyView(ui.View):
    """Buttons attached to the knock DM; each button is a DynamicItem (works after restart)."""

    def __init__(self, knock_id: int) -> None:
        super().__init__(timeout=None)
        for action in ("ok", "later", "pass"):
            self.add_item(KnockReplyButton(knock_id, action))
