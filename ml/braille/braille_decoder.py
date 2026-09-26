"""
Deterministic Grade 1 Braille Decoder Module.
Implements standard Grade 1 English Braille mappings:
- 6-dot pattern -> Braille character
- a-z alphabetic characters
- Number sign indicator (#) and numeric mode digits 0-9
- Capital indicator prefix
- Standard punctuation and Grade 1 symbols
- Unicode Braille conversion (0x2800 to 0x283F)
- Optional Liblouis Grade 2 translation hook
"""

from typing import Tuple, List, Dict, Optional, Union, Any

# Standard 6-dot pattern representation: (d1, d2, d3, d4, d5, d6) where each di is 0 or 1.
# Column 0: d1 (row 0), d2 (row 1), d3 (row 2)
# Column 1: d4 (row 0), d5 (row 1), d6 (row 2)

BRAILLE_MAP_GRADE1: Dict[Tuple[int, int, int, int, int, int], str] = {
    # Letters a-z
    (1, 0, 0, 0, 0, 0): "a",
    (1, 1, 0, 0, 0, 0): "b",
    (1, 0, 0, 1, 0, 0): "c",
    (1, 0, 0, 1, 1, 0): "d",
    (1, 0, 0, 0, 1, 0): "e",
    (1, 1, 0, 1, 0, 0): "f",
    (1, 1, 0, 1, 1, 0): "g",
    (1, 1, 0, 0, 1, 0): "h",
    (0, 1, 0, 1, 0, 0): "i",
    (0, 1, 0, 1, 1, 0): "j",
    (1, 0, 1, 0, 0, 0): "k",
    (1, 1, 1, 0, 0, 0): "l",
    (1, 0, 1, 1, 0, 0): "m",
    (1, 0, 1, 1, 1, 0): "n",
    (1, 0, 1, 0, 1, 0): "o",
    (1, 1, 1, 1, 0, 0): "p",
    (1, 1, 1, 1, 1, 0): "q",
    (1, 1, 1, 0, 1, 0): "r",
    (0, 1, 1, 1, 0, 0): "s",
    (0, 1, 1, 1, 1, 0): "t",
    (1, 0, 1, 0, 0, 1): "u",
    (1, 1, 1, 0, 0, 1): "v",
    (0, 1, 0, 1, 1, 1): "w",
    (1, 0, 1, 1, 0, 1): "x",
    (1, 0, 1, 1, 1, 1): "y",
    (1, 0, 1, 0, 1, 1): "z",

    # Punctuation & common symbols
    (0, 1, 0, 0, 0, 0): ",",    # Dot 2: comma
    (0, 1, 1, 0, 0, 0): ";",    # Dots 2,3: semicolon
    (0, 1, 0, 0, 1, 0): ":",    # Dots 2,5: colon
    (0, 1, 0, 0, 1, 1): ".",    # Dots 2,5,6: period
    (0, 1, 1, 0, 1, 0): "!",    # Dots 2,3,5: exclamation
    (0, 1, 1, 0, 0, 1): "?",    # Dots 2,3,6: question mark / opening quote
    (0, 0, 0, 0, 1, 1): '"',    # Dots 5,6: closing quote
    (0, 0, 1, 0, 0, 0): "'",    # Dot 3: apostrophe
    (0, 0, 1, 0, 0, 1): "-",    # Dots 3,6: hyphen
    (0, 0, 1, 1, 0, 0): "/",    # Dots 3,4: slash
    (0, 1, 1, 0, 1, 1): "(",    # Dots 2,3,5,6: opening parenthesis
    (0, 0, 0, 0, 0, 0): " ",    # Empty cell: space
}

# Number mapping for digits 0-9 in Number Mode
NUMBER_MAP: Dict[Tuple[int, int, int, int, int, int], str] = {
    (1, 0, 0, 0, 0, 0): "1",  # a
    (1, 1, 0, 0, 0, 0): "2",  # b
    (1, 0, 0, 1, 0, 0): "3",  # c
    (1, 0, 0, 1, 1, 0): "4",  # d
    (1, 0, 0, 0, 1, 0): "5",  # e
    (1, 1, 0, 1, 0, 0): "6",  # f
    (1, 1, 0, 1, 1, 0): "7",  # g
    (1, 1, 0, 0, 1, 0): "8",  # h
    (0, 1, 0, 1, 0, 0): "9",  # i
    (0, 1, 0, 1, 1, 0): "0",  # j
}

# Indicators
PATTERN_NUMBER_SIGN = (0, 0, 1, 1, 1, 1)  # Dots 3,4,5,6 (#)
PATTERN_CAPITAL_SIGN = (0, 0, 0, 0, 0, 1) # Dot 6 (capital indicator)


def pattern_to_unicode(dots: Union[Tuple[int, ...], List[int]], empty_as_space: bool = False) -> str:
    """
    Converts 6-dot boolean pattern to Unicode Braille pattern character (U+2800 to U+283F).
    Formula: 0x2800 + (d1*1 + d2*2 + d3*4 + d4*8 + d5*16 + d6*32)
    """
    d1 = 1 if len(dots) > 0 and dots[0] else 0
    d2 = 1 if len(dots) > 1 and dots[1] else 0
    d3 = 1 if len(dots) > 2 and dots[2] else 0
    d4 = 1 if len(dots) > 3 and dots[3] else 0
    d5 = 1 if len(dots) > 4 and dots[4] else 0
    d6 = 1 if len(dots) > 5 and dots[5] else 0

    mask = (d1 * 1) + (d2 * 2) + (d3 * 4) + (d4 * 8) + (d5 * 16) + (d6 * 32)
    if mask == 0 and empty_as_space:
        return " "
    return chr(0x2800 + mask)


def unicode_to_pattern(char: str) -> Tuple[int, int, int, int, int, int]:
    """Converts a Unicode Braille character to 6-dot tuple."""
    code = ord(char)
    if 0x2800 <= code <= 0x283F:
        mask = code - 0x2800
        return tuple((mask >> i) & 1 for i in range(6))
    return (0, 0, 0, 0, 0, 0)


def decode_cell_pattern(
    pattern: Union[Tuple[int, ...], List[int]],
    number_mode: bool = False,
    capital_next: bool = False
) -> Tuple[str, bool, bool]:
    """
    Deterministically decodes a single 6-dot cell pattern.
    Returns: (decoded_char, new_number_mode, new_capital_next)
    """
    tup = tuple(int(b) for b in pattern[:6])
    if len(tup) < 6:
        tup = tup + (0,) * (6 - len(tup))

    # Number sign activation
    if tup == PATTERN_NUMBER_SIGN:
        return "", True, capital_next

    # Capital sign activation
    if tup == PATTERN_CAPITAL_SIGN:
        return "", number_mode, True

    # Empty cell / Space exits number mode
    if sum(tup) == 0:
        return " ", False, False

    # Numeric mode decoding
    if number_mode:
        if tup in NUMBER_MAP:
            return NUMBER_MAP[tup], True, capital_next
        elif tup in [(0, 1, 0, 0, 0, 0), (0, 1, 0, 0, 1, 1), (0, 0, 1, 0, 0, 1)]:
            # Comma, period, or hyphen in number mode stay in number mode
            punct = BRAILLE_MAP_GRADE1.get(tup, "")
            return punct, True, capital_next
        else:
            # Non-digit drops out of number mode
            number_mode = False

    # Grade 1 mapping
    char = BRAILLE_MAP_GRADE1.get(tup, None)
    if char is not None:
        if capital_next and char.isalpha():
            char = char.upper()
            capital_next = False
        return char, number_mode, capital_next

    # Ambiguous / unmapped pattern: fallback to Unicode Braille glyph
    u_char = pattern_to_unicode(tup)
    return u_char, number_mode, capital_next


def decode_line_grade1(cells: List[Any]) -> Tuple[str, str]:
    """
    Decodes an entire line of BrailleCellCandidates deterministically using Grade 1 rules.
    Preserves word spaces based on `has_space_before`.
    Returns: (raw_unicode_braille, decoded_text)
    """
    unicode_chars = []
    text_chars = []

    number_mode = False
    capital_next = False

    for cell in cells:
        pattern = getattr(cell, "dots", None)
        has_space = getattr(cell, "has_space_before", False)

        if pattern is None and isinstance(cell, (list, tuple)):
            pattern = cell
            has_space = False

        if has_space:
            if text_chars and text_chars[-1] != " ":
                text_chars.append(" ")
            if unicode_chars and unicode_chars[-1] != " ":
                unicode_chars.append(" ")
            number_mode = False
            capital_next = False

        u_char = pattern_to_unicode(pattern)
        unicode_chars.append(u_char)

        decoded_char, number_mode, capital_next = decode_cell_pattern(
            pattern,
            number_mode=number_mode,
            capital_next=capital_next
        )
        if decoded_char:
            text_chars.append(decoded_char)

    raw_unicode = "".join(unicode_chars)
    decoded_text = "".join(text_chars).strip()
    return raw_unicode, decoded_text


def decode_line_grade2_liblouis(cells: List[Any], table: str = "en-ueb-g2.ctb") -> Tuple[str, str]:
    """
    Decodes cells using the official Liblouis Grade 2 contracted translation engine
    while preserving backward compatibility.
    """
    try:
        try:
            from . import louis
        except ImportError:
            from ..braille_ocr import louis
        u_chars = []
        for cell in cells:
            pattern = getattr(cell, "dots", None)
            has_space = getattr(cell, "has_space_before", False)
            if has_space and u_chars and u_chars[-1] != " ":
                u_chars.append(" ")
            u_chars.append(pattern_to_unicode(pattern, empty_as_space=True))
        raw_unicode = "".join(u_chars)
        translated = louis.backTranslateString([table], raw_unicode)
        return raw_unicode, translated
    except Exception as e:
        # Fallback to Grade 1 deterministic decoding if Liblouis is unavailable
        raw_unicode, text = decode_line_grade1(cells)
        return raw_unicode, text
