"""hima-bot entry point: startup, slash commands, background cleanup loop."""
from __future__ import annotations

import asyncio
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
    PANEL_CUSTOM_IDS,
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
        # Non-privileged standard intents only (presence / server members / message
        # content all stay off, so no privileged intents are enabled).
        super().__init__(command_prefix="!", intents=discord.Intents.default())
        self.display_name = os.getenv("BOT_DISPLAY_NAME") or DEFAULT_DISPLAY_NAME
        # /panel_setup のサーバー単位ロック（同時実行防止）
        self.panel_setup_locks: dict[int, asyncio.Lock] = {}

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
        """Purge expired registrations, remove their announcements and stale knock DMs."""
        now = int(time.time())
        expired_rows = storage.purge_expired(now)
        for row in expired_rows:
            await self.delete_stored_message(row["guild_id"], row["announce_message_id"])
        for knock in storage.list_unanswered_knocks():
            from_alive = storage.get_hima(knock["guild_id"], knock["from_user_id"]) is not None
            to_alive = storage.get_hima(knock["guild_id"], knock["to_user_id"]) is not None
            if from_alive and to_alive:
                continue
            await self.delete_knock_dm(knock["to_user_id"], knock["dm_message_id"])
            storage.update_knock_status(knock["id"], "expired")
        changed_guilds = {row["guild_id"] for row in expired_rows}
        for guild_id in changed_guilds:
            await self.refresh_guild_list(guild_id)

    async def delete_stored_message(self, guild_id: int, message_id: Optional[int]) -> None:
        """Delete a bot-posted message in the configured panel channel. Failures are logged only."""
        if message_id is None:
            return
        try:
            cfg = storage.get_guild_config(guild_id)
            if cfg is None:
                return
            channel = self.get_channel(cfg["channel_id"])
            if channel is None:
                channel = await self.fetch_channel(cfg["channel_id"])
            await channel.delete_message(discord.Object(id=message_id))
        except Exception as exc:  # noqa: BLE001 - cleanup must not break the flow
            print(f"[hima-bot] メッセージの削除に失敗しました（無視します）: {exc}")

    async def delete_knock_dm(self, to_user_id: int, message_id: Optional[int]) -> None:
        """Delete a previously sent knock DM. Failures are logged only."""
        if message_id is None:
            return
        try:
            user = await self.fetch_user(to_user_id)
            dm = await user.create_dm()
            await dm.delete_message(discord.Object(id=message_id))
        except Exception as exc:  # noqa: BLE001 - cleanup must not break the flow
            print(f"[hima-bot] ノックDMの削除に失敗しました（無視します）: {exc}")

    async def announce_hima(
        self,
        guild_id: int,
        display_name: str,
        minutes: int,
        mood_label: str,
        activity: str,
        note: str,
        method: str,
    ) -> None:
        """Announce a registration to the panel channel per the chosen method.

        silent: nothing. message: plain text. mention: @here with everyone=True.
        Returns the posted message id (None when silent/failed).
        Failures are only logged and never break the registration flow.
        """
        try:
            if method not in ("message", "mention"):
                return None
            cfg = storage.get_guild_config(guild_id)
            if cfg is None:
                return None
            channel = self.get_channel(cfg["channel_id"])
            if channel is None:
                channel = await self.fetch_channel(cfg["channel_id"])
            text = f"🙋 {display_name} さんがヒマ宣言したよ！ あと{minutes}分 ｜ {mood_label} ｜ {activity}"
            if note:
                text += f"（ひとこと：{note}）"
            if method == "mention":
                text = "@here " + text
                message = await channel.send(text, allowed_mentions=discord.AllowedMentions(everyone=True))
            else:
                message = await channel.send(text)
            return message.id
        except Exception as exc:  # noqa: BLE001 - announcement failure must not break registration
            print(f"[hima-bot] 告知の送信に失敗しました（登録は完了済み）: {exc}")
            return None


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
        has_manage_guild = bool(getattr(interaction.permissions, "manage_guild", False))
        is_owner = False
        if interaction.guild is not None and interaction.user.id == interaction.guild.owner_id:
            is_owner = True
        if not (has_manage_guild or is_owner):
            await interaction.response.send_message(
                "このコマンドはサーバー管理権限のある人だけが使えるよ。", ephemeral=True
            )
            return
        # サーバー単位のロック：実行中に再度呼ばれたら何もしない
        assert interaction.guild_id is not None
        lock = self.bot.panel_setup_locks.setdefault(interaction.guild_id, asyncio.Lock())
        if not lock.acquire(blocking=False):
            await interaction.response.send_message("設置処理中です。少し待ってからもう一度試してね。", ephemeral=True)
            return
        try:
            channel = interaction.channel
            assert channel is not None and hasattr(channel, "send")
            # 1) チャンネル履歴（直近200件）から旧パネル/旧一覧を掃除する
            async for message in channel.history(limit=200):
                if message.author.id != self.bot.user.id:
                    continue
                is_panel = any(
                    getattr(child, "custom_id", None) in PANEL_CUSTOM_IDS
                    for row in message.components
                    for child in row.children
                )
                is_list = any(
                    embed.title is not None and ("掲示板" in embed.title or "メンバー一覧" in embed.title)
                    for embed in message.embeds
                )
                if not (is_panel or is_list):
                    continue
                try:
                    await message.delete()
                except Exception as exc:  # noqa: BLE001 - cleanup must not break setup
                    print(f"[hima-bot] 旧パネル/一覧の削除に失敗しました（無視します）: {exc}")
            # 2) 保険：保存済みIDの削除（履歴200件より古い分。重複削除は無視）
            old_cfg = storage.get_guild_config(interaction.guild_id)
            if old_cfg is not None:
                for message_id in (old_cfg["panel_message_id"], old_cfg["list_message_id"]):
                    try:
                        old_channel = self.bot.get_channel(old_cfg["channel_id"])
                        if old_channel is None:
                            old_channel = await self.bot.fetch_channel(old_cfg["channel_id"])
                        old_message = await old_channel.fetch_message(message_id)
                        await old_message.delete()
                    except Exception as exc:  # noqa: BLE001 - cleanup must not break setup
                        print(f"[hima-bot] 旧パネル/一覧の削除に失敗しました（無視します）: {exc}")
            # 3) 新しいパネルと一覧を投稿して guild_config を更新
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
        finally:
            lock.release()

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
        row = storage.get_hima(interaction.guild_id, interaction.user.id)
        if row is None:
            await interaction.response.send_message("今はヒマ登録されていないよ。", ephemeral=True)
            return
        storage.delete_hima(interaction.guild_id, interaction.user.id)
        await self.bot.delete_stored_message(interaction.guild_id, row["announce_message_id"])
        await self.bot.refresh_guild_list(interaction.guild_id)
        await interaction.response.send_message("登録をやめたよ！また誘ってね。", ephemeral=True)

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
