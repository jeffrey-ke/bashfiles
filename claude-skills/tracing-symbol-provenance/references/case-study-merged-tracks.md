# Case study: what's in `holder->merged_tracks`

From a session on Nuro's behavior data-dumping pipeline. The user pointed at
`data_dumping_node.cc:1081`, where `holder->merged_tracks` is passed into the
arrival-label routine, and asked who populates it. The first answer listed
assignments; the user called it tautological. Over several turns the answer took the
shape below, and the user asked for that shape to become this skill.

## What changed

| Move | Before | After |
|---|---|---|
| Stopping point | The two assignments to the symbol (`:646`, `:1625`) | The external source (the tracker's recorded messages) and the lines that insert or extend entries |
| Data vs. tool | `merged_tracks` and `all_merged_tracks` read as two maps | One path collection, plus the stitching *tool* whose internal table it is |
| Renames | Only the variable's own name | Every name it takes: tool's `storage_` → message field `MergedTracks{.tracks}` → `holder.merged_tracks` → local tool `all_merged_tracks` → parameter `tracks` |
| Abstraction | Functions and lines | Graph nodes (`TRACKS` → `LEARNED_BEHAVIOR_FEATURE` → `DATA_DUMPING_FEATURE` → `DATA_DUMPING_LABEL`), with the stitcher shown *inside* a node |
| Code | `path:line` citations only | A verbatim snippet per marker, each with `// ←` notes on what it adds |
| Output or not | Unstated | "The path collection is NOT written; what reaches disk is computed from it" |

## Before

```markdown
Two writers, one after the other. Only the second version reaches `:1081`.

1. At the example's own moment T: the snapshot stage copies the map in —
   `holder.merged_tracks = {merged_tracks.begin(), merged_tracks.end()};` (`:646`)
2. About 12 s later: the label stage overwrites it —
   `holder.merged_tracks = all_merged_tracks.GetAllMergedTracks();` (`:1625`)
```

The user replied: *"Those seem tautological, no? What's contained in merged_tracks or
all_merged_tracks, and who populates them?"*

## After (abridged: 3 of the 7 marker blocks shown)

```markdown
### Two things to know first

**1. The path collection.** A lookup table from each object's id to its recorded
path: timestamped position/velocity estimates, size, class probabilities, confidence.
*Nuro names:* `merged_tracks`, `std::unordered_map<uint32_t, Track>`.

**2. The stitching tool.** The tracker sends only the last ~2.5 s of each object per
message (`track_buffer.h:13`). The tool joins those overlapping pieces into one path
per id and keeps the table inside itself; "give me the paths" hands out that table.
*Nuro names:* `TrackBuffer`; its table is `storage_` (`track_buffer.h:106`).

### Where it lives

 drive log, replayed ───────────────────────────────┐
   │ tracker messages (~10/s)                        │ raw tracker msgs
   ▼                                                 │
 TRACKS ── this tick's objects ──► LEARNED_BEHAVIOR_FEATURE
                                   ① stitching tool #1's table (last 5 s)
                                        │ ② copied into the output message
                                        ▼
                                   DATA_DUMPING_FEATURE
                                   ③ copied into the new cell
                                        │ ④ parked ~12 s
                                        ▼                 ▼
                                   DATA_DUMPING_LABEL ◄── buffered
                                   ⑤ stitching tool #2: starts from ③, adds msgs after T
                                   ⑥ replaces the cell's copy
                                   ⑦ handed to the arrival routine
                                        ▼
                                   record on disk   ← the path collection is NOT written

**① Inside the model-input builder: tool #1, keeping the last 5 s.**

    // object_tracks_producer.cc:127  — every tick
      track_buffer_.EraseAllExpired(..., kMaxTrackMissingDuration);  // ← drop objects unseen >3.85 s
      for (const auto& track : input_tracks.tracks) {
        track_buffer_.Insert(track);                                 // ← stitch in this tick's pieces
      }

**③ The snapshot node copies it into the new cell — the only point it crosses nodes.**

    // data_dumping_node.cc:640
      const auto& merged_tracks = feature_node_out.merged_tracks->tracks;  // ← read ② off the message
      ...
      holder.merged_tracks = {merged_tracks.begin(), merged_tracks.end()}; // ← now part of the cell

**⑤ Once the cell is ripe, tool #2 extends it past T.**

    // data_dumping_node.cc:1575
      onboard::perception::TrackBuffer all_merged_tracks(history_length);  // ← tool #2, local
      all_merged_tracks.Update(holder.merged_tracks);                      // start from ③
      for (auto it = std::ranges::upper_bound(detected_objects_buffer_, holder.cur_ts, ...); ...) {
        all_merged_tracks.UpdateWithoutErase(**it);                        // ← add objects first seen after T

Contents afterward: everything from ③ plus everything seen from T to T+10 s.

### Takeaways
- One path collection carried by the cell, with two builders (① up to T, ⑤ through T+10 s).
- ③ is the only point where it crosses nodes.
- It is working material; what reaches disk is computed from it.
```

## What made the difference

- The follow-up questions came in this order: *what's in it* → *is that stage a node,
  and where is the graph in code* → *plain terms, with snippets placed on the graph*.
  Answer all three up front.
- The user caught a mismatch between "stitching tool" and "cells". State explicitly
  which unit is being joined (pieces of one object's path from successive messages)
  and which units never are (cells).
