# Case Study — Prologue Collaborators (callee vs caller is a false choice)

Function parameters are collaborators too. An onboard planner function decides whether an emergency vehicle (AEV) blocks the next intersection on ego's route.

**1. Fused: the callee asks for everything.**

```cpp
FindAevBlockedIntersection(route, turn_around, ego_xy, map, aevs);
```

The AEV logic needs only a box, a point and a heading. It takes the route and the map just to work those out first.

**2. The feared alternative: the caller does the working-out.**

```cpp
auto [interval, box] = ...;                         // map query, overlap, skip rules
const double mid = 0.5 * (interval.left() + interval.right());
const auto point = route.ToPoint(mid);
const auto dir = route.DirectionAt(mid);
FindAevBlockedIntersection(box, point, dir, aevs);
```

Narrow signature, but the caller now has to know how to find the intersection. This is the tension: narrowing the callee seems to just inline computation into the caller.

**3. The way out: the working-out becomes its own callee.**

```cpp
const auto intersection = FindNearestRouteIntersection(route, turn_around, ego_xy, map);
if (!intersection) return out;
return FindAevBlockedIntersection(*intersection, aevs);
```

The caller still knows nothing about how either step works, and each function takes only what it uses. A second consumer (a siren rule that needs the next intersection without any AEV analysis) can now call the first step alone. If callers want one call, keep the old signature as a wrapper that does these two calls.

**The false choice** was between callee-does-everything (1) and caller-does-it (2). Option 3 is a second callee.

**The rule:** if a function uses an input only to compute other inputs before its real work starts, move that computation into its own function. Don't push it up to the caller. Test: look at what you pass to the collaborator. `route.DirectionAt(mid)` with `mid` fixed before the AEV loop is a prologue, so split it out. `route.DirectionAt(route.Project(aev.position))` inside the loop asks something only the callee can phrase, so the route stays.
