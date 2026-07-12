---
name: find-the-seam
description: Find WHERE to split a big function into independent parts by tracing dataflow — chains, local vs escaping variables. The companion to reusable-parts: that skill decides whether a function fuses logic; this one locates the cut and picks the wiring (hoist / pipeline / fuse).
argument-hint: "[function or file to slice]"
allowed-tools: Read, Edit, Grep, Bash(git diff:*)
---

# Find the Seam

`reusable-parts` tells you a function fuses logic and should be composed of independent
parts. It does not tell you *where the boundaries are*. This skill does: you find the cut
by tracing dataflow, not by reading top-to-bottom.

## Two necks make a function

A function is a **bulge of local variables joined to the outside by a thin neck on each
side** — a few inputs in, one or two outputs out. Extract where both necks are thin:

- **Input neck** — count the arrows *in* (`reusable-parts` test 5). A block that reads 3
  of 26 in-scope variables has a thin input neck.
- **Output neck** — count the variables that *escape*. One value leaving, the rest dying
  inside → thin output neck. If five names escape to five places, you cut in the wrong
  spot.

You need both. Thin input alone isn't enough; the single escaper is what proves the cut is
clean and not arbitrary.

## Definitions

- **Chain toward an output** — pick a value the code downstream needs (stored on `self`,
  returned, read far below); follow the wires *backward* and collect every line that feeds
  it. That set is the output's chain.
- **Local** — every read of the name sits inside one output's chain. It's scratch: dies
  when the block ends, becomes the extracted function's private guts.
- **Escapes** — a read sits in a *different* output's chain (or another method / a return).
  It's the interface: it must cross the seam as an argument or a return value.

The whole classification is one question per assigned name: **is it read by more than one
output's chain?** One chain → local. Two → escapes.

## Procedure

1. **List the outputs** (values consumed downstream / on `self` / returned).
2. **Slice backward** from each: which lines feed it, transitively?
3. **Tag every LHS** local or escapes by tracing *reads across the whole scope* — not by
   line adjacency. A line parked between a def and its use only matters if it actually
   reads/writes those names.
4. **Gather the slice**: slide each statement next to its chain-mates (code motion — legal
   past any line that doesn't read its output or write its inputs). If it separates cleanly,
   the interleaving was cosmetic → extract. If a dependency blocks the move, you found a
   real coupling → it's an interface value or a genuine fusion.

## What an escape means for the wiring

How a value escapes picks the composition shape:

- **Case 1 — shared input → hoist.** Read by *both* chains. Promote its computation above
  both; pass it in as an explicit arg to each. Computed once, so they can't disagree.
  Avoid the two tells of a wrong cut: one function reaching into the other's internals, or
  each recomputing it (drift).
- **Case 2 — one chain's output feeds the next → pipeline.** Escapes one direction into one
  other chain. Run producer, feed its result to the consumer.
- **Case 3 — mutual dependency → it's one function.** A needs B *and* B needs A. Stop
  fighting it; name it honestly as a single function.

## Case study — the chains

Two outputs, `oa` and `ob`:

```
oa ← b ← a        # oa's chain = {a, b, oa}
ob ← y ← x        # ob's chain = {x, y, ob}
```

`a` is read only by `b`, and `b` is in `oa`'s chain → one chain → `a` is **local** to `oa`;
it vanishes inside `A`. Two disjoint chains → two functions, even if the source interleaves
them (`a=f(); x=g(); b=a+1; y=x+2; ...`) — adjacency is noise, the read-set is truth.

Change one line to `b = a + x`: now `x` is read by `y` (ob's chain) **and** `b` (oa's
chain) → **escapes**. Two chains read it → hoist it (Case 1):

```python
x  = compute_x()   # hoisted above both
oa = A(x)          # takes x
ob = B(x)          # takes x
```

## Case study — a stacker `__init__` (real)

One `__init__` fused: measure bboxes off the stage, compute column footprints (pure numpy),
then seat each prim. Two outputs: `self.columns_xy` and `self._placements`.

```
columns_xy  ← col_xs, col_ys ← left_edges, total_w, gaps ← col_widths ← sizes
_placements ← (the loop)      ← columns_xy, sizes, centers
```

- `col_widths`, `gaps`, `total_w`, `left_edges`, `col_xs`, `col_ys` — read only within the
  `columns_xy` chain → **local**, they disappear inside `wall_layout`.
- `columns_xy` — read by the loop (the `_placements` chain, a *different* output) →
  **escapes**, one direction → **Case 2, pipeline**: `wall_layout` produces it, `stack`
  consumes it.
- `sizes` / `centers` — read by the layout chain *and* the loop → **escape into both** →
  **Case 1, hoist**: computed up front in a measure phase, passed into both.

The escapes dictate the finished orchestrator — `sizes` hoisted, `columns_xy` pipelined:

```python
sizes, centers = measure(prim_paths)               # Case 1: hoisted shared input (impure)
columns_xy     = wall_layout(col_widths, col_ys)   # Case 2: produces the bridge (pure)
placements     = stack(columns, columns_xy, sizes, centers)   # consumes both (pure)
```

The inline geometry that only ever touched a bbox — "origin translation that lands the
centroid on a target point" — was its own thin-neck leaf (`centroid_at_point(center,
target)`); note `size` is *not* an arrow into it, so it's not in the signature.

## When applying this skill

1. Confirm the function is worth cutting (`reusable-parts` first — is logic actually fused?).
2. Name the outputs; slice each backward.
3. Tag LHS local/escapes by tracing reads across the whole scope, ignoring line order.
4. For each escaper, decide hoist / pipeline / fuse.
5. Extract locals into leaves; reduce the original to a calling sequence over them.
6. Sanity check: one escaper per cut. Many escapers → wrong seam, re-cut.
