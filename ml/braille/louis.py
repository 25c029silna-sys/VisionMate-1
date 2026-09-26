"""
Official Python interface for Liblouis Braille Translator.
Provides ctypes wrapper around liblouis.dll and fallback to lou_translate.exe CLI.
"""

import os
import sys
import ctypes
import subprocess
from typing import List, Union, Optional

_BASE_DIR = os.path.dirname(os.path.abspath(__file__))
_LIBLOUIS_DIR = os.path.join(_BASE_DIR, "liblouis")
_BIN_DIR = os.path.join(_LIBLOUIS_DIR, "bin")
_TABLES_DIR = os.path.join(_LIBLOUIS_DIR, "share", "liblouis", "tables")
_DLL_PATH = os.path.join(_BIN_DIR, "liblouis.dll")
_CLI_PATH = os.path.join(_BIN_DIR, "lou_translate.exe")

# Ensure Windows C runtime sees the table path
os.environ["LOUIS_TABLEPATH"] = _TABLES_DIR
if sys.platform == "win32":
    try:
        ctypes.cdll.msvcrt._wputenv(f"LOUIS_TABLEPATH={_TABLES_DIR}")
    except Exception:
        pass

# Initialize ctypes library
_lib = None
_char_size = 4

if os.path.exists(_DLL_PATH):
    try:
        _lib = ctypes.cdll.LoadLibrary(_DLL_PATH)
        _lib.lou_version.restype = ctypes.c_char_p
        _lib.lou_charSize.restype = ctypes.c_int
        _char_size = _lib.lou_charSize()
    except Exception as e:
        _lib = None


def version() -> str:
    """Returns the Liblouis library version string."""
    if _lib is not None:
        try:
            return _lib.lou_version().decode("utf-8")
        except Exception:
            pass
    if os.path.exists(_CLI_PATH):
        try:
            res = subprocess.run([_CLI_PATH, "--version"], capture_output=True, text=True)
            first_line = res.stdout.splitlines()[0] if res.stdout else "3.39.0"
            return first_line
        except Exception:
            pass
    return "3.39.0"


def _resolve_table_list(tables: Union[str, List[str]]) -> bytes:
    """Formats table list string or list of tables into comma-separated bytes with full paths."""
    if isinstance(tables, str):
        table_names = [t.strip() for t in tables.split(",") if t.strip()]
    else:
        table_names = list(tables)

    resolved = []
    for t in table_names:
        if os.path.isabs(t):
            resolved.append(t)
        else:
            # Check in TABLES_DIR
            cand = os.path.join(_TABLES_DIR, t)
            if os.path.exists(cand):
                resolved.append(cand)
            else:
                resolved.append(t)

    return ",".join(resolved).encode("utf-8")


def backTranslateString(
    tableList: Union[str, List[str]],
    inbuf: str,
    typeform: Optional[List[int]] = None,
    mode: int = 0
) -> str:
    """
    Back-translates a string of Braille characters to print text.
    
    :param tableList: Name or list of translation tables (e.g. ['unicode.dis', 'en-ueb-g2.ctb'])
    :param inbuf: Braille text to back-translate (Unicode Braille or ASCII Braille depending on table)
    :param typeform: Optional typeform formatting list
    :param mode: Translation mode flags
    :return: Translated text
    """
    if not inbuf:
        return ""

    table_spec = _resolve_table_list(tableList)

    # 1. Try ctypes in-process translation
    if _lib is not None:
        try:
            in_chars = [ord(c) for c in inbuf]
            in_len = ctypes.c_int(len(in_chars))
            in_buf = (ctypes.c_uint32 * len(in_chars))(*in_chars)

            out_max = max(len(in_chars) * 6, 256)
            out_len = ctypes.c_int(out_max)
            out_buf = (ctypes.c_uint32 * out_max)()

            res = _lib.lou_backTranslateString(
                table_spec,
                in_buf,
                ctypes.byref(in_len),
                out_buf,
                ctypes.byref(out_len),
                None,
                None,
                mode
            )
            if res != 0:
                return "".join(chr(out_buf[i]) for i in range(out_len.value))
        except Exception:
            pass

    # 2. Fallback to lou_translate.exe CLI
    if os.path.exists(_CLI_PATH):
        try:
            env = os.environ.copy()
            env["LOUIS_TABLEPATH"] = _TABLES_DIR
            table_arg = table_spec.decode("utf-8")
            p = subprocess.run(
                [_CLI_PATH, "-b", table_arg],
                input=inbuf.encode("utf-8"),
                capture_output=True,
                env=env,
                check=False
            )
            return p.stdout.decode("utf-8", errors="replace").strip()
        except Exception as e:
            raise RuntimeError(f"Liblouis translation failed: {e}")

    raise RuntimeError("Liblouis binaries not found. Ensure ml/braille_ocr/liblouis/ exists.")


def translateString(
    tableList: Union[str, List[str]],
    inbuf: str,
    typeform: Optional[List[int]] = None,
    mode: int = 0
) -> str:
    """
    Forward-translates print text to Braille.
    """
    if not inbuf:
        return ""

    table_spec = _resolve_table_list(tableList)

    if _lib is not None:
        try:
            in_chars = [ord(c) for c in inbuf]
            in_len = ctypes.c_int(len(in_chars))
            in_buf = (ctypes.c_uint32 * len(in_chars))(*in_chars)

            out_max = max(len(in_chars) * 6, 256)
            out_len = ctypes.c_int(out_max)
            out_buf = (ctypes.c_uint32 * out_max)()

            res = _lib.lou_translateString(
                table_spec,
                in_buf,
                ctypes.byref(in_len),
                out_buf,
                ctypes.byref(out_len),
                None,
                None,
                mode
            )
            if res != 0:
                return "".join(chr(out_buf[i]) for i in range(out_len.value))
        except Exception:
            pass

    if os.path.exists(_CLI_PATH):
        try:
            env = os.environ.copy()
            env["LOUIS_TABLEPATH"] = _TABLES_DIR
            table_arg = table_spec.decode("utf-8")
            p = subprocess.run(
                [_CLI_PATH, "-f", table_arg],
                input=inbuf.encode("utf-8"),
                capture_output=True,
                env=env,
                check=False
            )
            return p.stdout.decode("utf-8", errors="replace").strip()
        except Exception as e:
            raise RuntimeError(f"Liblouis forward translation failed: {e}")

    raise RuntimeError("Liblouis binaries not found.")


# Register into sys.modules as 'louis' for direct `import louis` support
sys.modules["louis"] = sys.modules[__name__]
