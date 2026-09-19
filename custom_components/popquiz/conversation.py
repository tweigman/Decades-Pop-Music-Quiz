"""The Pop Quiz conversation agent.

Set this as the conversation agent of the voice pipeline your satellite uses.
"Play Pop Quiz" starts a game; everything else goes to Home Assistant's
built-in agent unless a game is running on that satellite.

A reply can't contain a song, so clips are played afterwards: once the
satellite has finished speaking, assist_satellite.start_conversation plays
the clip and then listens for the answer, which comes back here.
"""

from __future__ import annotations

import asyncio
import logging
import time
from typing import Literal

from homeassistant.components import conversation
from homeassistant.components.conversation import (
    ConversationEntity,
    ConversationInput,
    ConversationResult,
)
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.helpers import entity_registry as er, intent

from . import CLIPS_URL, SOUNDS_URL, PopQuizData
from .clips import render_clip
from .const import BONUS_INTRO_FILE, GAME_IDLE_TIMEOUT_MIN, POST_SPEECH_DELAY
from .game import Game, Reply
from .grading import is_start

_LOGGER = logging.getLogger(__name__)


async def async_setup_entry(
    hass: HomeAssistant, entry: ConfigEntry, async_add_entities
) -> None:
    async_add_entities([PopQuizAgent(entry)])


class PopQuizAgent(ConversationEntity):
    _attr_has_entity_name = True
    _attr_name = "Pop Quiz"

    def __init__(self, entry: ConfigEntry) -> None:
        self._data: PopQuizData = entry.runtime_data
        self._attr_unique_id = entry.entry_id
        self._games: dict[str, Game] = {}  # one game per satellite
        self._tasks: set[asyncio.Task] = set()

    @property
    def supported_languages(self) -> list[str] | Literal["*"]:
        return ["en"]

    async def async_will_remove_from_hass(self) -> None:
        for task in self._tasks:
            task.cancel()

    async def async_process(self, user_input: ConversationInput) -> ConversationResult:
        key = user_input.device_id or user_input.conversation_id or "default"
        game = self._games.get(key)
        if game and time.monotonic() - game.last_activity > GAME_IDLE_TIMEOUT_MIN * 60:
            del self._games[key]
            game = None

        if is_start(user_input.text):
            game = self._games[key] = Game(self._data.library)
            reply = game.start()
        elif game is None:
            return await conversation.async_converse(
                self.hass,
                user_input.text,
                user_input.conversation_id,
                user_input.context,
                language=user_input.language,
                agent_id=conversation.HOME_ASSISTANT_AGENT,
                device_id=user_input.device_id,
                satellite_id=user_input.satellite_id,
            )
        else:
            reply = game.handle(user_input.text)

        if reply.done:
            self._games.pop(key, None)
        if reply.clip:
            satellite = self._find_satellite(user_input)
            if satellite is None:
                self._games.pop(key, None)
                return _result(
                    user_input,
                    "Pop Quiz needs a voice satellite to play songs. "
                    "Try again from a smart speaker.",
                    listen=False,
                )
            task = self.hass.async_create_background_task(
                self._play_clip(satellite, reply), f"{self.entity_id} play clip"
            )
            self._tasks.add(task)
            task.add_done_callback(self._tasks.discard)

        # A reply can't put speech after the bonus sound, so on a satellite the
        # bonus announcement is spoken first and the sound plays before the clip.
        speech = f"{reply.speech} {reply.bonus_speech}".strip()
        return _result(user_input, speech, listen=reply.listen)

    def _find_satellite(self, user_input: ConversationInput) -> str | None:
        if user_input.satellite_id and user_input.satellite_id.startswith(
            "assist_satellite."
        ):
            return user_input.satellite_id
        if not user_input.device_id:
            return None
        registry = er.async_get(self.hass)
        for entry in er.async_entries_for_device(registry, user_input.device_id):
            if entry.domain == "assist_satellite":
                return entry.entity_id
        return None

    async def _play_clip(self, satellite: str, reply: Reply) -> None:
        """Wait for the satellite to finish speaking, then play the clip and listen."""
        try:
            path, _ = await asyncio.gather(
                render_clip(self._data.ffmpeg, reply.clip, self._data.clips_dir),
                self._wait_until_idle(satellite),
            )
            await asyncio.sleep(POST_SPEECH_DELAY)
            bonus = self._data.data_dir / BONUS_INTRO_FILE
            play_bonus = bool(reply.bonus_speech) and await self.hass.async_add_executor_job(
                bonus.is_file
            )
            await self.hass.services.async_call(
                "assist_satellite",
                "start_conversation",
                {
                    "entity_id": satellite,
                    "start_media_id": f"{CLIPS_URL}/{path.name}",
                    "preannounce": play_bonus,
                    **(
                        {"preannounce_media_id": f"{SOUNDS_URL}/{bonus.name}"}
                        if play_bonus
                        else {}
                    ),
                },
                blocking=True,
            )
        except asyncio.CancelledError:
            raise
        except Exception:
            _LOGGER.exception("Pop Quiz could not play a clip on %s", satellite)

    async def _wait_until_idle(self, satellite: str, timeout: float = 90) -> None:
        """Wait for the satellite to go busy (speaking our reply) and back to idle."""
        loop = asyncio.get_running_loop()
        start = loop.time()
        seen_busy = False
        while loop.time() - start < timeout:
            state = self.hass.states.get(satellite)
            idle = state is None or state.state == "idle"
            if not idle:
                seen_busy = True
            elif seen_busy or loop.time() - start > 5:
                return
            await asyncio.sleep(0.2)


def _result(user_input: ConversationInput, speech: str, listen: bool) -> ConversationResult:
    response = intent.IntentResponse(language=user_input.language)
    response.async_set_speech(speech)
    return ConversationResult(
        response=response,
        conversation_id=user_input.conversation_id,
        continue_conversation=listen,
    )
