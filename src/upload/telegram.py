import asyncio
import fcntl
import subprocess
import json as _json
from pathlib import Path
from telethon import TelegramClient
from telethon.tl.types import DocumentAttributeVideo
from utils.logger_manager import logger
from utils.utils import read_telegram_config

FREE_USER_MAX_FILE_SIZE = 2 * 1024 * 1024 * 1024
PREMIUM_USER_MAX_FILE_SIZE = 4 * 1024 * 1024 * 1024

LOCK_FILE = Path(__file__).resolve().parent / ".telegram_upload.lock"

def _probe_video(file_path: str):
    try:
        result = subprocess.run(
            [
                "ffprobe", "-v", "error", "-select_streams", "v:0",
                "-show_entries", "stream=width,height",
                "-show_entries", "format=duration", "-of", "json",
                file_path,
            ],
            capture_output=True, text=True, timeout=30,
        )
        data = _json.loads(result.stdout)
        stream = data.get("streams", [{}])[0]
        fmt = data.get("format", {})
        width = int(stream.get("width", 0) or 0)
        height = int(stream.get("height", 0) or 0)
        duration = int(float(fmt.get("duration", 0) or 0))
        return duration, width, height
    except Exception as e:
        logger.warning(f"Could not probe video metadata: {e}")
        return 0, 0, 0

class Telegram:
    def __init__(self):
        config = read_telegram_config()
        self.api_id = config["api_id"]
        self.api_hash = config["api_hash"]
        self.chat_id = config["chat_id"]
        self.client = TelegramClient(
            "tiktok_live_recorder_session",
            api_id=self.api_id,
            api_hash=self.api_hash,
        )

    def upload(self, file_path: str) -> bool:
        LOCK_FILE.touch(exist_ok=True)
        with open(LOCK_FILE, "w") as lock_f:
            logger.info("Waiting for Telegram upload slot (uploads run one at a time)...")
            fcntl.flock(lock_f, fcntl.LOCK_EX)
            try:
                logger.info("Got upload slot, starting Telegram upload.")
                return self._do_upload(file_path)
            finally:
                fcntl.flock(lock_f, fcntl.LOCK_UN)

    def _do_upload(self, file_path: str) -> bool:
        async def _upload() -> bool:
            try:
                await self.client.connect()
                if not await self.client.is_user_authorized():
                    await self.client.start()
                me = await self.client.get_me()
                max_size = PREMIUM_USER_MAX_FILE_SIZE if me.premium else FREE_USER_MAX_FILE_SIZE
                file_size = Path(file_path).stat().st_size
                logger.info(f"File to upload: {Path(file_path).name} ({round(file_size/(1024*1024))} MB)")
                if file_size > max_size:
                    logger.warning("The file is too large to be uploaded with this type of account.")
                    return False
                duration, width, height = _probe_video(file_path)
                video_attrs = [DocumentAttributeVideo(duration=duration, w=width, h=height, supports_streaming=True)]
                logger.info("Uploading video on Telegram... This may take a while depending on file size.")
                await self.client.send_file(
                    entity=self.chat_id,
                    file=file_path,
                    caption='🎥 <b>Video recorded via <a href="https://github.com/Michele0303/tiktok-live-recorder">TikTok Live Recorder</a></b>',
                    parse_mode="html",
                    force_document=False,
                    supports_streaming=True,
                    attributes=video_attrs,
                )
                logger.info("File successfully uploaded to Telegram.\n")
                return True
            except Exception as e:
                logger.error(f"Error during Telegram upload: {e}\n", exc_info=True)
                return False
            finally:
                await self.client.disconnect()
        return asyncio.run(_upload())
