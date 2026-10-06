---
name: tracing-symbol-provenance
description: Traces the flow of a symbol — where its contents come from, where it goes, or both — as a dataflow/call-graph diagram plus annotated code. Use for 'what's in X / who fills X / where does X go / how does X reach Y / show the flow of X'.
argument-hint: <symbol> [file:line] [upstream|downstream|both]
allowed-tools: Bash(grep -n *), Bash(rg -n *), Bash(git blame *), Bash(git log *)
---

# Tracing Symbol Flow

Answer "how does X flow" by showing the lines where X **changes meaning**: where
information enters it, and where it is consumed. Don't list the lines that just copy it
along. The deliverable is a diagram (a dataflow graph across stages, or a call graph
within a process) with numbered markers, plus a verbatim, annotated snippet for each
marker.

## Pick the direction

Take the direction from the question. If it's ambiguous, trace both, with the
anchor line in the middle.

| Question | Direction | Stop when every branch reaches |
|---|---|---|
| "What's in X / who fills X" | **upstream** | an external source, or a write that adds information |
| "Where does X go / how does X reach Y / what does X affect" | **downstream** | a consumer that uses X up, or the named target Y |
| "Show the flow of X" | **both** | both of the above |

Start the explanation at the anchor line the user named, then work outward one hop at
a time. Don't build up from the leaves.

## The trap

The first draft lists the copies: the assignments to X upstream (`x = y`), or the
calls that pass X along downstream (`f(x)` → `g(x)`). That is tautological, because it
only moves the question to the next name. Keep following copies until every branch
ends at a line that **changes meaning**:

- **Upstream, information-adding:** an external source (log, sensor, file, network),
  or a write that inserts, appends, computes, or parses.
- **Downstream, consuming:** X is combined with other data (multiplied into a loss,
  joined, used as a mask or index), reduced (sum/mean/max), thresholded or branched
  on, serialized to output, or dropped.

Those lines are the answer. The copies are the route between them.

## Workflow

1. **Pin the symbol** at the line the user named. Note its type and shape, since that
   tells you what one element holds.
2. **Classify every hit.** Grep the name and sort the hits into
   - *moves*: assignment, `std::move`, returning it, passing it as an argument,
     tuple unpacking, reshaping/broadcasting, copying into or out of a message field;
   - *meaning-changing lines*: the upstream and downstream kinds listed under
     "The trap".
3. **Follow moves across renames** (local → return value → caller's local → struct
   member → message field → parameter) in the chosen direction, until each branch
   reaches a meaning-changing line. Record every name the data takes on the way.
4. **Record what X meets.** At each consuming line, name what X is combined with and
   how: additive or multiplicative, which mask, which denominator. At the final sink,
   say whether X itself is serialized or differentiated, or is only working material
   (for example, a detached weight that scales a loss but gets no gradient).
5. **Note the conditions.** If the path only runs under a flag or branch (for
   example, `if extra_losses:`), say so up front. It decides whether X matters at all.
6. **Separate the data from the tool that builds it.** A buffer, builder, or cache
   object and the container it hands out are different things. Say which is which.
7. **Choose the diagram's level of abstraction:**
   - Across processes or pipelines: the stages that pass data (graph nodes,
     processes). A component inside a stage is an annotation, not a box. If the edges
     are implicit (publish/subscribe), say so and cite the subscriptions.
   - Within one process: a **call graph** of the functions X passes through, with
     `path:line` on each call edge and markers on the lines where X lives.
8. **Verify** every `path:line` with `grep -n` against the current checkout, right
   before citing it. Files change during a session; if HEAD moved, say so and re-read
   the affected code. If the user asks whether something predates a change,
   `git blame` the lines and give each layer its author and commit.
9. **Write the answer** in the format below.
10. If a live nvim session is available, push the markers as a quickfix list in
    marker order (see the `pointing-to-code` skill).

## Output format

Sensible default; adjust the section count to the symbol.

**Things to know first** (one to three). Each is a plain idea first, then a
*Names:* line mapping it to identifiers and `path:line`. Typically: what one element
of X is, what X meets downstream (or what builds it upstream), and any condition that
gates the whole path.

**Diagram.** ASCII. Sources at the top, final consumer / disk / loss at the bottom.
Each stage or function is a labeled block. Place ①…⑧ at every point where X exists or
changes. For a call graph, use tree edges (`├─`, `└─`) with `path:line`. Mark the
bottom `← X is NOT written` / `← X gets no gradient` when that applies.

**Table:** marker | what X is at this point (name, container, shape) | contents | `path:line`.

**Step by step.** One block per marker:

````markdown
**① <stage or function>: <what happens here, in plain words>.**

```python
# path/to/file.py:NN
  verbatim line
  ...
  verbatim line                                  # ← what this adds / how X is consumed
```

Contents: <only when they change at this marker>.
````

**Takeaways** (two or three bullets): how many builders or consumers X has, where it
crosses between stages, how it affects the final sink (additive vs. multiplicative,
diluted by a denominator, gated), and whether X is output or working material.

## Rules

- Snippets are verbatim, trimmed with `...`. Put explanations in trailing `# ←` /
  `// ←` comments; never rewrite the code.
- Every marker appears in the diagram, the table, and a snippet block. A marker with
  no code (for example, "parked, waits 12 s") still gets a line saying so.
- Side branches (for example, a metrics dict returned alongside X) get their own
  marker letter (Ⓜ) and are followed to their sink too.
- Call out both *same name, different object* and *different name, same object*.
- Plain idea before project jargon. Name things by what they do, and attach the
  internal name afterwards.
- Keep it local: about eight markers at most. If there are more, split by builder or
  consumer and deliver one per message.
- Label inference as inference. Everything cited should be verified.

## Worked example

`references/case-study-merged-tracks.md` is an upstream trace: it shows the
tautological first answer and the version the user asked to have captured as this
skill. Read it the first time you use this skill in a session. For a downstream trace,
the same shape applies: anchor at the line that produces X, then follow it to the sink.
