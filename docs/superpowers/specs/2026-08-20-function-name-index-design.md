# fnidx — a faceted index of function names

**Status:** design approved 2026-08-20. Revised same day: the module replaces the
namespace name-slot (§3), a 1-token method takes its class verbatim as the object
while normalization is removed as policy-in-mechanism (§3), and the picker is
deferred to its own plan (§9).

## 1. Problem & objective

Recalling a function you wrote means recalling an exact string. The failure is
narrow and predictable: you remember the domain noun (`track`) and roughly where
it lives, and you cannot remember whether you wrote `get_track`, `fetch_track`,
`load_track`, `read_track`, `retrieve_track`, or `lookup_track`.

**Objective:** make function names *parseable into facets*, so recall becomes
navigating a small closed vocabulary instead of guessing a string. A name is not
an opaque identifier; it is a record with fields.

**In scope:** a read-only indexer that reads paths on stdin and emits one TSV row
per function definition on stdout, plus conformance reports on stderr.

**Out of scope:** editing, renaming, call-site rewriting, name authoring/insertion,
and enforcement. The tool never writes to source. The picker is deferred (§9).
Downstream tools consume the TSV.

**Scale:** the convention applies to the author's own greenfield code, Python
first. The trees it is pointed at will contain peers' code too, which is never
expected to conform — `.fnidxignore` (§6) silences those subtrees' report lines
while still indexing them, so they stay findable.

## 2. The facets

| Facet | Meaning | Source | Cardinality |
|---|---|---|---|
| `module` | the file | path stem | one per file |
| `class` | enclosing class, empty for free functions | AST | ~10-50 |
| `object` | the operand of the verb | name, or the class verbatim | ~10-30 per module |
| `verb` | the action | name | ~30, global |
| `target` | second operand, for transfer/conversion verbs | name | sparse |

Facets are independent axes, not a hierarchy: picking `verb=get` then `object=track`
lands in the same place as the reverse. That property is what makes "show me all
objects for this verb" as natural as "all verbs for this object".

The recall mechanism is that the `object` and `verb` value sets fit on one screen.
Seeing thirty verbs at once replaces remembering which one you chose.

`module` and `class` are derived, never spelled — a name that repeats either is a
stutter (§7), the same way Go writes `strings.Split` and not
`strings.StringSplit`.

**The indexer never normalizes.** It extracts what was written and counts it.
Deciding that `Tracks`, `TrackStore`, and `Track` name the same object, or that
`PointCloud` and `pointcloud` do, is a policy the author owns — not something the
mechanism may assert on their behalf, least of all invisibly. The governing rule:
**an equivalence may inform a report; it may never produce a column value.**

## 3. Grammar

Names are tokenized on `_`. The parse is by token count alone — it needs no
vocabulary, and it does not branch on whether the definition is a method:

| Tokens | Parse | Example |
|---|---|---|
| 1 | `verb`; object is the class verbatim, or empty | `TrackStore.get` |
| 2 | `verb_object` | `get_track` |
| 3 | `object_verb_object` | `mask_to_proto` |
| 4+ or 0 | unparseable | `doTheThing` |

**The module is the namespace.** An earlier draft spelled a namespace token into
every free function's name (`perc_get_track`); the file already supplies it, so
the token was redundant. Dropping it collapses the parse to one table and makes
`module` uniform: a `module=tracking` pivot reaches that file's free functions and
its methods alike.

**Word order is arity-dependent by choice.** Arity-1 is verb-first (`get_track`)
because it reads as English and matches every surrounding convention; arity-2 is
infix (`mask_to_proto`) because English wants the preposition between the nouns.
The rejected alternative was object-first everywhere (`track_get`), which is
positionally regular but reads worse. A faceted picker pivots on any facet
regardless, so positional regularity buys nothing at query time.

### Why the target is a slot, not part of the verb

`to_proto` could be read as a single verb. It is not, because then every new target
abstraction (`to_dict`, `to_tensor`, `to_numpy`) adds a verb and the verb set stops
fitting on a screen — losing the one property the design exists to preserve. As a
separate slot, targets draw from the *object* vocabulary that already exists, which
also makes `object=proto` return everything touching protos in either role.

### 1-token names: the class is the object, verbatim

A 1-token name spells no object. For a **method**, the enclosing class supplies it
unchanged:

```
TrackStore.get   →  object=TrackStore   verb=get
```

Not `track`. An earlier draft ran the class name through a normalizer — strip
`Store`/`Manager`/`Cache`, singularize, lower the initial — and that was policy
baked into mechanism: it asserted an equivalence class (`TrackStore` ≡ `Tracks` ≡
`track`) the author never chose, and the undecorated column made the assertion
invisible. Sourcing the object *from* the class is structural, the same kind of
fact as the `class` column; *transforming* it is not the tool's call.

This restores the receiver/operand distinction the facets exist for.
`TrackStore.get` has the class as the operand; `Track.get_pose` has `pose` as the
operand and the class as mere scope. The two columns holding the same value is the
signal, not redundancy — `object=TrackStore` finds verbs acting on the store
itself, `class=TrackStore` finds everything defined on it.

**For a free function the object stays empty**, and for a different reason than the
transform: a module stem is a topic label, not an entity. Imputing from it would
inject `utils`, `helpers`, `config` into the object vocabulary that this design
exists to keep small. The row is still indexed, and §7 reports it.

**Object values therefore mix casing** — `track` from a spelled name, `TrackStore`
from a class — so `cut -f7 | sort -u` lists both `Track` and `track` when both
occur. That is the rule working as intended: the split is visible rather than
silently folded, case-insensitive matching handles it at the query layer, and a
capital initial is a free tell that the value came from a class. If folding is ever
wanted it belongs in the query layer as a file the author owns; the index stays raw
and lossless.

The consequence worth stating: **the scraper contains no heuristics.** Every column
is copied from the AST or split from the name, which makes the golden files in §10
exactly predictable.

### Compound objects: camelCase inside a facet

Domain nouns are often multi-word — `point_cloud`, `bounding_box`, `feature_map`,
`ego_pose` — and `_` is already the facet separator, so `get_bounding_box` would
mis-parse as `object=get, verb=bounding, target=box`.

**Decision: `_` separates facets, camelCase joins words inside one.**

```
get_boundingBox            verb=get           object=boundingBox
pointCloud_to_proto        object=pointCloud  verb=to  target=proto
```

This keeps the token-count parse total and keeps nouns readable. Rejected:
abbreviating to one token (`bbox` or `bb`? — recreates the recall problem one level
down) and `__` as the facet separator (unambiguous but ugly).

The cost is fighting PEP 8 inside identifiers. Accepted: the count parse is the
load-bearing property, and the separator has to be unambiguous for it to hold.

Two consequences for the implementation:

- Tokenizing is still a plain `split('_')`. camelCase lives *inside* a token and
  the parser never looks at it.
- Facet values are therefore mixed-case, and `class` holds CamelCase class names,
  so **all facet comparison is case-insensitive** — including the stutter check, or
  `Track.get_track` would slip through on a `Track` vs `track` mismatch.

## 4. Vocabularies are discovered, never declared

There are no registry files. Every facet value set is a byproduct of the scrape,
so the index cannot drift from the code, and any picker over it shows what
*exists* rather than what is *permitted* — the only thing that makes it able to
find a function you actually wrote.

The cost, accepted knowingly: the tool cannot know the vocabulary stopped being
small. A synonym slip becomes verb #31 silently. It stays visible to a human as a
lopsided count in the verb report (§7).

If mechanical enforcement is ever wanted, generate the pin from the scrape and
diff it. Never hand-author that list.

## 5. Output format

TSV on stdout, 9 columns, fixed positions, empty string for absent facets:

```
file                    ln   col  name              module    class       object      verb  target
perception/tracking.py  88   1    get_track         tracking              track       get
perception/convert.py   12   1    pointCloud_to_pb  convert               pointCloud  to    pb
perception/tracking.py  142  5    get_pose          tracking  Track       pose        get
perception/store.py     31   5    get               store     TrackStore  TrackStore  get
perception/legacy.py    7    1    doTheThing        legacy
```

Rows are: free function; free-function conversion using `target`; method with its
class; 1-token method taking its class as the object; and an unparseable name. The header
above is illustrative — **no header row is emitted**, since it would appear as a
value in every `cut | sort -u` pivot.

**Rejected alternative:** a single `%f:%l:%c:%m` line that vim's default
errorformat parses directly. It packs the facets into `%m`, so every downstream
pivot has to re-split the message — a permanent tax to save ~10 lines of
`setqflist()` lua.

Two column notes:

- `col` is useless for facet queries and kept anyway, because it is what makes a
  quickfix jump land on the name rather than the line start.
- Fixed positions matter more than compactness. `cut -f7` breaking on some subset
  of rows is an expensive class of bug.

## 6. Error handling

**Unparseable names are indexed, not rejected.** They get a row with `module`
filled and the remaining facets empty, and are also named in the report. A
function that exists must always be findable by name or path, or the index
acquires a silent hole exactly where legacy and framework-imposed names live.

### Exemptions

Exempt names are **still indexed** — exemption suppresses the report line only.

Two sources, neither hand-maintained:

1. **Framework-imposed names**, by pattern: dunders, `test_*`, and known callback
   names (`forward`, `on_epoch_end`). The author did not choose them.
2. **`.fnidxignore`**, discovered by walking up the tree from each file. Lines are
   globs matched case-insensitively against the bare function name; `#` comments
   and blank lines ignored. A file containing `*` exempts its whole subtree, which
   is the intended way to silence peers' code:

   ```
   peers/vendor/.fnidxignore     →  *
   perception/.fnidxignore       →  legacy_*
   ```

   All `.fnidxignore` files from the file's directory up to the filesystem root
   apply, union-ed. There is no negation syntax; add it only if a real case
   appears.

A file that fails to parse warns on stderr and is skipped. Exit is nonzero only
if no file parsed at all.

## 7. Reports

**There is no `--report` flag.** The index goes to stdout, the reports go to
stderr, on every run:

```bash
git ls-files '*.py' | fnidx > index.tsv                # reports on the terminal
git ls-files '*.py' | fnidx > index.tsv 2>/dev/null    # if you ever don't want them
```

A flag would mean the drift report only appears when you remember to ask for it,
which for a report you'd check monthly at best means never. Sending it to stderr
means you see it every time you rebuild the index and it can never corrupt the
TSV. Reports are computed at end-of-run, since collision counts and histograms
need the whole corpus.

| Report | Catches |
|---|---|
| unparseable | wrong token count; typos; legacy names |
| unspelled object | a 1-token *free function*; no class to take the object from |
| cross-slot collisions | a token used as both object and verb — `track` ×47 object / ×1 verb is an inverted name |
| stutter | `tokens(name) ∩ (tokens(module) ∪ tokens(class))`, case-insensitive |
| verb tail | a verb used once beside a 47-use synonym |

Structural validity is nearly free to satisfy under a vocabulary-free parser —
any 2-token name parses — so the unparseable report alone catches little. The
collision report is what catches inversion, and it needs no declarations: it is
the corpus checked against itself.

The stutter and collision reports compare case-insensitively, which is the one
equivalence left in the tool. It is confined to the reports and never writes a
column value — a case-sensitive stutter check would never fire at all, since
`class` is CamelCase and name tokens are not.

No git hook, no nonzero exit on violations. The report is something the author
glances at as it scrolls past.

## 8. Extraction

Interface: one scraper per language, returning a list of definitions.

**Python (v1): the stdlib `ast` module, not ast-grep.** This diverges from the
original plan. `ast` gives `FunctionDef`/`AsyncFunctionDef` with exact
`lineno`/`col_offset`, and the enclosing class from a parent walk — the entire
input the parser needs. It handles decorators, `async`, and nesting because it is
the real parser, and it adds no dependency.

**C++ (later): not ast-grep.** Out-of-line definitions (`void Track::get_pose() {}`
in a `.cc`), overloads, templates, and macro-generated declarations are where
pattern matching gets unreliable. Prefer clangd's index or
`compile_commands.json` + clang-query. Keeping this behind the interface means
adding it changes no schema.

Paths arrive on stdin, so file selection composes with the tools that already do
it well. No include/exclude flags.

## 9. Deferred: the picker

Deliberately not in v1. The TSV is useful immediately with `fzf`, `grep`, and
`cut`, and the picker is better designed against a real index than against a
guess.

What is already settled for that later plan:

- **fzf 0.74.2 is installed and verified** to support both `transform-query` and
  `--nth=4..9` field ranges. §11's open question is closed.
- **`~/dotfiles/bin/` already has this exact pattern**: a shell launcher plus a
  self-bootstrapping `nvim --clean -u <tool>.lua` telescope config sharing
  `telescope_boot.lua`. `pydef` is an interactive Python def/class picker and
  `fgr` its live-grep sibling. An earlier draft of this spec recommended fzf-lua
  over telescope; that was written without knowing this harness exists, and the
  argument for fzf (one implementation serving both CLI and editor) is already
  satisfied by it.
- **Multi-term matching is the core query mechanism**, whichever host: terms
  AND-ed and matched independently in any order is the any-order property the
  facets were chosen for.

## 10. Testing

The tool is a pure function from a file set to two text outputs, so golden files
are the whole strategy. Fixture modules containing every name shape from §3 and
every violation class from §7; assert the TSV and the report byte-for-byte.

## 11. Open decisions

| Item | Resolution path |
|---|---|
| Picker host: telescope sibling of `pydef`, or fzf | decide against a real index, in the picker's own plan (§9) |
