"""Atsumaro Bot — a thin client over the Atsumaro API (no local database).

Startup, slash commands and Discord UI only; all state lives behind the API.
Observability (command error handler, disconnect/resumed logs, heartbeat)
carries over from commit a9ca819.
"""
from __future__ import annotations

import os
import sys
import time

import discord
from discord import app_commands
from discord.ext import commands, tasks
from dotenv import load_dotenv

from api_client import ApiClient, ApiConnectionError, ApiHTTPError
from views import (
    AtsumaroPanelView,
    BoardView,
    JoinView,
    KnockReplyButton,
    KnockTemplateView,
    SuggestDeclareButton,
    WatchToggle,
    _build_board,
    send_api_error,
)

load_dotenv()


class HimaBot(commands.Bot):
    def __init__(self) -> None:
        # Non-privileged standard intents only.
        super().__init__(command_prefix="!", intents=discord.Intents.default())
        self.display_name = os.getenv("BOT_DISPLAY_NAME") or "今ヒマ！"
        self.api = ApiClient()
        self._started_at = time.time()

    async def setup_hook(self) -> None:
        await self.add_cog(HimaCog(self))
        # Persistent panel/board views + dynamic knock-reply/watch-toggle items
        # survive restarts.
        self.add_view(AtsumaroPanelView(self))
        self.add_view(BoardView(self, _empty_board_data()))
        self.add_dynamic_items(KnockReplyButton)
        self.add_dynamic_items(WatchToggle)
        self.add_dynamic_items(SuggestDeclareButton)
        self.tree.on_error = self._on_app_command_error
        await self._sync_commands()
        self.liveness_loop.start()
        print("persistent views & dynamic items registered")

    async def _sync_commands(self) -> None:
        dev_guild_id = os.getenv("DEV_GUILD_ID")
        try:
            if dev_guild_id:
                guild = discord.Object(id=int(dev_guild_id))
                self.tree.copy_global_to(guild=guild)
                await self.tree.sync(guild=guild)
                print(f"スラッシュコマンドをギルド {dev_guild_id} に即時同期しました。")
            else:
                await self.tree.sync()
                print("スラッシュコマンドをグローバルに同期しました（反映まで最大1時間かかることがあります）。")
        except discord.HTTPException as exc:
            print(f"コマンド同期に失敗しました: {exc}")

    async def on_ready(self) -> None:
        print(f"ログインしました: {self.user} (api={self.api.base_url})")

    async def _on_app_command_error(
        self, interaction: discord.Interaction, error: app_commands.AppCommandError
    ) -> None:
        command = interaction.command
        name = command.name if command is not None else "<unknown>"
        print(f"[hima-bot][cmd-error] /{name}: {type(error).__name__}: {error}")
        # ユーザーへの応答試行で二次例外を出さないよう握る

    async def on_disconnect(self) -> None:
        print("[hima-bot][gateway] disconnected")

    async def on_resumed(self) -> None:
        print("[hima-bot][gateway] resumed")

    @tasks.loop(minutes=10)
    async def liveness_loop(self) -> None:
        uptime = time.time() - self._started_at
        print(f"[hima-bot][heartbeat] alive for {int(uptime // 3600)}h{int(uptime % 3600 // 60):02d}m")

    # ------------------------------------------------------------------ helpers

    async def _send_board(self, interaction: discord.Interaction) -> None:
        embeds, view = await _build_board(self, interaction)
        if embeds is None:
            return
        await interaction.response.send_message(embeds=embeds, view=view, ephemeral=True)


class HimaCog(commands.Cog):
    panel = app_commands.Group(
        name="panel",
        description="Atsumaro の操作（応答はすべて自分だけに表示されます）",
        guild_only=True,
    )

    def __init__(self, bot: HimaBot) -> None:
        self.bot = bot

    # ------------------------------------------------------------------ /panel 確認

    @panel.command(name="確認", description="いま募集している人と自分の状態を見る")
    async def panel_check(self, interaction: discord.Interaction) -> None:
        """旧 /board と同一内容（掲示板＋自分の状態＋受信箱＋ボタン群）。"""
        await self.bot._send_board(interaction)

    # ------------------------------------------------------------------ /panel 募集

    @panel.command(name="募集", description="募集をはじめる")
    async def panel_recruit(self, interaction: discord.Interaction) -> None:
        await interaction.response.send_message(
            view=JoinView(self.bot, interaction.guild_id, interaction.user), ephemeral=True
        )

    # ------------------------------------------------------------------ /panel 取り消し

    @panel.command(name="取り消し", description="募集を取り消す")
    async def panel_cancel(self, interaction: discord.Interaction) -> None:
        try:
            data = await self.bot.api.end_session(interaction.user.id)
        except Exception as exc:  # noqa: BLE001
            await send_api_error(interaction, exc)
            return
        if data.get("ended"):
            await interaction.response.send_message("募集を取り消したよ！また誘ってね。", ephemeral=True)
        else:
            await interaction.response.send_message("いまは募集していません", ephemeral=True)

    # ------------------------------------------------------------------ /panel 参加

    @panel.command(name="参加", description="募集している人に参加を申し込む")
    @app_commands.describe(相手="参加を申し込む相手（いま募集している人）")
    async def panel_join(self, interaction: discord.Interaction, 相手: discord.User) -> None:
        guild_id = interaction.guild_id
        assert guild_id is not None
        try:
            data = await self.bot.api.get_board(guild_id, interaction.user.id)
        except Exception as exc:  # noqa: BLE001
            await send_api_error(interaction, exc)
            return
        target = next((s for s in data.get("sessions", []) if s["user_id"] == 相手.id), None)
        if target is None:
            await interaction.response.send_message("いまは募集していないみたいです", ephemeral=True)
            return
        await interaction.response.send_message(
            view=KnockTemplateView(self.bot, interaction.user, 相手), ephemeral=True
        )


def _empty_board_data() -> dict:
    from views import _empty_board_data as _e

    return _e()


def main() -> None:
    token: str | None = os.getenv("DISCORD_TOKEN")
    if not token:
        print("DISCORD_TOKENが未設定です。.env に DISCORD_TOKEN=... を書いてから起動してください。")
        sys.exit(1)
    bot = HimaBot()
    bot.run(token)


if __name__ == "__main__":
    main()
