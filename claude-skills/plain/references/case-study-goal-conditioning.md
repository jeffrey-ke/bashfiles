# Case study: pullover goal conditioning, phase A

A walkthrough of when Nuro's driving model (ILP) starts steering to a pullover
spot. The user asked for a plain-language redo of the first version; the second
version is the one they called much better.

## What changed

| Move | Before | After |
|---|---|---|
| Background first | Jumped straight into the mechanism | "Three things to know first": propose vs. choose, two kinds of destination, pullover stages, each as a plain idea |
| Names come second | Identifiers were the subject of sentences (`InactiveState moves to SearchingState`) | Each idea closes with a *Nuro names:* line mapping it to identifiers and `path:line` |
| Outline rows | Described in identifiers ("pin on, goal_pose off", "`violated_goal_conditioning_constraint`") | Described as what's happening ("the car knows roughly where it will stop, but the driving model hasn't been told") |
| Mechanism as a question | Four numbered algorithm steps | One question the code answers ("if the car started braking gently right now, would it still stop comfortably short of the spot?"), named the "runway check" |
| Tables explain rather than list | `Param \| Value \| Where` | `Check \| Value \| Plain meaning` |
| Units made intuitive | −1.0 m/s², 3 rad | "About 0.1 g, a relaxed stop"; "more than about 170°" |
| Why it's designed this way | Absent | Why the model isn't told early: it cuts corners when steering at a target (cited to PR #270019 and a code comment) |

Every fact, number, and citation from the first version survives in the second.
The only addition is the design reason, and it was already sourced earlier in
the session.

## Before

```markdown
## A — Searching: pin on, `goal_pose` off

**How it starts.** A DROPOFF trigger sets `pullover_cause`, and `InactiveState` moves to `SearchingState` (`pullover_state_machine.cc:198-204`). `SEARCHING` counts as "active" (`pullover_utils.cc:32-35`), so `GetRouteGoal` begins passing the pin to the model on this tick. Entering Searching also clears the goal-conditioning flag (`pullover_state_machine.cc:349-353`).

**What happens every tick:**
- The PoseGen PUDO head sees the pin and proposes candidate poses. These are thrown away unless `route_goal_was_set` is true (`pullover_state_machine_utils.cc:1141-1156`).
- `UpdateTargetPose` picks one: the ML pose if it passes validation, otherwise the heuristic fallback. The result goes into `target_pullover_pos_smooth`.
- ILP's `goal_pose` token is still masked, so ILP drives off the route exactly as in normal driving.

**The planner still uses the chosen pose in this phase, just not as an ILP input.** Motion selection checks every candidate plan against it (`create_candidate_info.cc:195-227`), using `ComputePulloverFeasibility` (`pullover_feasibility_utils.cc:80-160`):

1. Take the plan and simulate braking gently to a stop from right now.
2. Project that stopping point onto the route.
3. The plan is **feasible** if it stops at least a set distance **before** the target pose.
4. It's also infeasible if it drifts sideways away from the pose early in the plan. This check is skipped if the route turns more than 3 rad before reaching the target.

| Param | Value | Where |
|---|---|---|
| `plan_reaction_decel_goal_conditioning` | −1.0 m/s² | `planner.pbtxt:493` |
| `min_dist_from_target_pos_goal_conditioning` | 15.0 m | `planner.pbtxt:495` |

In plain terms, the check asks: **"Is there still enough room that the car could brake gently and stop well short of the spot?"** While the answer is yes, ILP doesn't need the goal pose; normal route-following gets the car to the right neighbourhood. Phase A is the long approach. It ends the first time the selected plan fails this check.
```

## After

```markdown
## A — Approach

### Three things to know first

**1. Proposing and choosing are separate steps.** On every planning cycle, a learned driving model proposes several candidate trajectories (short future paths with speeds). Then a separate rule-based step scores them and picks one to execute. The model suggests; the rules decide.
*Nuro names:* the model is **ILP** (a decoder on top of **BFM**); the choosing step is **motion selection**.

**2. A drop-off involves two different "destinations."**
- **Requested point:** where the rider asked to be dropped off. It's a spot on the map with no direction, and it may be in the middle of the road or a driveway.
- **Committed spot:** the exact place the car decides to stop, with position and heading, usually against the curb and possibly tens of metres from the requested point.

The requested point goes in; the committed spot comes out.
*Nuro names:* requested point = **`route_goal_location`** (the "pin"); committed spot = **`goal_pose`** once it's given to the driving model, stored in the planner as **`target_pullover_pos_smooth` / `_yaw_smooth`**.

**3. A pullover has stages.** A small state tracker records where the car is: not pulling over → looking for a spot → committed and approaching → stopped.
*Nuro names:* `INACTIVE` → `SEARCHING` → `ATTEMPTING` → `COMPLETED`, in the **pullover state machine** (`pullover_state_machine.cc`).

### What happens during the approach

**It starts** when a drop-off comes within range and the tracker moves from "not pulling over" to "looking for a spot" (`pullover_state_machine.cc:198-204`). From that cycle on, the requested point is fed to the model (`planner_node_utils.cc:77-85`, gated by `pullover_utils.cc:32-35`).

**Every cycle, a spot gets picked.** A learned spot-proposer looks at the requested point and suggests candidate curbside spots. Rule-based checks throw out bad ones: too close to a hydrant, overlapping a parked car, unreachable, and so on. The best survivor becomes the committed spot. If nothing survives and the car is running out of room, a hand-written spot picker is used instead. While searching, the committed spot can move from cycle to cycle.
*Nuro names:* spot-proposer = **PoseGen** (the pose-generation head); checker = **`UpdateTargetPoseML`**; hand-written fallback = **`UpdateTargetPoseHeuristic`** — the function Ben linked (`pullover_state_machine_utils.cc:1534-1571`).

**The driving model is not told the committed spot yet.** It follows lanes as in ordinary driving. This is deliberate. When the model is steering at a target point, it tends to drop normal driving habits and cut corners toward the target, sometimes even trying to drive through obstacles. That's stated in jyurkanin's DistantGoalPose PR (#270019), and the code comment at `planner_node_utils.cc:90-92` says goal conditioning stays off until *"a nominal ILP plan cannot comfortably reach the goal pose."*

**The choosing step still keeps the spot in mind.** For the trajectory it's about to execute, it runs a **runway check**: *if the car started braking gently right now, would it still stop comfortably short of the spot?*

| Check | Value | Plain meaning |
|---|---|---|
| Gentle braking rate | 1.0 m/s² (`planner.pbtxt:493`) | About 0.1 g, a relaxed stop |
| Required slack | 15 m before the spot (`planner.pbtxt:495`) | "Still plenty of room" |
| Sideways drift | Fails if the trajectory veers away from the spot early | Car is heading the wrong way laterally |
| Exception | Passes anyway if the route turns sharply (more than about 170°) before the spot | Don't force a shortcut across a loop |

*Nuro names:* the runway check is **`ComputePulloverFeasibility`** (`pullover_feasibility_utils.cc:80-160`), run per candidate at `create_candidate_info.cc:195-227`; its result is **`is_feasible_for_goal_conditioning`**.

While the runway check passes, ordinary lane-following gets the car to the right neighbourhood without help. **The approach ends the first time the trajectory the car actually picks fails the runway check**, meaning the car is now close enough that it has to start aiming for the exact spot.
```
