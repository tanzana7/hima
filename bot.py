"""hima-bot entry point: startup, slash commands, background cleanup loop."""
from __future__ import annotations

import os
import sys
import time
from typing import Optional

import discord
from discord import app_commands
from discord.ext import commands, tasks
from dotenv import load_dotenv

import storage
from views import (
    HimaJoinView,
    HimaPanelView,
    KnockReplyButton,
    KnockView,
    build_list_embed,
    build_panel_embed,
)

load_dotenv()

DEFAULT_DISPLAY_NAME = "今ヒマ！"


class HimaBot(commands.Bot):
    def __init__(self) -> None:
        # No privileged intents (presence / server members / message content are all off).
        super().__init__(command_prefix="!", intents=discord.Intents.none())
        self.display_name = os.getenv("BOT_DISPLAY_NAME") or DEFAULT_DISPLAY_NAME

    async def setup_hook(self) -> None:
        storage.init()
        await self.add_cog(HimaCog(self))
        # Persistent panel view + dynamic knock-reply buttons survive restarts.
        self.add_view(HimaPanelView(self))
        self.add_dynamic_items(KnockReplyButton)
        await self._sync_commands()
        self.cleanup_loop.start()

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
        print(f"ログインしました: {self.user} (display_name={self.display_name})")

    async def refresh_guild_list(self, guild_id: int) -> None:
        """Re-render the list message for one guild (kept always up to date)."""
        cfg = storage.get_guild_config(guild_id)
        if cfg is None:
            return
        channel = self.get_channel(cfg["channel_id"])
        if channel is None:
            try:
                channel = await self.fetch_channel(cfg["channel_id"])
            except discord.HTTPException:
                return
        try:
            message = await channel.fetch_message(cfg["list_message_id"])
        except discord.HTTPException:
            return
        rows = storage.list_hima(guild_id, now=int(time.time()))
        try:
            await message.edit(embed=build_list_embed(rows, self.display_name))
        except discord.HTTPException:
            pass

    @tasks.loop(seconds=30)
    async def cleanup_loop(self) -> None:
        """Purge expired registrations every 30 seconds and refresh the lists."""
        changed = storage.purge_expired(now=int(time.time()))
        for guild_id in changed:
            await self.refresh_guild_list(guild_id)


class HimaCog(commands.Cog):
    def __init__(self, bot: HimaBot) -> None:
        self.bot = bot

    # ------------------------------------------------------------------ /panel_setup

    @app_commands.command(
        name="panel_setup",
        description="ヒマパネルと一覧をこのチャンネルに設置する（サーバー管理権限が必要）",
    )
    @app_commands.guild_only()
    @app_commands.default_permissions(manage_guild=True)
    async def panel_setup(self, interaction: discord.Interaction) -> None:
        perms = getattr(interaction.user, "guild_permissions", None)
        if perms is None or not (perms.manage_guild or perms.administrator):
            await interaction.response.send_message(
                "このコマンドはサーバー管理権限のある人だけが使えるよ。", ephemeral=True
            )
            return
        assert interaction.guild_id is not None
        channel = interaction.channel
        assert channel is not None and hasattr(channel, "send")
        panel_message = await channel.send(
            embed=build_panel_embed(self.bot.display_name), view=HimaPanelView(self.bot)
        )
        list_message = await channel.send(embed=build_list_embed([], self.bot.display_name))
        storage.set_guild_config(
            interaction.guild_id, channel.id, panel_message.id, list_message.id
        )
        await interaction.response.send_message(
            "パネルと一覧を設置したよ！ここに「今ヒマ！」の人が表示される🚀", ephemeral=True
        )

    # ------------------------------------------------------------------ /hima

    @app_commands.command(name="hima", description="「今ヒマ！」として登録する")
    @app_commands.guild_only()
    async def hima(self, interaction: discord.Interaction) -> None:
        await interaction.response.send_message(view=HimaJoinView(self.bot), ephemeral=True)

    # ------------------------------------------------------------------ /hima_off

    @app_commands.command(name="hima_off", description="自分のヒマ登録をやめる")
    @app_commands.guild_only()
    async def hima_off(self, interaction: discord.Interaction) -> None:
        assert interaction.guild_id is not None
        if storage.delete_hima(interaction.guild_id, interaction.user.id):
            await self.bot.refresh_guild_list(interaction.guild_id)
            await interaction.response.send_message("登録をやめたよ！また誘ってね。", ephemeral=True)
        else:
            await interaction.response.send_message("今はヒマ登録されていないよ。", ephemeral=True)

    # ------------------------------------------------------------------ /hima_list

    @app_commands.command(name="hima_list", description="今ヒマな人の一覧を見る")
    @app_commands.guild_only()
    async def hima_list(self, interaction: discord.Interaction) -> None:
        assert interaction.guild_id is not None
        rows = storage.list_hima(interaction.guild_id, now=int(time.time()))
        await interaction.response.send_message(
            embed=build_list_embed(rows, self.bot.display_name), ephemeral=True
        )


def main() -> None:
    token: Optional[str] = os.getenv("DISCORD_TOKEN")
    if not token:
        print("DISCORD_TOKENが未設定です。.env に DISCORD_TOKEN=... を書いてから起動してください。")
        sys.exit(1)
    bot = HimaBot()
    bot.run(token)


if __name__ == "__main__":
    main()
