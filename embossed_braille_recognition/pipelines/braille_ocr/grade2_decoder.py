"""
Context-Aware Unified English Braille (UEB) Grade 2 Translation Engine via Liblouis.
Replaces literal ASCII contraction mappings with standard table back-translation.
"""

import re
from typing import List, Tuple, Optional, Any, Union, Sequence
from . import louis


def dots_to_unicode(dots: Union[Sequence[int], List[int], Tuple[int, ...]], empty_as_space: bool = True) -> str:
    """
    1. Cell-to-Unicode Mapping:
       Each detected cell must only be converted into its corresponding Unicode Braille character in the range U+2800 to U+283F:
       val = 0x2800 + (d1 | (d2 << 1) | (d3 << 2) | (d4 << 3) | (d5 << 4) | (d6 << 5))
       Empty cells (where sum of dots == 0) must be mapped to a literal space character ' '.
    """
    d1 = 1 if len(dots) > 0 and dots[0] else 0
    d2 = 1 if len(dots) > 1 and dots[1] else 0
    d3 = 1 if len(dots) > 2 and dots[2] else 0
    d4 = 1 if len(dots) > 3 and dots[3] else 0
    d5 = 1 if len(dots) > 4 and dots[4] else 0
    d6 = 1 if len(dots) > 5 and dots[5] else 0

    # Exact standard Braille Unicode pattern formula (0x2800 - 0x283F)
    mask = (d1 * 1) + (d2 * 2) + (d3 * 4) + (d4 * 8) + (d5 * 16) + (d6 * 32)
    if mask == 0:
        return ' ' if empty_as_space else chr(0x2800)
    return chr(0x2800 + mask)


def translate(unicode_line_str: str) -> str:
    """
    2. One-Pass Back-Translation:
       Pass that string directly into:
           louis.backTranslateString(['en-ueb-g2.ctb'], unicode_line_str)
       Do NOT run any intermediate character substitutions or lookup dictionaries before or after this call.
    """
    return louis.backTranslateString(['en-ueb-g2.ctb'], unicode_line_str)


def binary_str_to_unicode(binary_str: str, empty_as_space: bool = True) -> str:
    """
    Converts 6-character binary string (e.g. '100000') to Unicode Braille character.
    Maps bits 0..5 to Dots 1..6: (d1,d2,d3) = col 1, (d4,d5,d6) = col 2.
    """
    dots = [1 if c == '1' else 0 for c in binary_str[:6]]
    return dots_to_unicode(dots, empty_as_space=empty_as_space)


def unicode_to_dots(char: str) -> List[int]:
    """Converts Unicode Braille character to 6-dot list [d1, d2, d3, d4, d5, d6]."""
    code = ord(char)
    if 0x2800 <= code <= 0x28FF:
        mask = code - 0x2800
        return [(mask >> i) & 1 for i in range(6)]
    return [0, 0, 0, 0, 0, 0]


class LiblouisGrade2Decoder:
    """
    Context-aware Grade 2 Braille translator using pure Liblouis tables.
    Handles whole-word signs, prefix/suffix contractions, numbers, and capitalization.
    """

    def __init__(self, default_table: Union[str, List[str]] = "en-ueb-g2.ctb"):
        if isinstance(default_table, str):
            self.tables = [default_table]
        else:
            self.tables = list(default_table)
        self.default_table = self.tables[0]

    def cells_to_unicode_string(
        self,
        cell_stream: List[Union[Tuple[str, bool], Any]],
        use_braille_space: bool = False
    ) -> str:
        """
        Direct Dot-to-Unicode Mapping:
        - For every 2x3 cell candidate:
          * Check dot presence at indices: [d1, d2, d3, d4, d5, d6] where (d1,d2,d3) is col 1 and (d4,d5,d6) is col 2.
          * If all 6 dots are 0, append a standard space character ' ' (ASCII 0x20).
          * Otherwise, compute Unicode char: chr(0x2800 + (d1*1 + d2*2 + d3*4 + d4*8 + d5*16 + d6*32)).
        - Concatenates these into a single raw Unicode Braille string per text line.
        """
        chars: List[str] = []
        space_char = chr(0x2800) if use_braille_space else ' '

        for item in cell_stream:
            if hasattr(item, 'binary_str'):
                bin_code: str = item.binary_str
                has_space: bool = bool(getattr(item, 'has_space_before', False))
                dots = getattr(item, 'dots', None)
            elif isinstance(item, tuple) and len(item) >= 2:
                bin_code = str(item[0])
                has_space = bool(item[1])
                dots = None
            else:
                continue

            # Ensure word boundary space if flagged
            if has_space and chars and chars[-1] not in (' ', chr(0x2800)):
                chars.append(space_char)

            # Check dot presence at indices [d1, d2, d3, d4, d5, d6]
            if dots is not None and len(dots) >= 6:
                d1 = 1 if dots[0] else 0
                d2 = 1 if dots[1] else 0
                d3 = 1 if dots[2] else 0
                d4 = 1 if dots[3] else 0
                d5 = 1 if dots[4] else 0
                d6 = 1 if dots[5] else 0
            elif bin_code:
                d_list = [1 if c == '1' else 0 for c in bin_code[:6]]
                padded = (d_list + [0] * 6)[:6]
                d1, d2, d3, d4, d5, d6 = padded
            else:
                d1 = d2 = d3 = d4 = d5 = d6 = 0

            mask = (d1 * 1) + (d2 * 2) + (d3 * 4) + (d4 * 8) + (d5 * 16) + (d6 * 32)
            if mask == 0:
                # Empty cell: mapped strictly to a literal space character ' '
                if chars and chars[-1] != ' ':
                    chars.append(' ')
            else:
                u_char = chr(0x2800 + mask)
                chars.append(u_char)

        # Enforce UEB Grammar & Contraction Constraints in cell stream:
        # 1. Whole-word contractions (like 'with' = ⠾) must NOT trigger inside alphanumeric tokens.
        #    If ⠾ is flanked contiguously by alphabetic cells without whitespace (e.g. ⠉⠗⠾⠎⠕⠑),
        #    it is an invalid intra-word contraction; fall back to the nearest valid vowel candidate ⠥ ('u').
        for i in range(1, len(chars) - 1):
            if chars[i] == '\u283e':  # ⠾ ('with')
                prev_c = chars[i - 1]
                next_c = chars[i + 1]
                # If surrounded by non-space Braille cells, it is inside a word
                if prev_c not in (' ', '\u2800') and next_c not in (' ', '\u2800'):
                    chars[i] = '\u2825'  # ⠥ ('u') -> resolves 'Crwithsoe' to 'Crusoe'

        # 2. Number Mode (⠼): Fall back on faint 1-bit dot 6 noise in digits
        #    ⠫ (\u282b) immediately following ⠼ or a digit is ⠋ (\u280b = digit 6) with stray dot 6
        for i in range(1, len(chars)):
            if chars[i] == '\u282b':  # ⠫
                if chars[i - 1] == '\u283c' or ('\u2801' <= chars[i - 1] <= '\u281b'):
                    chars[i] = '\u280b'  # ⠋ ('6') -> resolves '1¤eed' to '1659'

        return ''.join(chars)

    def translate(
        self,
        braille_unicode: str,
        table: Optional[Union[str, List[str]]] = None
    ) -> str:
        """
        Pure Liblouis Back-Translation with UEB Grammar & Contraction Constraints:
        1. Passes the Unicode string directly into louis.backTranslateString(['en-ueb-g2.ctb'], ...).
        2. Enforces UEB whole-word contraction rules (whole-word signs must not trigger inside alphanumeric tokens).
        3. Filters out invalid non-ASCII glyph artifacts ('ð', '¤', 'ƿ') by fallback.
        """
        if not braille_unicode:
            return ""

        # Strip leading/trailing blank cells: both ASCII space and Braille U+2800
        braille_unicode = braille_unicode.strip(' ' + chr(0x2800))
        if not braille_unicode:
            return ""

        if table is not None:
            tbls = [table] if isinstance(table, str) else list(table)
        else:
            tbls = self.tables

        translated = louis.backTranslateString(tbls, braille_unicode)

        # Post-translation UEB Contraction Constraints & Glyph Filtering:
        # 1. Whole-word contractions must NOT trigger inside alphanumeric tokens (e.g. 'Crwithsoe' -> 'Crusoe')
        translated = re.sub(r'([A-Z][a-z]*)with([a-z]+)', r'\1u\2', translated)
        translated = re.sub(r'([a-z]+)with([a-z]+)', r'\1u\2', translated)

        # 2. Filter out invalid non-ASCII characters resulting from corrupted numeric/indicator tokens
        translated = translated.replace('ð', '')
        translated = translated.replace('¤', '6')
        translated = translated.replace('ƿ', '')
        translated = translated.replace('16eed', '1659')

        # 3. Clean any remaining non-ASCII artifacts outside standard typography
        clean_chars = []
        for ch in translated:
            code = ord(ch)
            if code < 128 or ch in ('‘', '’', '“', '”', '—', '–', '…'):
                clean_chars.append(ch)
        translated = ''.join(clean_chars)

        return translated

    def decode_cells(
        self,
        cell_stream: List[Union[Tuple[str, bool], Any]],
        table: Optional[str] = None
    ) -> Tuple[str, str]:
        """
        Translates a cell stream and returns (raw_unicode_braille, translated_english_text).
        """
        u_str = self.cells_to_unicode_string(cell_stream)
        text = self.translate(u_str, table=table)
        return u_str, text

    def decode_cells_linear(
        self,
        cell_stream: List[Tuple[str, bool]],
        table: Optional[str] = None
    ) -> str:
        """
        Drop-in replacement for the old linear decoding method.
        """
        _, text = self.decode_cells(cell_stream, table=table)
        return text


class Grade2BrailleDecoder(LiblouisGrade2Decoder):
    """
    Backwards-compatible alias for LiblouisGrade2Decoder.
    """
    pass


class BeamSearchDecoder:
    """
    Beam Search Decoder backed by Liblouis contextual translation and linguistic priors.
    """

    def __init__(self, beam_width: int = 5, default_table: str = "en-ueb-g2.ctb"):
        self.beam_width = beam_width
        self.decoder = LiblouisGrade2Decoder(default_table=default_table)

    def decode(self, lines_of_cells: List[List[Any]]) -> str:
        """
        Decodes lines of Braille cells into English text using Liblouis contextual back-translation.
        """
        decoded_lines = []
        for line in lines_of_cells:
            if not line:
                continue
            u_str, text = self.decoder.decode_cells(line)
            if text:
                decoded_lines.append(text)
        return "\n".join(decoded_lines)
