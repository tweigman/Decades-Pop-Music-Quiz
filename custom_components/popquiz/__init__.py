"""Pop Quiz: a name-that-tune game for Home Assistant Assist.

Home Assistant imports stay inside functions so the game engine can be
imported and tested without Home Assistant installed.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import TYPE_CHECKING

from .const import DOMAIN

if TYPE_CHECKING:
    from homeassistant.config_entries import ConfigEntry
    from homeassistant.core import HomeAssistant

    from .data import Library

PLATFORMS = ["conversation"]
CLIPS_URL = f"/api/{DOMAIN}/clips"
SOUNDS_URL = f"/api/{DOMAIN}/sounds"


@dataclass
class PopQuizData:
    library: Library
    data_dir: Path
    clips_dir: Path
    ffmpeg: str


async def async_setup_entry(hass: HomeAssistant, entry: ConfigEntry) -> bool:
    from homeassistant.components.ffmpeg import get_ffmpeg_manager
    from homeassistant.components.http import StaticPathConfig
    from homeassistant.exceptions import ConfigEntryError

    from .data import Library

    data_dir = Path(hass.config.path(DOMAIN))
    library = await hass.async_add_executor_job(Library, data_dir)
    if not library.categories:
        raise ConfigEntryError(f"No playable songs found in {data_dir}")

    clips_dir = data_dir / ".clips"
    await hass.async_add_executor_job(lambda: clips_dir.mkdir(exist_ok=True))

    # Static paths can't be unregistered, so only add them once per run.
    if not hass.data.get(DOMAIN):
        await hass.http.async_register_static_paths(
            [
                StaticPathConfig(CLIPS_URL, str(clips_dir), False),
                StaticPathConfig(SOUNDS_URL, str(data_dir / "sounds"), True),
            ]
        )
        hass.data[DOMAIN] = True

    entry.runtime_data = PopQuizData(
        library, data_dir, clips_dir, get_ffmpeg_manager(hass).binary
    )
    await hass.config_entries.async_forward_entry_setups(entry, PLATFORMS)
    return True


async def async_unload_entry(hass: HomeAssistant, entry: ConfigEntry) -> bool:
    return await hass.config_entries.async_unload_platforms(entry, PLATFORMS)
