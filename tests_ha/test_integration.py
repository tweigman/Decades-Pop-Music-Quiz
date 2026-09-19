"""Run the integration inside a real Home Assistant core (no UI, no network).

Needs Home Assistant's test harness, which the plain unit tests don't:
    pip install pytest-homeassistant-custom-component
    pytest tests_ha
"""

import asyncio
from pathlib import Path

import pytest
from homeassistant.components import conversation
from homeassistant.core import Context, HomeAssistant
from homeassistant.helpers import device_registry as dr, entity_registry as er
from homeassistant.setup import async_setup_component
from pytest_homeassistant_custom_component.common import (
    MockConfigEntry,
    async_mock_service,
)

REPO = Path(__file__).resolve().parent.parent
AGENT = "conversation.pop_quiz"
SATELLITE = "assist_satellite.kitchen_dot"


@pytest.fixture(autouse=True)
def auto_enable_custom_integrations(enable_custom_integrations):
    yield


@pytest.fixture
async def setup(hass: HomeAssistant, tmp_path):
    data = tmp_path / "popquiz"
    data.mkdir()
    for name in ("categories", "previews", "sounds"):
        (data / name).symlink_to(REPO / name)
    hass.config.config_dir = str(tmp_path)
    assert await async_setup_component(hass, "homeassistant", {})

    entry = MockConfigEntry(domain="popquiz")
    entry.add_to_hass(hass)
    assert await hass.config_entries.async_setup(entry.entry_id)
    await hass.async_block_till_done()

    device = dr.async_get(hass).async_get_or_create(
        config_entry_id=entry.entry_id, identifiers={("test", "dot")}
    )
    er.async_get(hass).async_get_or_create(
        "assist_satellite", "test", "dot", device_id=device.id,
        suggested_object_id="kitchen_dot",
    )  # fmt: skip
    hass.states.async_set(SATELLITE, "idle")
    calls = async_mock_service(hass, "assist_satellite", "start_conversation")
    return device.id, calls, data


async def say(hass, text, device_id):
    return await conversation.async_converse(
        hass, text, None, Context(), language="en", agent_id=AGENT,
        device_id=device_id,
    )  # fmt: skip


async def satellite_speaks(hass):
    """Simulate the satellite speaking the reply and going idle again."""
    await asyncio.sleep(0.3)
    hass.states.async_set(SATELLITE, "responding")
    await asyncio.sleep(0.3)
    hass.states.async_set(SATELLITE, "idle")
    await asyncio.sleep(0.8)
    await hass.async_block_till_done()


async def test_game_flow_plays_clips(hass: HomeAssistant, setup):
    device_id, calls, data = setup

    result = await say(hass, "Play Pop Quiz.", device_id)
    assert "How many players" in result.response.speech["plain"]["speech"]
    assert result.continue_conversation

    result = await say(hass, "Two.", device_id)
    assert "Pick a category" in result.response.speech["plain"]["speech"]

    result = await say(hass, "The eighties", device_id)
    speech = result.response.speech["plain"]["speech"]
    assert "Player 1, here's your song" in speech
    assert not result.continue_conversation  # the clip's conversation listens

    await satellite_speaks(hass)
    assert len(calls) == 1
    call = calls[0].data
    assert call["entity_id"] == SATELLITE
    assert call["start_media_id"].startswith("/api/popquiz/clips/")
    assert call["preannounce"] is False
    clip = data / ".clips" / call["start_media_id"].rsplit("/", 1)[1]
    assert clip.stat().st_size > 10_000

    result = await say(hass, "repeat", device_id)
    assert result.response.speech["plain"]["speech"] == "Here it is again."
    await satellite_speaks(hass)
    assert len(calls) == 2

    result = await say(hass, "exit game now", device_id)
    assert "Thanks for playing" in result.response.speech["plain"]["speech"]


async def test_other_commands_go_to_home_assistant(hass: HomeAssistant, setup):
    device_id, calls, _ = setup
    await hass.async_block_till_done()
    result = await say(hass, "turn on the tall lamp", device_id)
    speech = result.response.speech["plain"]["speech"]
    assert "player" not in speech.lower()
    assert result.response.intent is None or result.response.error_code is not None
    assert not calls
