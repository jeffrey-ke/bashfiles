# fnidx Faceted Function Index — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `fnidx`, a read-only tool that reads Python file paths on stdin and emits one TSV row per function definition — parsing each name into `object`/`verb`/`target` facets — with conformance reports on stderr.

**Architecture:** A single importable module, `bin/fnidx.py`, containing four pure stages: scrape (stdlib `ast` → `Definition` records), parse (token count → `Facets`), emit (fill a 1-token method's object from its class, then a 9-column TSV to stdout), report (corpus-wide checks to stderr). It contains no heuristics: every column is copied from the AST or split from the name, never transformed. A thin `bin/fnidx` bash launcher runs it under `uv`, matching the existing `bin/pydef` + `bin/pydef.lua` pairing. No third-party dependencies.

**Tech Stack:** Python 3.11+ stdlib only (`ast`, `pathlib`, `fnmatch`, `dataclasses`, `collections`), `uv` for execution, `pytest` for golden-file tests.

**Spec:** `~/dotfiles/docs/superpowers/specs/2026-08-20-function-name-index-design.md`

## Global Constraints

Every task's requirements implicitly include these. Values are copied verbatim from the spec.

- **Read-only.** The tool never writes to source files. No editing, renaming, or call-site rewriting.
- **TSV is 9 columns, fixed positions, no header row:** `file ln col name module class object verb target`. Empty string for absent facets. A header row would appear as a value in every `cut | sort -u` pivot.
- **The indexer never normalizes.** No singularizing, no case folding, no suffix stripping. Deciding that `Tracks`, `TrackStore`, and `Track` name the same object is the author's policy, not the tool's. **An equivalence may inform a report; it may never produce a column value.**
- **A 1-token method takes its class as the object, verbatim** — `TrackStore.get` → `object=TrackStore`, never `track`. Sourcing a facet from the AST is structural; transforming its text is policy.
- **A 1-token free function leaves `object` empty.** A module stem is a topic label, not an entity — imputing from it would inject `utils`/`config` into the object vocabulary. The row is still indexed and the report names it.
- **All facet comparison is case-insensitive**, including the stutter check — or `Track.get_track` slips through on a `Track` vs `track` mismatch.
- **Index goes to stdout, reports go to stderr, on every run. There is no `--report` flag.**
- **Unparseable names are indexed, not rejected.** They get a row with `module` filled and the remaining facets empty.
- **Exempt names are still indexed.** Exemption suppresses the report line only.
- **Exit nonzero only if no file parsed at all.** A file that fails to parse warns on stderr and is skipped.
- **Paths arrive on stdin. No include/exclude flags.**
- **Stdlib only.** No third-party runtime dependencies.

### Grammar reference (spec §3)

| Tokens | Parse | Example |
|---|---|---|
| 1 | `verb`; object is the class verbatim, or empty | `TrackStore.get` |
| 2 | `verb_object` | `get_track` |
| 3 | `object_verb_object` | `mask_to_proto` |
| 4+ or 0 | unparseable | `doTheThing` |

Tokenizing is a plain `split('_')`. camelCase lives *inside* a token and the parser never looks at it.

## File Structure

| File | Responsibility |
|---|---|
| `bin/fnidx.py` (create) | All logic. Importable module with a `main()`; PEP-723 header so `uv run` works standalone. |
| `bin/fnidx` (create) | Bash launcher. `exec uv run "$DIR/fnidx.py" "$@"`, using the `readlink -f` idiom from `bin/pydef`. |
| `bin/tests/test_fnidx.py` (create) | Pytest suite. Unit tests per stage plus the two golden-file assertions from spec §10. |
| `bin/tests/fixtures/` (create) | Fixture package: every name shape from §3 and every violation class from §7. |

One module, not a package: the whole tool is ~250 lines of pure functions over two dataclasses, and splitting it across files would add imports without adding a seam. `bin/registry.py` sets the precedent for an importable `.py` library living in `bin/` alongside extensionless launchers.

## Data model

Defined in Task 1, used by every later task. Reproduced here because tasks may be read out of order.

```python
@dataclass(frozen=True)
class Definition:
    path: str        # exactly as it arrived on stdin, not resolved
    line: int        # 1-indexed
    col: int         # 1-indexed (ast gives 0-indexed col_offset; +1 on construction)
    name: str        # bare function name, no class prefix
    module: str      # file stem, e.g. "tracking" for perception/tracking.py
    class_name: str  # nearest enclosing class, '' for free functions


@dataclass(frozen=True)
class Facets:
    object: str      # '' when unparseable, or a 1-token free function
    verb: str        # '' when unparseable
    target: str      # '' unless the name had 3 tokens
    parsed: bool     # False => token count was 0 or 4+
```

---

### Task 1: Scrape definitions with `ast`

**Files:**
- Create: `~/dotfiles/bin/fnidx.py`
- Create: `~/dotfiles/bin/tests/test_fnidx.py`
- Create: `~/dotfiles/bin/tests/fixtures/shapes.py`

**Interfaces:**
- Consumes: nothing.
- Produces: `Definition` (fields above); `scrape_python(path: str, source: str) -> list[Definition]`. Takes source as a string rather than reading the file, so tests need no I/O and Task 7 owns all file reading.

- [ ] **Step 1: Write the fixture module**

Create `~/dotfiles/bin/tests/fixtures/shapes.py`. This same file is reused by Tasks 2-5, so it carries every shape at once:

```python
"""Fixture covering every name shape in spec section 3 and every violation in section 7."""


def get_track(track_id):
    """2 tokens: verb_object."""
    return track_id


def pointCloud_to_pb(cloud):
    """3 tokens: object_verb_object, with a camelCase object."""
    return cloud


def get():
    """1 token free function: no class, so object stays empty and gets reported."""
    return None


def doTheThing():
    """Unparseable: 1 token by split('_') but not a real parse target."""
    return None


def get_bounding_box_fast(x):
    """Unparseable: 4 tokens."""
    return x


def track_get(track_id):
    """Inverted slots: parses as verb=track, object=get. Feeds the collision report."""
    return track_id


async def build_mask(raw):
    """async def must be scraped like def."""
    return raw


class Track:
    def get_pose(self):
        """Method, 2 tokens. class_name=Track."""
        return None

    def get_track(self):
        """Stutter: repeats the class name."""
        return None

    class Nested:
        def get_id(self):
            """Nested class: class_name is the nearest enclosing class, Nested."""
            return None


class TrackStore:
    def get(self):
        """1 token: the class becomes the object, verbatim -> object=TrackStore."""
        return None


def make_closure():
    def get_inner():
        """A nested function is still indexed; see Step 3's note."""
        return None

    return get_inner
```

- [ ] **Step 2: Write the failing test**

Create `~/dotfiles/bin/tests/test_fnidx.py`:

```python
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))  # -> dotfiles/bin

import fnidx

FIXTURES = Path(__file__).resolve().parent / 'fixtures'


def scrape_fixture(stem: str) -> list[fnidx.Definition]:
    path = FIXTURES / f'{stem}.py'
    return fnidx.scrape_python(str(path), path.read_text())


def test_scrape_finds_free_function():
    # Keyed by (class_name, name): `get_track` exists twice in the fixture, as a
    # free function and as Track's stutter case. A name-only key would silently
    # keep whichever came last.
    defs = {(d.class_name, d.name): d for d in scrape_fixture('shapes')}
    d = defs[('', 'get_track')]
    assert d.module == 'shapes'
    assert d.col == 1


def test_scrape_records_enclosing_class():
    defs = {(d.class_name, d.name): d for d in scrape_fixture('shapes')}
    assert ('Track', 'get_pose') in defs
    assert ('TrackStore', 'get') in defs


def test_scrape_uses_nearest_enclosing_class():
    defs = {(d.class_name, d.name): d for d in scrape_fixture('shapes')}
    assert ('Nested', 'get_id') in defs


def test_scrape_includes_async_and_nested_functions():
    names = {d.name for d in scrape_fixture('shapes')}
    assert 'build_mask' in names
    assert 'get_inner' in names


def test_scrape_line_and_col_are_one_indexed():
    defs = {d.name: d for d in scrape_fixture('shapes')}
    assert defs['get_pose'].col == 5  # 4 spaces of indent -> col_offset 4 -> col 5
    assert defs['get_track'].line > 0
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd ~/dotfiles && uv run --with pytest pytest bin/tests/test_fnidx.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'fnidx'`

- [ ] **Step 4: Write the scraper**

Create `~/dotfiles/bin/fnidx.py`:

```python
#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""fnidx — a faceted index of function names.

Reads file paths on stdin, writes a 9-column TSV of function definitions to
stdout and conformance reports to stderr. Read-only: never touches source.

Spec: ~/dotfiles/docs/superpowers/specs/2026-08-20-function-name-index-design.md
"""
import ast
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Definition:
    path: str
    line: int
    col: int
    name: str
    module: str
    class_name: str


def scrape_python(path: str, source: str) -> list[Definition]:
    """Every function definition in `source`, including methods, nested classes,
    async defs, and closures. `path` is recorded verbatim, not resolved."""
    module = Path(path).stem
    out: list[Definition] = []

    def walk(node: ast.AST, class_name: str) -> None:
        for child in ast.iter_child_nodes(node):
            if isinstance(child, (ast.FunctionDef, ast.AsyncFunctionDef)):
                out.append(
                    Definition(
                        path=path,
                        line=child.lineno,
                        col=child.col_offset + 1,
                        name=child.name,
                        module=module,
                        class_name=class_name,
                    )
                )
                walk(child, class_name)
            elif isinstance(child, ast.ClassDef):
                walk(child, child.name)
            else:
                walk(child, class_name)

    walk(ast.parse(source), '')
    return out
```

Two decisions the spec leaves open, resolved here:

- **Nested functions are indexed.** Spec §6's rule is that a function which exists must always be findable; a closure is no exception. Its `class_name` is the nearest enclosing class, which is why `walk` recurses into function bodies carrying `class_name` through.
- **`path` is recorded verbatim.** Resolving it would make golden files depend on the checkout location.

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd ~/dotfiles && uv run --with pytest pytest bin/tests/test_fnidx.py -v`
Expected: PASS — the new tests plus every test written in earlier tasks

- [ ] **Step 6: Commit**

```bash
cd ~/dotfiles
git add bin/fnidx.py bin/tests/test_fnidx.py bin/tests/fixtures/shapes.py
git commit -m "feat(fnidx): scrape Python function definitions with ast"
```

---

### Task 2: Parse names into facets by token count

**Files:**
- Modify: `~/dotfiles/bin/fnidx.py`
- Modify: `~/dotfiles/bin/tests/test_fnidx.py`

**Interfaces:**
- Consumes: nothing from Task 1 (pure string function).
- Produces: `Facets` (fields in the Data model section); `parse_name(name: str) -> Facets`.

- [ ] **Step 1: Write the failing test**

Append to `~/dotfiles/bin/tests/test_fnidx.py`:

```python
def test_parse_two_tokens_is_verb_object():
    f = fnidx.parse_name('get_track')
    assert (f.verb, f.object, f.target, f.parsed) == ('get', 'track', '', True)


def test_parse_three_tokens_is_object_verb_object():
    f = fnidx.parse_name('pointCloud_to_pb')
    assert (f.object, f.verb, f.target, f.parsed) == ('pointCloud', 'to', 'pb', True)


def test_parse_one_token_leaves_object_empty():
    f = fnidx.parse_name('get')
    assert (f.verb, f.object, f.target, f.parsed) == ('get', '', '', True)


def test_parse_four_tokens_is_unparseable():
    f = fnidx.parse_name('get_bounding_box_fast')
    assert f.parsed is False
    assert (f.verb, f.object, f.target) == ('', '', '')


def test_parse_preserves_camel_case_inside_a_token():
    assert fnidx.parse_name('get_boundingBox').object == 'boundingBox'


def test_parse_does_not_branch_on_definition_kind():
    """Same name, same parse, whether it is a method or a free function."""
    assert fnidx.parse_name('mask_to_proto') == fnidx.parse_name('mask_to_proto')
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd ~/dotfiles && uv run --with pytest pytest bin/tests/test_fnidx.py -k parse -v`
Expected: FAIL — `AttributeError: module 'fnidx' has no attribute 'parse_name'`

- [ ] **Step 3: Write the parser**

Add to `~/dotfiles/bin/fnidx.py`, after `Definition`:

```python
@dataclass(frozen=True)
class Facets:
    object: str
    verb: str
    target: str
    parsed: bool


UNPARSEABLE = Facets(object='', verb='', target='', parsed=False)


def parse_name(name: str) -> Facets:
    """Facets of `name`, by token count alone. Needs no vocabulary and does not
    branch on definition kind. A 1-token name leaves `object` empty and it stays
    empty: the indexer never invents a facet value."""
    tokens = name.split('_')
    if len(tokens) == 1 and tokens[0]:
        return Facets(object='', verb=tokens[0], target='', parsed=True)
    if len(tokens) == 2:
        return Facets(object=tokens[1], verb=tokens[0], target='', parsed=True)
    if len(tokens) == 3:
        return Facets(object=tokens[0], verb=tokens[1], target=tokens[2], parsed=True)
    return UNPARSEABLE
```

Note that a name with a leading or trailing underscore (`_get_track`, `get_track_`) yields an empty token and therefore a 3-token parse with an empty slot. That is correct behavior for this grammar: `_get_track` is not a conforming name, and the empty facet plus the report line in Task 6 is how the author finds out.

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd ~/dotfiles && uv run --with pytest pytest bin/tests/test_fnidx.py -v`
Expected: PASS — the new tests plus every test written in earlier tasks

- [ ] **Step 5: Commit**

```bash
cd ~/dotfiles
git add bin/fnidx.py bin/tests/test_fnidx.py
git commit -m "feat(fnidx): parse names into facets by token count"
```

---

### Task 3: Emit the 9-column TSV

**Files:**
- Modify: `~/dotfiles/bin/fnidx.py`
- Modify: `~/dotfiles/bin/tests/test_fnidx.py`
- Create: `~/dotfiles/bin/tests/golden/shapes.tsv`

**Interfaces:**
- Consumes: `Definition` (Task 1), `Facets` (Task 2).
- Produces: `class_as_object(definition: Definition, facets: Facets) -> Facets` — fills an empty `object` with `definition.class_name` verbatim, unchanged otherwise; `tsv_row(definition: Definition, facets: Facets) -> str` (one line, no trailing newline); `COLUMNS: tuple[str, ...]` naming the 9 columns in order.

- [ ] **Step 1: Write the failing test**

Append to `~/dotfiles/bin/tests/test_fnidx.py`:

```python
def row_for(name: str, module: str = 'tracking', class_name: str = '') -> list[str]:
    d = fnidx.Definition(
        path='perception/tracking.py',
        line=88,
        col=1,
        name=name,
        module=module,
        class_name=class_name,
    )
    f = fnidx.class_as_object(d, fnidx.parse_name(name))
    return fnidx.tsv_row(d, f).split('\t')


def test_row_has_nine_fields_always():
    assert len(fnidx.COLUMNS) == 9
    assert len(row_for('get_track')) == 9
    assert len(row_for('doTheThing')) == 9
    assert len(row_for('get_bounding_box_fast')) == 9


def test_row_field_order():
    fields = row_for('get_track')
    assert fields[:4] == ['perception/tracking.py', '88', '1', 'get_track']
    assert fields[4] == 'tracking'   # module
    assert fields[5] == ''           # class
    assert fields[6] == 'track'      # object
    assert fields[7] == 'get'        # verb
    assert fields[8] == ''           # target


def test_row_fills_target_for_three_token_names():
    assert row_for('pointCloud_to_pb')[6:] == ['pointCloud', 'to', 'pb']


def test_row_for_unparseable_keeps_module_and_empties_facets():
    fields = row_for('doTheThing')
    assert fields[4] == 'tracking'
    assert fields[6:] == ['', '', '']


def test_row_takes_the_class_as_object_verbatim():
    fields = row_for('get', class_name='TrackStore')
    assert fields[5] == 'TrackStore'   # class
    assert fields[6] == 'TrackStore'   # object: verbatim, NOT 'track'


def test_row_leaves_object_empty_for_a_one_token_free_function():
    assert row_for('get')[6] == ''


def test_row_does_not_overwrite_a_spelled_object():
    assert row_for('get_pose', class_name='TrackStore')[6] == 'pose'
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd ~/dotfiles && uv run --with pytest pytest bin/tests/test_fnidx.py -k row -v`
Expected: FAIL — `AttributeError: module 'fnidx' has no attribute 'COLUMNS'`

- [ ] **Step 3: Write the emitter**

Add to `~/dotfiles/bin/fnidx.py`:

```python
import dataclasses

COLUMNS = ('file', 'ln', 'col', 'name', 'module', 'class', 'object', 'verb', 'target')


def class_as_object(definition: Definition, facets: Facets) -> Facets:
    """A 1-token method's object is its class, copied verbatim. Sourcing a facet
    from the AST is structural; normalizing its text would be policy, so
    `TrackStore` stays `TrackStore` and never becomes `track`. A free function has
    no class, so its object stays empty and the report names it."""
    if not facets.parsed or facets.object or not definition.class_name:
        return facets
    return dataclasses.replace(facets, object=definition.class_name)


def tsv_row(definition: Definition, facets: Facets) -> str:
    """One TSV line, 9 fields, no trailing newline. Fixed positions: an absent
    facet is an empty field, never a dropped one, so `cut -f7` never shifts."""
    return '\t'.join(
        (
            definition.path,
            str(definition.line),
            str(definition.col),
            definition.name,
            definition.module,
            definition.class_name,
            facets.object,
            facets.verb,
            facets.target,
        )
    )
```

No header row is emitted: it would appear as a value in every `cut | sort -u` pivot.

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd ~/dotfiles && uv run --with pytest pytest bin/tests/test_fnidx.py -v`
Expected: PASS — the new tests plus every test written in earlier tasks

- [ ] **Step 5: Add the golden TSV test**

Append to `~/dotfiles/bin/tests/test_fnidx.py`:

```python
GOLDEN = Path(__file__).resolve().parent / 'golden'


def index_fixture(stem: str) -> str:
    lines = []
    for d in scrape_fixture(stem):
        f = fnidx.class_as_object(d, fnidx.parse_name(d.name))
        lines.append(fnidx.tsv_row(d, f))
    return '\n'.join(lines) + '\n'


def test_golden_tsv():
    actual = index_fixture('shapes').replace(str(FIXTURES) + '/', '')
    expected = (GOLDEN / 'shapes.tsv').read_text()
    assert actual == expected
```

- [ ] **Step 6: Generate the golden file, then read it before trusting it**

```bash
cd ~/dotfiles/bin/tests && mkdir -p golden
uv run --with pytest python -c "
import sys; sys.path.insert(0, '..')
import test_fnidx as t
open('golden/shapes.tsv','w').write(t.index_fixture('shapes').replace(str(t.FIXTURES)+'/',''))
"
cat golden/shapes.tsv
```

Read every row against the grammar table in Global Constraints before committing. A golden file generated from a buggy implementation locks the bug in. Specifically confirm: `TrackStore.get` has `object=TrackStore` **verbatim**, not `track`; the free `get` has an **empty** object; `doTheThing` and `get_bounding_box_fast` have three trailing empty fields; and `get_inner` appears at all.

- [ ] **Step 7: Run the full suite**

Run: `cd ~/dotfiles && uv run --with pytest pytest bin/tests/test_fnidx.py -v`
Expected: PASS — the new tests plus every test written in earlier tasks

- [ ] **Step 8: Commit**

```bash
cd ~/dotfiles
git add bin/fnidx.py bin/tests/test_fnidx.py bin/tests/golden/shapes.tsv
git commit -m "feat(fnidx): emit the nine-column TSV"
```

---

### Task 4: Exemptions — patterns and `.fnidxignore`

**Files:**
- Modify: `~/dotfiles/bin/fnidx.py`
- Modify: `~/dotfiles/bin/tests/test_fnidx.py`
- Create: `~/dotfiles/bin/tests/fixtures/peers/.fnidxignore`
- Create: `~/dotfiles/bin/tests/fixtures/peers/vendor_code.py`

**Interfaces:**
- Consumes: `Definition` (Task 1).
- Produces: `is_exempt(definition: Definition, ignore_globs: frozenset[str]) -> bool`; `load_ignore_globs(path: str) -> frozenset[str]` which walks up from `path`'s directory to the filesystem root, union-ing every `.fnidxignore` it finds.

Exemption suppresses a report line only. Exempt definitions are still indexed, so they stay findable.

- [ ] **Step 1: Write the ignore fixtures**

```bash
mkdir -p ~/dotfiles/bin/tests/fixtures/peers
cat > ~/dotfiles/bin/tests/fixtures/peers/.fnidxignore <<'EOF'
# Peers' code never conforms; silence the whole subtree.
*
EOF
cat > ~/dotfiles/bin/tests/fixtures/peers/vendor_code.py <<'EOF'
def DoSomethingEntirelyDifferent(a, b):
    return a + b
EOF
```

- [ ] **Step 2: Write the failing test**

Append to `~/dotfiles/bin/tests/test_fnidx.py`:

```python
def a_definition(name: str, path: str = 'x.py') -> fnidx.Definition:
    return fnidx.Definition(
        path=path, line=1, col=1, name=name, module='x', class_name=''
    )


def test_dunders_and_tests_and_callbacks_are_exempt_by_pattern():
    for name in ('__init__', '__repr__', 'test_thing', 'forward', 'on_epoch_end'):
        assert fnidx.is_exempt(a_definition(name), frozenset())


def test_ordinary_names_are_not_exempt():
    assert not fnidx.is_exempt(a_definition('doTheThing'), frozenset())


def test_ignore_globs_match_case_insensitively():
    globs = frozenset({'legacy_*'})
    assert fnidx.is_exempt(a_definition('LEGACY_thing'), globs)


def test_star_glob_exempts_everything():
    assert fnidx.is_exempt(a_definition('anything'), frozenset({'*'}))


def test_load_ignore_globs_walks_up_the_tree():
    path = str(FIXTURES / 'peers' / 'vendor_code.py')
    assert '*' in fnidx.load_ignore_globs(path)


def test_load_ignore_globs_is_empty_where_no_file_applies():
    assert fnidx.load_ignore_globs(str(FIXTURES / 'shapes.py')) == frozenset()


def test_exempt_definitions_are_still_indexed():
    """Exemption is a report concern, never an index concern."""
    defs = scrape_fixture('peers/vendor_code')
    assert [d.name for d in defs] == ['DoSomethingEntirelyDifferent']
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd ~/dotfiles && uv run --with pytest pytest bin/tests/test_fnidx.py -k "exempt or ignore" -v`
Expected: FAIL — `AttributeError: module 'fnidx' has no attribute 'is_exempt'`

- [ ] **Step 4: Write the exemption logic**

Add to `~/dotfiles/bin/fnidx.py`:

```python
import fnmatch

_FRAMEWORK_GLOBS = frozenset(
    {'__*__', 'test_*', 'forward', 'on_epoch_end', 'on_train_*', 'on_validation_*'}
)
IGNORE_FILENAME = '.fnidxignore'


def load_ignore_globs(path: str) -> frozenset[str]:
    """Union of every `.fnidxignore` from `path`'s directory up to the filesystem
    root. Lines are name globs; `#` comments and blank lines are skipped."""
    globs: set[str] = set()
    directory = Path(path).resolve().parent
    for candidate in (directory, *directory.parents):
        ignore_file = candidate / IGNORE_FILENAME
        if not ignore_file.is_file():
            continue
        for line in ignore_file.read_text().splitlines():
            stripped = line.strip()
            if stripped and not stripped.startswith('#'):
                globs.add(stripped)
    return frozenset(globs)


def is_exempt(definition: Definition, ignore_globs: frozenset[str]) -> bool:
    """Whether `definition` is excused from the reports. Exempt names are still
    indexed. Matching is case-insensitive, like every facet comparison."""
    name = definition.name.lower()
    return any(
        fnmatch.fnmatchcase(name, glob.lower())
        for glob in (*_FRAMEWORK_GLOBS, *ignore_globs)
    )
```

`fnmatchcase` against pre-lowered operands rather than `fnmatch.fnmatch`, because `fnmatch` normalizes paths on some platforms and these are bare identifiers.

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd ~/dotfiles && uv run --with pytest pytest bin/tests/test_fnidx.py -v`
Expected: PASS — the new tests plus every test written in earlier tasks

- [ ] **Step 6: Commit**

```bash
cd ~/dotfiles
git add bin/fnidx.py bin/tests/test_fnidx.py bin/tests/fixtures/peers/
git commit -m "feat(fnidx): exempt framework names and .fnidxignore globs from reports"
```

---

### Task 5: Corpus reports on stderr

**Files:**
- Modify: `~/dotfiles/bin/fnidx.py`
- Modify: `~/dotfiles/bin/tests/test_fnidx.py`
- Create: `~/dotfiles/bin/tests/golden/shapes.report.txt`

**Interfaces:**
- Consumes: `Definition`, `Facets`, `is_exempt`.
- Produces: `build_report(rows: list[tuple[Definition, Facets]], exempt: set[tuple[str, int]]) -> str` where `exempt` holds `(path, line)` for every definition excused by Task 5. Returns the full report text, ending in a newline, or `''` when every section is empty.

`exempt` is keyed by position, not by name: a bare name would exempt that spelling in every file, so one `.fnidxignore` in a peer's tree would silence a same-named function of your own elsewhere.

Five sections, in this order: unparseable, unspelled object, cross-slot collisions, stutter, verb tail.

- [ ] **Step 1: Write the failing test**

Append to `~/dotfiles/bin/tests/test_fnidx.py`:

```python
def rows_for_fixture(stem: str) -> list[tuple[fnidx.Definition, fnidx.Facets]]:
    out = []
    for d in scrape_fixture(stem):
        out.append((d, fnidx.class_as_object(d, fnidx.parse_name(d.name))))
    return out


def test_report_lists_one_token_free_functions_as_unspelled():
    """The free `get` has no class to take an object from; TrackStore.get does."""
    report = fnidx.build_report(rows_for_fixture('shapes'), set())
    assert 'unspelled object' in report
    unspelled_section = report.split('unspelled object')[1].split('\n\n')[0]
    assert 'TrackStore' not in unspelled_section


def test_report_lists_unparseable_names():
    report = fnidx.build_report(rows_for_fixture('shapes'), set())
    assert 'get_bounding_box_fast' in report


def test_report_flags_cross_slot_collision_with_counts():
    """`track` appears as an object (get_track) and as a verb (track_get)."""
    report = fnidx.build_report(rows_for_fixture('shapes'), set())
    assert 'track' in report
    assert 'collision' in report.lower()


def test_report_flags_stutter_against_the_class_name():
    report = fnidx.build_report(rows_for_fixture('shapes'), set())
    assert 'Track.get_track' in report


def test_report_stutter_is_case_insensitive():
    d = fnidx.Definition(
        path='x.py', line=1, col=1, name='get_track', module='x', class_name='Track'
    )
    report = fnidx.build_report([(d, fnidx.parse_name('get_track'))], set())
    assert 'stutter' in report.lower()


def test_report_omits_exempt_definitions():
    rows = rows_for_fixture('shapes')
    exempt = {(d.path, d.line) for d, _ in rows if d.name == 'get_bounding_box_fast'}
    report = fnidx.build_report(rows, exempt)
    assert 'get_bounding_box_fast' not in report


def test_report_is_empty_when_the_corpus_is_clean():
    d = fnidx.Definition(
        path='x.py', line=1, col=1, name='get_pose', module='x', class_name='Track'
    )
    assert fnidx.build_report([(d, fnidx.parse_name('get_pose'))], set()) == ''


def test_report_verb_tail_needs_contrast_before_it_fires():
    """One `to` beside eleven `get`s is tail; one beside two is not."""
    def rows(get_count: int):
        out = []
        for i in range(get_count):
            d = fnidx.Definition('x.py', i + 1, 1, f'get_thing{i}', 'x', '')
            out.append((d, fnidx.parse_name(d.name)))
        d = fnidx.Definition('x.py', 999, 1, 'mask_to_pb', 'x', '')
        out.append((d, fnidx.parse_name('mask_to_pb')))
        return out

    assert 'verb tail' not in fnidx.build_report(rows(2), set())
    assert 'verb tail' in fnidx.build_report(rows(11), set())
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd ~/dotfiles && uv run --with pytest pytest bin/tests/test_fnidx.py -k report -v`
Expected: FAIL — `AttributeError: module 'fnidx' has no attribute 'build_report'`

- [ ] **Step 3: Write the report builder**

Add to `~/dotfiles/bin/fnidx.py`:

```python
from collections import Counter

VERB_TAIL_THRESHOLD = 1
VERB_TAIL_CONTRAST = 10


def build_report(
    rows: list[tuple[Definition, Facets]], exempt: set[tuple[str, int]]
) -> str:
    """Corpus-wide conformance report. Computed at end-of-run because collision
    counts and the verb histogram need every row. Empty string when clean.

    `exempt` is keyed by (path, line): exempting a bare name would silence that
    spelling everywhere, including files no .fnidxignore covers."""
    judged = [(d, f) for d, f in rows if (d.path, d.line) not in exempt]

    unparseable = [d for d, f in judged if not f.parsed]
    unspelled = [d for d, f in judged if f.parsed and not f.object]

    objects = Counter(f.object.lower() for _, f in judged if f.object)
    objects.update(f.target.lower() for _, f in judged if f.target)
    verbs = Counter(f.verb.lower() for _, f in judged if f.verb)
    collisions = sorted(set(objects) & set(verbs))

    stutters = []
    for d, f in judged:
        if not f.parsed:
            continue
        spelled = {t.lower() for t in d.name.split('_')}
        context = {d.module.lower()} | ({d.class_name.lower()} if d.class_name else set())
        if spelled & context:
            stutters.append(d)

    # A once-used verb is only suspicious beside a well-established one: the spec
    # frames this as "a verb used once beside a 47-use synonym". Without the
    # contrast gate every verb in a small corpus is tail and the report is noise.
    tail: list[str] = []
    if verbs and max(verbs.values()) >= VERB_TAIL_CONTRAST:
        tail = sorted(v for v, n in verbs.items() if n <= VERB_TAIL_THRESHOLD)

    sections: list[str] = []
    if unparseable:
        sections.append(
            'unparseable ({}):\n'.format(len(unparseable))
            + '\n'.join(f'  {d.path}:{d.line}: {d.name}' for d in unparseable)
        )
    if unspelled:
        sections.append(
            'unspelled object ({}):\n'.format(len(unspelled))
            + '\n'.join(f'  {d.path}:{d.line}: {d.name}' for d in unspelled)
        )
    if collisions:
        sections.append(
            'cross-slot collisions ({}):\n'.format(len(collisions))
            + '\n'.join(
                f'  {t}: object x{objects[t]}  verb x{verbs[t]}' for t in collisions
            )
        )
    if stutters:
        sections.append(
            'stutter ({}):\n'.format(len(stutters))
            + '\n'.join(
                '  {}:{}: {}.{}'.format(
                    d.path, d.line, d.class_name or d.module, d.name
                )
                for d in stutters
            )
        )
    if tail:
        sections.append(
            'verb tail ({}):\n'.format(len(tail))
            + '\n'.join(f'  {v} x{verbs[v]}' for v in tail)
        )
    return '\n\n'.join(sections) + '\n' if sections else ''
```

The collision report counts `target` values as objects, since §3 has targets drawing from the object vocabulary.

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd ~/dotfiles && uv run --with pytest pytest bin/tests/test_fnidx.py -v`
Expected: PASS — the new tests plus every test written in earlier tasks

- [ ] **Step 5: Add the golden report test**

Append to `~/dotfiles/bin/tests/test_fnidx.py`:

```python
def test_golden_report():
    rows = rows_for_fixture('shapes')
    actual = fnidx.build_report(rows, set()).replace(str(FIXTURES) + '/', '')
    expected = (GOLDEN / 'shapes.report.txt').read_text()
    assert actual == expected
```

- [ ] **Step 6: Generate the golden report, then read it before trusting it**

```bash
cd ~/dotfiles/bin/tests
uv run --with pytest python -c "
import sys; sys.path.insert(0, '..')
import test_fnidx as t, fnidx
rows = t.rows_for_fixture('shapes')
open('golden/shapes.report.txt','w').write(
    fnidx.build_report(rows, set()).replace(str(t.FIXTURES)+'/',''))
"
cat golden/shapes.report.txt
```

Confirm before committing: `get_bounding_box_fast` under unparseable; both 1-token `get`s under unspelled object; `track` under collisions with both counts; `Track.get_track` under stutter; that `get_track` the *free function* is **not** a stutter (its module is `shapes`, not `track`); and that there is **no verb-tail section** — the fixture's busiest verb is `get` at ~7 uses, below `VERB_TAIL_CONTRAST`.

- [ ] **Step 7: Run the full suite**

Run: `cd ~/dotfiles && uv run --with pytest pytest bin/tests/test_fnidx.py -v`
Expected: PASS — the new tests plus every test written in earlier tasks

- [ ] **Step 8: Commit**

```bash
cd ~/dotfiles
git add bin/fnidx.py bin/tests/test_fnidx.py bin/tests/golden/shapes.report.txt
git commit -m "feat(fnidx): report unparseable names, collisions, stutter, and verb tail"
```

---

### Task 6: CLI — stdin paths, stdout index, stderr reports

**Files:**
- Modify: `~/dotfiles/bin/fnidx.py`
- Create: `~/dotfiles/bin/fnidx`
- Modify: `~/dotfiles/bin/tests/test_fnidx.py`

**Interfaces:**
- Consumes: every function from Tasks 1-5.
- Produces: `main(argv: list[str], stdin, stdout, stderr) -> int` — injected streams so the test needs no subprocess. Exit code 0 when at least one file parsed, 1 when none did.

- [ ] **Step 1: Write the failing test**

Append to `~/dotfiles/bin/tests/test_fnidx.py`:

```python
import io


def run_main(paths: list[str]) -> tuple[int, str, str]:
    stdin = io.StringIO('\n'.join(paths) + '\n')
    stdout, stderr = io.StringIO(), io.StringIO()
    code = fnidx.main([], stdin, stdout, stderr)
    return code, stdout.getvalue(), stderr.getvalue()


def test_main_writes_index_to_stdout_and_report_to_stderr():
    code, out, err = run_main([str(FIXTURES / 'shapes.py')])
    assert code == 0
    assert 'get_track' in out
    assert 'unparseable' in err
    assert 'unparseable' not in out


def test_main_emits_no_header_row():
    _, out, _ = run_main([str(FIXTURES / 'shapes.py')])
    assert not out.startswith('file\t')


def test_main_every_row_has_nine_fields():
    _, out, _ = run_main([str(FIXTURES / 'shapes.py')])
    for line in out.splitlines():
        assert len(line.split('\t')) == 9


def test_main_applies_ignore_file_per_path():
    _, out, err = run_main([str(FIXTURES / 'peers' / 'vendor_code.py')])
    assert 'DoSomethingEntirelyDifferent' in out   # indexed
    assert 'DoSomethingEntirelyDifferent' not in err  # but exempt from reports


def test_main_skips_unparseable_files_and_warns():
    bad = FIXTURES / 'broken_syntax.py'
    bad.write_text('def (: bad python\n')
    try:
        code, out, err = run_main([str(bad), str(FIXTURES / 'shapes.py')])
        assert code == 0            # one file parsed, so success
        assert 'broken_syntax.py' in err
        assert 'get_track' in out
    finally:
        bad.unlink()


def test_main_exits_nonzero_when_nothing_parsed():
    code, out, err = run_main([str(FIXTURES / 'does_not_exist.py')])
    assert code == 1
    assert out == ''
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd ~/dotfiles && uv run --with pytest pytest bin/tests/test_fnidx.py -k main -v`
Expected: FAIL — `AttributeError: module 'fnidx' has no attribute 'main'`

- [ ] **Step 3: Write the CLI**

Add to the end of `~/dotfiles/bin/fnidx.py`:

```python
import sys
from typing import TextIO


def main(argv: list[str], stdin: TextIO, stdout: TextIO, stderr: TextIO) -> int:
    """Read paths from `stdin`, write the TSV to `stdout`, reports to `stderr`.
    Returns 1 only when no file parsed at all."""
    if argv:
        print(f'fnidx: unexpected arguments {argv}; paths come from stdin', file=stderr)
        return 2

    rows: list[tuple[Definition, Facets]] = []
    exempt: set[tuple[str, int]] = set()
    parsed_any = False

    for raw in stdin:
        path = raw.strip()
        if not path:
            continue
        try:
            source = Path(path).read_text()
            definitions = scrape_python(path, source)
        except (OSError, SyntaxError, ValueError) as exc:
            print(f'fnidx: skipping {path}: {exc}', file=stderr)
            continue
        parsed_any = True
        ignore_globs = load_ignore_globs(path)
        for definition in definitions:
            facets = class_as_object(definition, parse_name(definition.name))
            rows.append((definition, facets))
            if is_exempt(definition, ignore_globs):
                exempt.add((definition.path, definition.line))
            print(tsv_row(definition, facets), file=stdout)

    report = build_report(rows, exempt)
    if report:
        stderr.write(report)
    return 0 if parsed_any else 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:], sys.stdin, sys.stdout, sys.stderr))
```

Rows stream to stdout as they are produced; only the report waits for the whole corpus.

Spec §8 calls for one scraper per language. `main` calls `scrape_python` directly rather than dispatching on file extension: with exactly one language there is nothing to dispatch on, and the seam the spec cares about is the `scrape_*(path, source) -> list[Definition]` signature, which a future `scrape_cpp` would satisfy without touching the parse, emit, or report stages. Add the dispatch when the second language arrives.

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd ~/dotfiles && uv run --with pytest pytest bin/tests/test_fnidx.py -v`
Expected: PASS — the new tests plus every test written in earlier tasks

- [ ] **Step 5: Write the launcher**

```bash
cat > ~/dotfiles/bin/fnidx <<'EOF'
#!/usr/bin/env bash
DIR="$(dirname "$(readlink -f "$0")")"
exec uv run "$DIR/fnidx.py" "$@"
EOF
chmod +x ~/dotfiles/bin/fnidx ~/dotfiles/bin/fnidx.py
```

Same `readlink -f` idiom as `bin/pydef`, so the launcher works through the `~/.local/bin/` symlink.

- [ ] **Step 6: Verify end-to-end on real code**

```bash
cd ~/dotfiles
git ls-files 'bin/*.py' | ./bin/fnidx > /tmp/fnidx-smoke.tsv
echo "exit=$?"
head -5 /tmp/fnidx-smoke.tsv
awk -F'\t' 'NF != 9 {print "BAD FIELD COUNT: " $0}' /tmp/fnidx-smoke.tsv
cut -f8 /tmp/fnidx-smoke.tsv | sort | uniq -c | sort -rn | head
```

Expected: exit 0; every line has 9 fields (the `awk` prints nothing); the verb histogram is readable. The report appeared on the terminal, not in the TSV.

- [ ] **Step 7: Link it onto PATH the way the sibling tools are**

```bash
ln -sf ~/dotfiles/bin/fnidx ~/.local/bin/fnidx
command -v fnidx && git ls-files '*.py' | fnidx | head -3
```

- [ ] **Step 8: Commit**

```bash
cd ~/dotfiles
git add bin/fnidx bin/fnidx.py bin/tests/test_fnidx.py
git commit -m "feat(fnidx): wire the CLI, stdin paths in, TSV out, reports on stderr"
```

---

## After the plan

Update `.docs_claude/PLANS_TOC.md` per its own maintenance instructions — a chronological entry plus a topic-section entry, with the abstract and a "Key changes" list (`+bin/fnidx.py`, `+bin/fnidx`, `+bin/tests/test_fnidx.py`, `+bin/tests/fixtures/`, `+bin/tests/golden/`, `+~/.local/bin/fnidx` symlink). The `index-plan-docs` skill does this.

The picker is deliberately out of scope (spec §9) and gets its own plan, written against a real index.
