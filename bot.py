"""Atsumaro Bot — a thin client over the Atsumaro API (no local database).

Startup, slash commands and Discord UI only; all state lives behind the API.
Observability (command error handler, disconnect/resumed logs, heartbeat)
carries over from commit a9ca819.
"""
from __future__ import annotations

import asyncio
import os
import re
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
    SuggestDeclareButton,
    WatchToggle,
    _build_board,
    send_api_error,
)

load_dotenv()

# 旧形式の自Botメッセージ（移行期の掃除対象）
OLD_PANEL_CUSTOM_IDS = {"hima:join", "hima:leave", "hima:knock"}
OLD_BOARD_TITLE_WORDS = ("掲示板", "メンバー一覧")
COUNTER_RE = re.compile(r"^いま\d+人ヒマ$")


class HimaBot(commands.Bot):
    def __init__(self) -> None:
        # Non-privileged standard intents only.
        super().__init__(command_prefix="!", intents=discord.Intents.default())
        self.display_name = os.getenv("BOT_DISPLAY_NAME") or "今ヒマ！"
        self.api = ApiClient()
        self.panel_setup_locks: dict[int, asyncio.Lock] = {}
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

    async def sweep_legacy_messages(self, channel: discord.abc.Messageable) -> tuple[int, int]:
        """旧形式の自Botメッセージ（hima:* ボタン/旧掲示板embed/旧人数メッセージ）を掃除する。"""
        scanned = 0
        removed = 0
        async for message in channel.history(limit=200):
            if message.author.id != self.user.id:
                continue
            scanned += 1
            component_ids = {
                getattr(child, "custom_id", "") or ""
                for row in message.components
                for child in row.children
            }
            is_old_panel = any(cid in OLD_PANEL_CUSTOM_IDS for cid in component_ids)
            is_any_panel = any(cid.startswith("atsumaro:") for cid in component_ids)
            is_old_board = any(
                embed.title is not None and any(w in embed.title for w in OLD_BOARD_TITLE_WORDS)
                for embed in message.embeds
            )
            is_old_counter = bool(COUNTER_RE.match(message.content or ""))
            if not (is_old_panel or is_any_panel or is_old_board or is_old_counter):
                continue
            try:
                await message.delete()
                removed += 1
            except Exception as exc:  # noqa: BLE001 - cleanup must not break setup
                print(f"[hima-bot] 旧メッセージの削除に失敗しました（無視します）: {exc}")
        print(f"[hima-bot][sweep] scanned={scanned} removed={removed}")
        return scanned, removed

    async def _send_board(self, interaction: discord.Interaction) -> None:
        embeds, view = await _build_board(self, interaction)
        if embeds is None:
            return
        await interaction.response.send_message(embeds=embeds, view=view, ephemeral=True)


class HimaCog(commands.Cog):
    def __init__(self, bot: HimaBot) -> None:
        self.bot = bot

    # ------------------------------------------------------------------ /panel_setup

    @app_commands.command(name="panel_setup", description="Atsumaro パネル（人数表示つき）をこのチャンネルに設置する")
    @app_commands.guild_only()
    async def panel_setup(self, interaction: discord.Interaction) -> None:
        assert interaction.guild_id is not None
        await interaction.response.defer(ephemeral=True)
        lock = self.bot.panel_setup_locks.setdefault(interaction.guild_id, asyncio.Lock())
        if lock.locked():
            await interaction.followup.send("設置処理中です。少し待ってからもう一度試してね。", ephemeral=True)
            return
        async with lock:
            # 旧方式のメッセージ対を先に消す（未設置なら何も起きない）
            try:
                await self.bot.api.teardown_guild(interaction.guild_id)
            except ApiHTTPError as exc:
                if exc.status_code != 404:
                    await send_api_error(interaction, exc)
                    return
            except ApiConnectionError as exc:
                await send_api_error(interaction, exc)
                return
            channel = interaction.channel
            assert channel is not None and hasattr(channel, "send")
            scanned, removed = await self.bot.sweep_legacy_messages(channel)
            try:
                data = await self.bot.api.setup_guild(
                    interaction.guild_id, interaction.guild.name, channel.id
                )
            except (ApiConnectionError, ApiHTTPError) as exc:
                await send_api_error(interaction, exc)
                return
            lines = [f"パネルを設置したよ！（掃除：{removed}件削除）"]
            if data.get("counter_message_id"):
                lines.append(f"人数メッセージ: {data.get('counter_message_id')}")
            if data.get("panel_message_id"):
                lines.append(f"パネルメッセージ: {data.get('panel_message_id')}")
            await interaction.followup.send("\n".join(lines), ephemeral=True)

    # ------------------------------------------------------------------ /panel_remove

    @app_commands.command(name="panel_remove", description="このチャンネルのパネルと人数表示を削除する")
    @app_commands.guild_only()
    async def panel_remove(self, interaction: discord.Interaction) -> None:
        assert interaction.guild_id is not None
        await interaction.response.defer(ephemeral=True)
        channel = interaction.channel
        assert channel is not None
        scanned, removed = await self.bot.sweep_legacy_messages(channel)
        try:
            await self.bot.api.teardown_guild(interaction.guild_id)
        except ApiHTTPError as exc:
            if exc.status_code != 404:
                await send_api_error(interaction, exc)
                return
        except ApiConnectionError as exc:
            await send_api_error(interaction, exc)
            return
        await interaction.followup.send(f"パネルを撤去したよ！（掃除：{removed}件削除）", ephemeral=True)

    # ------------------------------------------------------------------ /board

    @app_commands.command(name="board", description="自分専用の掲示板（受信箱つき）を開く")
    @app_commands.guild_only()
    async def board(self, interaction: discord.Interaction) -> None:
        await self.bot._send_board(interaction)

    # ------------------------------------------------------------------ 互換エイリアス

    @app_commands.command(name="hima", description="ヒマ宣言する（/board のボタンと同じ）")
    @app_commands.guild_only()
    async def hima(self, interaction: discord.Interaction) -> None:
        await interaction.response.send_message(
            view=JoinView(self.bot, interaction.guild_id, interaction.user), ephemeral=True
        )

    @app_commands.command(name="hima_off", description="ヒマ宣言をやめる")
    @app_commands.guild_only()
    async def hima_off(self, interaction: discord.Interaction) -> None:
        try:
            data = await self.bot.api.end_session(interaction.user.id)
        except Exception as exc:  # noqa: BLE001
            await send_api_error(interaction, exc)
            return
        await interaction.response.send_message(
            "やめたよ！また誘ってね。" if data.get("ended") else "今は宣言していないよ。", ephemeral=True
        )

    @app_commands.command(name="hima_list", description="掲示板を見る（/board と同じ）")
    @app_commands.guild_only()
    async def hima_list(self, interaction: discord.Interaction) -> None:
        await self.bot._send_board(interaction)


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
