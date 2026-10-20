#!/usr/bin/env python3

"""
Translate an SRT subtitle file using the OpenAI API.

Example:

    python translate_srt.py movie.srt movie.es.srt \
        --source English \
        --target Spanish

Requirements:

    pip install openai

Environment:

    export OPENAI_API_KEY="your-api-key"

The script preserves:
    - Subtitle numbers
    - Start/end timestamps
    - Subtitle ordering

Only the subtitle text is translated.
"""

import argparse
import re
import sys
import time
from pathlib import Path

from openai import OpenAI


# ---------------------------------------------------------------------------
# SRT parsing
# ---------------------------------------------------------------------------

SRT_BLOCK_RE = re.compile(
    r"^(\d+)\s*\n"
    r"(\d{2}:\d{2}:\d{2},\d{3}\s*-->\s*\d{2}:\d{2}:\d{2},\d{3}[^\n]*)\s*\n"
    r"([\s\S]*?)"
    r"(?=\n\s*\n|\Z)",
    re.MULTILINE,
)


def parse_srt(text):
    """
    Parse an SRT file into a list of dictionaries.

    Each entry looks like:

        {
            "number": 1,
            "timestamp": "00:00:01,000 --> 00:00:03,000",
            "text": "Hello world!"
        }
    """

    entries = []

    # Normalize line endings.
    text = text.replace("\r\n", "\n").replace("\r", "\n")

    for match in SRT_BLOCK_RE.finditer(text):
        number = int(match.group(1))
        timestamp = match.group(2).strip()
        subtitle_text = match.group(3).strip()

        entries.append(
            {
                "number": number,
                "timestamp": timestamp,
                "text": subtitle_text,
            }
        )

    return entries


def write_srt(entries):
    """Convert parsed subtitle entries back into SRT format."""

    blocks = []

    for entry in entries:
        blocks.append(
            f"{entry['number']}\n"
            f"{entry['timestamp']}\n"
            f"{entry['text']}"
        )

    return "\n\n".join(blocks) + "\n"


# ---------------------------------------------------------------------------
# OpenAI translation
# ---------------------------------------------------------------------------

def translate_batch(
    client,
    entries,
    source_language,
    target_language,
    model,
):
    """
    Translate a batch of subtitle entries.

    The model receives numbered subtitles and must return the same
    numbers with translated text.
    """

    subtitle_text = "\n\n".join(
        f"[{entry['number']}]\n{entry['text']}"
        for entry in entries
    )

    system_prompt = f"""
You are a professional movie and television subtitle translator.

Translate subtitles from {source_language} to {target_language}.

Important rules:

1. Preserve the meaning and tone of the original dialogue.
2. Use natural, idiomatic {target_language}; do not translate word-for-word
   when that would sound unnatural.
3. Preserve character names, proper nouns, places, brands, and terminology
   unless they normally have a translated form in {target_language}.
4. Preserve profanity and slang when appropriate to the original.
5. Keep the translation concise enough to work as subtitles.
6. Preserve line breaks inside an individual subtitle when practical.
7. NEVER add explanations, comments, translator notes, or quotation marks.
8. NEVER combine or split subtitle entries.
9. Every subtitle number must appear exactly once in the output.
10. Return ONLY the translated subtitles in this exact format:

[NUMBER]
translated text

[NUMBER]
translated text

Do not output anything before or after the subtitles.
"""

    user_prompt = f"""
Translate the following subtitle entries from {source_language}
to {target_language}.

{subtitle_text}
"""

    response = client.responses.create(
        model=model,
        instructions=system_prompt,
        input=user_prompt,
    )

    result = response.output_text.strip()

    return parse_translated_response(
        result,
        expected_numbers=[entry["number"] for entry in entries],
    )


def parse_translated_response(text, expected_numbers):
    """
    Parse the model's numbered translation back into subtitle entries.

    Expected format:

        [1]
        Hello.

        [2]
        How are you?
    """

    pattern = re.compile(
        r"\[(\d+)\]\s*\n([\s\S]*?)(?=\n\s*\[\d+\]\s*\n|\Z)"
    )

    translations = {}

    for match in pattern.finditer(text):
        number = int(match.group(1))
        translated_text = match.group(2).strip()

        translations[number] = translated_text

    # Validate that every subtitle was returned.
    missing = [
        number
        for number in expected_numbers
        if number not in translations
    ]

    if missing:
        raise ValueError(
            f"OpenAI response is missing subtitle(s): {missing}"
        )

    # Check for unexpected subtitle numbers.
    unexpected = [
        number
        for number in translations
        if number not in expected_numbers
    ]

    if unexpected:
        raise ValueError(
            f"OpenAI returned unexpected subtitle number(s): {unexpected}"
        )

    return translations


# ---------------------------------------------------------------------------
# Main translation process
# ---------------------------------------------------------------------------

def read_text_any_encoding(path):
    for encoding in ("utf-8-sig", "cp1252"):
        try:
            return path.read_text(encoding=encoding)
        except UnicodeDecodeError:
            continue
    return path.read_text(encoding="latin-1")


def translate_srt(
    input_file,
    output_file,
    source_language,
    target_language,
    model,
    batch_size,
    delay,
):
    client = OpenAI()

    input_path = Path(input_file)
    output_path = Path(output_file)

    print(f"Reading: {input_path}")

    text = read_text_any_encoding(input_path)

    entries = parse_srt(text)

    if not entries:
        raise ValueError("No valid SRT subtitle entries were found.")

    print(f"Found {len(entries)} subtitle entries.")

    # Translate batches while preserving the original entries.
    for start in range(0, len(entries), batch_size):
        end = min(start + batch_size, len(entries))

        batch = entries[start:end]

        print(
            f"Translating subtitles "
            f"{start + 1}-{end} / {len(entries)}..."
        )

        # Retry transient API failures.
        for attempt in range(3):
            try:
                translations = translate_batch(
                    client=client,
                    entries=batch,
                    source_language=source_language,
                    target_language=target_language,
                    model=model,
                )

                break

            except Exception as exc:
                if attempt == 2:
                    raise

                wait = 2 ** attempt

                print(
                    f"API error: {exc}\n"
                    f"Retrying in {wait} seconds...",
                    file=sys.stderr,
                )

                time.sleep(wait)

        # Replace ONLY the subtitle text.
        for entry in batch:
            entry["text"] = translations[entry["number"]]

        if delay > 0 and end < len(entries):
            time.sleep(delay)

    output_path.write_text(
        write_srt(entries),
        encoding="utf-8",
    )

    print(f"\nDone.")
    print(f"Output: {output_path}")


# ---------------------------------------------------------------------------
# Command-line interface
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Translate an SRT subtitle file using OpenAI."
    )

    parser.add_argument(
        "input",
        help="Input .srt file",
    )

    parser.add_argument(
        "output",
        help="Output .srt file",
    )

    parser.add_argument(
        "--source",
        default="English",
        help="Source language (default: English)",
    )

    parser.add_argument(
        "--target",
        default="Spanish",
        help="Destination language (default: Spanish)",
    )

    parser.add_argument(
        "--model",
        default="gpt-5.6-luna",
        help="OpenAI model to use (default: gpt-5.6-luna)",
    )

    parser.add_argument(
        "--batch-size",
        type=int,
        default=40,
        help="Number of subtitle entries per API request (default: 40)",
    )

    parser.add_argument(
        "--delay",
        type=float,
        default=0,
        help="Delay between API requests in seconds (default: 0)",
    )

    args = parser.parse_args()

    if args.batch_size < 1:
        parser.error("--batch-size must be at least 1")

    if not Path(args.input).exists():
        parser.error(f"Input file does not exist: {args.input}")

    translate_srt(
        input_file=args.input,
        output_file=args.output,
        source_language=args.source,
        target_language=args.target,
        model=args.model,
        batch_size=args.batch_size,
        delay=args.delay,
    )


if __name__ == "__main__":
    main()
