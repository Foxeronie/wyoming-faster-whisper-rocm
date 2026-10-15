"""Event handler for clients of the server."""

import argparse
import asyncio
import logging
import os
import tempfile
import wave
from typing import Iterable, Optional

import faster_whisper
from wyoming.asr import Transcribe, Transcript
from wyoming.audio import AudioChunk, AudioStop
from wyoming.event import Event
from wyoming.info import Describe, Info
from wyoming.server import AsyncEventHandler

_LOGGER = logging.getLogger(__name__)


def normalize_language(
    language: Optional[str], supported_languages: Iterable[str]
) -> Optional[str]:
    """Map a language code like "de-DE" to a code the model understands.

    Returns None (auto-detect) for "auto" and for unsupported languages, since
    faster-whisper fails the whole transcription on an unknown code.
    """
    if not language or language == "auto":
        return None

    code = language.replace("_", "-").split("-")[0].lower()
    if code not in supported_languages:
        _LOGGER.warning(
            "Language %s is not supported by the model, using auto-detection",
            language,
        )
        return None

    return code


class FasterWhisperEventHandler(AsyncEventHandler):
    """Event handler for clients."""

    def __init__(
        self,
        wyoming_info: Info,
        cli_args: argparse.Namespace,
        model: faster_whisper.WhisperModel,
        model_lock: asyncio.Lock,
        *args,
        initial_prompt: Optional[str] = None,
        **kwargs,
    ) -> None:
        super().__init__(*args, **kwargs)

        self.cli_args = cli_args
        self.wyoming_info_event = wyoming_info.event()
        self.model = model
        self.model_lock = model_lock
        self.initial_prompt = initial_prompt
        self._language = self.cli_args.language
        self._wav_dir = tempfile.TemporaryDirectory()
        self._wav_path = os.path.join(self._wav_dir.name, "speech.wav")
        self._wav_file: Optional[wave.Wave_write] = None

    async def handle_event(self, event: Event) -> bool:
        if AudioChunk.is_type(event.type):
            chunk = AudioChunk.from_event(event)

            if self._wav_file is None:
                self._wav_file = wave.open(self._wav_path, "wb")
                self._wav_file.setframerate(chunk.rate)
                self._wav_file.setsampwidth(chunk.width)
                self._wav_file.setnchannels(chunk.channels)

            self._wav_file.writeframes(chunk.audio)
            return True

        if AudioStop.is_type(event.type):
            _LOGGER.debug(
                "Audio stopped. Transcribing with initial prompt=%s",
                self.initial_prompt,
            )
            if self._wav_file is None:
                _LOGGER.warning("Received audio-stop without any audio")
                text = ""
            else:
                self._wav_file.close()
                self._wav_file = None

                async with self.model_lock:
                    # Run in a thread so the event loop stays responsive
                    text = await asyncio.to_thread(self._transcribe)

            _LOGGER.info(text)

            await self.write_event(Transcript(text=text).event())
            _LOGGER.debug("Completed request")

            # Reset
            self._language = self.cli_args.language

            return False

        if Transcribe.is_type(event.type):
            transcribe = Transcribe.from_event(event)
            if transcribe.language:
                self._language = normalize_language(
                    transcribe.language, self.model.supported_languages
                )
                _LOGGER.debug("Language set to %s", self._language)
            return True

        if Describe.is_type(event.type):
            await self.write_event(self.wyoming_info_event)
            _LOGGER.debug("Sent info")
            return True

        return True

    def _transcribe(self) -> str:
        segments, _info = self.model.transcribe(
            self._wav_path,
            beam_size=self.cli_args.beam_size,
            language=self._language,
            initial_prompt=self.initial_prompt,
        )

        # Segments are generated lazily, so decoding happens while joining.
        # Segment texts already carry a leading space.
        return "".join(segment.text for segment in segments).strip()
