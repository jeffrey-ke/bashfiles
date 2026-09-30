"""Tests for mdmath. Run: uv run --with pytest --with pillow --with pylatexenc pytest ~/dotfiles/bin/test_mdmath.py"""

import importlib.machinery
import importlib.util
import os
import subprocess
from pathlib import Path

import pytest

MDMATH = Path(__file__).resolve().parent / "mdmath"
_loader = importlib.machinery.SourceFileLoader("mdmath", str(MDMATH))
mdmath = importlib.util.module_from_spec(importlib.util.spec_from_loader("mdmath", _loader))
_loader.exec_module(mdmath)


def kinds(text):
    return [(type(s).__name__, getattr(s, "latex", None)) for s in mdmath.parse(text)]


def blocks(text):
    return [s.latex for s in mdmath.parse(text) if isinstance(s, mdmath.Block)]


def test_display_math_multiline_and_line_number():
    segments = mdmath.parse("intro\n\n$$\na = b\n$$\n\nafter\n")
    block = next(s for s in segments if isinstance(s, mdmath.Block))
    assert (block.latex, block.line) == ("a = b", 3)


def test_bracket_display_and_same_line_as_text():
    assert blocks(r"see $$x^2$$ and \[ y \] here") == ["x^2", "y"]


def test_code_fences_and_spans_are_not_math():
    text = "```\n$$ a $$\n```\n`$$ b $$` and ~~~ is prose\n~~~py\n\\[ c \\]\n~~~\n$$ d $$\n"
    assert blocks(text) == ["d"]


def test_unclosed_fence_swallows_the_rest():
    assert blocks("```\n$$ a $$\n") == []


def test_inline_math_follows_pandoc_rules():
    assert mdmath.inline_to_unicode("costs $5 and $10") == "costs $5 and $10"
    assert mdmath.inline_to_unicode(r"escaped \$x$ stays") == r"escaped \$x$ stays"
    assert mdmath.inline_to_unicode(r"$\alpha$ and `$\beta$`") == r"α and `$\beta$`"


def test_display_envs_are_not_double_wrapped():
    assert r"\[" not in mdmath._page(r"\begin{align*} a &= b \end{align*}")
    assert mdmath._page(r"\begin{aligned} a &= b \end{aligned}").count(r"\[") == 1


def test_grid_encodes_id_rows_and_columns():
    diacritics = mdmath._diacritics()
    grid = mdmath._grid(0x5A0102, 3, 2, diacritics)
    assert len(grid) == 2
    assert grid[1].startswith("\x1b[38;2;90;1;2m")
    cells = grid[1].removeprefix("\x1b[38;2;90;1;2m").removesuffix("\x1b[39m")
    assert cells == "".join(mdmath.PLACEHOLDER + diacritics[1] + diacritics[x] for x in range(3))


def test_transmit_wraps_every_chunk_for_tmux():
    png = os.urandom(5000)  # > one 4096-byte base64 chunk
    out = mdmath._transmit(png, 7, 4, 2, tmux=True).decode()
    chunks = out.split("\x1bPtmux;")[1:]
    assert len(chunks) == 2
    assert chunks[0].startswith("\x1b\x1b_Ga=T,U=1,f=100,i=7,c=4,r=2,q=2,m=1;")
    assert chunks[1].startswith("\x1b\x1b_Gm=0;")


@pytest.mark.skipif(not subprocess.run(["which", "tectonic"], capture_output=True).returncode == 0,
                    reason="needs tectonic")
def test_check_caches_and_reports_broken_blocks(tmp_path, monkeypatch):
    monkeypatch.setenv("MDMATH_CACHE", str(tmp_path / "cache"))
    doc = tmp_path / "doc.md"
    doc.write_text("$$ a^2 + b^2 $$\n\n$$ \\frac{1}{ $$\n")
    run = lambda: subprocess.run([str(MDMATH), "--check", str(doc)], capture_output=True, text=True)
    first = run()
    assert first.returncode == 1
    assert "doc.md:3: block 1 failed" in first.stderr
    assert len(list((tmp_path / "cache").glob("*.png"))) == 1
    doc.write_text("$$ a^2 + b^2 $$\n")
    assert run().returncode == 0
