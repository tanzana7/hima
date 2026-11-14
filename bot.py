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
    BoardView,
    HimaJoinView,
    HimaPanelView,
    KnockReplyButton,
    KnockView,
    build_board_components,
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
        # Persistent panel/board views + dynamic knock-reply buttons survive restarts.
        self.add_view(HimaPanelView(self))
        self.add_view(BoardView(self))
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
            # DM配送廃止に伴い、受信箱から消えるようステータス更新のみ行う。
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

    async def sweep_panel_messages(self, channel: discord.abc.Messageable, guild_id: int) -> tuple[int, int, int]:
        """旧パネル/旧一覧を掃除する（履歴200件+保存IDの保険）。戻り値は (panels, lists, failures)。"""
        scanned = 0
        swept_panels = 0
        swept_lists = 0
        sweep_failures = 0
        async for message in channel.history(limit=200):
            if message.author.id != self.user.id:
                continue
            scanned += 1
            matched_panel = any(
                getattr(child, "custom_id", None) in PANEL_CUSTOM_IDS
                for row in message.components
                for child in row.children
            )
            matched_list = any(
                embed.title is not None and ("掲示板" in embed.title or "メンバー一覧" in embed.title)
                for embed in message.embeds
            )
            if not (matched_panel or matched_list):
                continue
            try:
                await message.delete()
            except Exception as exc:  # noqa: BLE001 - cleanup must not break setup
                sweep_failures += 1
                print(f"[hima-bot] 旧パネル/一覧の削除に失敗しました（無視します）: {exc}")
            else:
                swept_panels += int(matched_panel)
                swept_lists += int(matched_list)
        print(
            f"[hima-bot][sweep] scanned={scanned} panel={swept_panels} list={swept_lists} "
            f"deleted_ok={swept_panels + swept_lists} deleted_fail={sweep_failures}"
        )
        # 保険：保存済みIDの削除（履歴200件より古い分。重複削除は無視）
        old_cfg = storage.get_guild_config(guild_id)
        if old_cfg is not None:
            for message_id in (old_cfg["panel_message_id"], old_cfg["list_message_id"]):
                try:
                    old_channel = self.get_channel(old_cfg["channel_id"])
                    if old_channel is None:
                        old_channel = await self.fetch_channel(old_cfg["channel_id"])
                    old_message = await old_channel.fetch_message(message_id)
                    await old_message.delete()
                except Exception as exc:  # noqa: BLE001 - cleanup must not break setup
                    print(f"[hima-bot] 旧パネル/一覧の削除に失敗しました（無視します）: {exc}")
        if swept_panels == 0 or swept_lists == 0:
            await self._log_panel_structure_diagnostics(channel, guild_id)
        return swept_panels, swept_lists, sweep_failures

    async def _log_panel_structure_diagnostics(self, channel: discord.abc.Messageable, guild_id: int) -> None:
        """該当0件のとき、実物のメッセージ構造をログに出して判定条件との食い違いを特定する。"""
        try:
            candidates = []
            old_cfg = storage.get_guild_config(guild_id)
            if old_cfg is not None:
                try:
                    old_channel = self.get_channel(old_cfg["channel_id"])
                    if old_channel is None:
                        old_channel = await self.fetch_channel(old_cfg["channel_id"])
                    for message_id in (old_cfg["panel_message_id"], old_cfg["list_message_id"]):
                        try:
                            candidates.append(await old_channel.fetch_message(message_id))
                        except Exception as exc:  # noqa: BLE001 - diagnostics only
                            print(f"[hima-bot][sweep-diag] 保存ID {message_id} の取得に失敗: {exc}")
                except Exception as exc:  # noqa: BLE001 - diagnostics only
                    print(f"[hima-bot][sweep-diag] 保存チャンネルの取得に失敗: {exc}")
            if not candidates:
                async for message in channel.history(limit=200):
                    if message.author.id == self.user.id and message.components:
                        candidates.append(message)
                        break
            if not candidates:
                print("[hima-bot][sweep-diag] 構造を確認できるBotメッセージが見つかりませんでした")
                return
            for probe in candidates:
                rows = [
                    [
                        {
                            "type": type(child).__name__,
                            "custom_id": getattr(child, "custom_id", None),
                            "label": getattr(child, "label", None),
                        }
                        for child in row.children
                    ]
                    for row in probe.components
                ]
                titles = [embed.title for embed in probe.embeds]
                print(
                    f"[hima-bot][sweep-diag] message_id={probe.id} author={probe.author.id} "
                    f"components={rows} embed_titles={titles}"
                )
        except Exception as exc:  # noqa: BLE001 - diagnostics must never break setup
            print(f"[hima-bot][sweep-diag] 診断自体が失敗: {exc}")

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
        description="ヒマパネルと一覧をこのチャンネルに設置する（サーバーのメンバーなら誰でも実行できます）",
    )
    @app_commands.guild_only()
    async def panel_setup(self, interaction: discord.Interaction) -> None:
        # 3秒制限対策：まず応答を保留しておき、完了後に followup で返す
        assert interaction.guild_id is not None
        await interaction.response.defer(ephemeral=True)
        # サーバー単位のロック：実行中に再度呼ばれたら何もしない
        lock = self.bot.panel_setup_locks.setdefault(interaction.guild_id, asyncio.Lock())
        if lock.locked():
            await interaction.followup.send("設置処理中です。少し待ってからもう一度試してね。", ephemeral=True)
            return
        async with lock:
            channel = interaction.channel
            assert channel is not None and hasattr(channel, "send")
            # 1) 旧パネル/旧一覧を掃除（履歴200件+保存IDの保険）
            swept_panels, swept_lists, sweep_failures = await self.bot.sweep_panel_messages(
                channel, interaction.guild_id
            )
            # 2) 新しいパネルと一覧を投稿して guild_config を更新
            panel_message = await channel.send(
                embed=build_panel_embed(self.bot.display_name), view=HimaPanelView(self.bot)
            )
            list_message = await channel.send(embed=build_list_embed([], self.bot.display_name))
            storage.set_guild_config(
                interaction.guild_id, channel.id, panel_message.id, list_message.id
            )
            await interaction.followup.send(
                f"パネルと一覧を設置したよ！ここに「今ヒマ！」の人が表示される🚀\n"
                f"掃除：パネル{swept_panels}件・一覧{swept_lists}件を削除しました"
                + (f"・削除失敗{sweep_failures}件" if sweep_failures else ""),
                ephemeral=True,
            )

    # ------------------------------------------------------------------ /panel_remove

    @app_commands.command(
        name="panel_remove",
        description="このチャンネルの公開パネル/掲示板を全部削除する",
    )
    @app_commands.guild_only()
    async def panel_remove(self, interaction: discord.Interaction) -> None:
        assert interaction.guild_id is not None
        await interaction.response.defer(ephemeral=True)
        channel = interaction.channel
        assert channel is not None
        swept_panels, swept_lists, sweep_failures = await self.bot.sweep_panel_messages(
            channel, interaction.guild_id
        )
        storage.delete_guild_config(interaction.guild_id)
        await interaction.followup.send(
            f"公開パネルと掲示板を削除したよ（パネル{swept_panels}件・一覧{swept_lists}件"
            + (f"・削除失敗{sweep_failures}件" if sweep_failures else "") + "）。\n"
            "このサーバーでは公開掲示板の自動更新とお知らせは止まるよ。個人用は /board からどうぞ！",
            ephemeral=True,
        )

    # ------------------------------------------------------------------ /board

    @app_commands.command(name="board", description="自分専用の掲示板（受信箱つき）を開く")
    @app_commands.guild_only()
    async def board(self, interaction: discord.Interaction) -> None:
        assert interaction.guild_id is not None
        await interaction.response.defer(ephemeral=True)
        embeds, view, result_ids = await build_board_components(
            self.bot, interaction.guild_id, interaction.user.id
        )
        await interaction.followup.send(embeds=embeds, view=view, ephemeral=True)
        if result_ids:
            storage.mark_results_seen(result_ids)

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
