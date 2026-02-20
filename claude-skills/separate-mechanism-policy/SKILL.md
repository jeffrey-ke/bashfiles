---
name: separate-mechanism-policy
description: Identify and fix code that fuses mechanism and policy. Use when reviewing code for architectural issues, refactoring tangled abstractions, or when a function is making decisions that belong to its caller.
argument-hint: [file-or-function to analyze]
---

# Separate Mechanism from Policy

When analyzing code for mechanism/policy fusion, apply this process:

## Definitions

- **Mechanism:** the capabilities a function provides — the "how." Pure computation, transformation, orchestration of lower-level operations.
- **Policy:** the decisions a function makes — the "what" and "when." Which algorithm, which parameters, which cases to handle, which fallbacks to use.
- These are **relationships between layers**, not absolute labels. Every function is policy to its callees and mechanism to its callers.

## The Diagnostic

For each function, examine every `if` branch, default value, and hardcoded choice. Ask:

**"Did the caller ask for this, or did the function decide it for them?"**

If the function decided, that's policy fused into mechanism. The caller loses a choice they might reasonably want to make differently.

## What Fused Code Looks Like

### Pattern 1: Mechanism that hardcodes domain decisions

The function knows things about the caller's world that it shouldn't.

```python
# BAD — physics engine knows about game entities
def resolve_collision(contact):
    if contact.body_a.tag == "debris":
        return
    if contact.impulse > 10.0:
        play_sound("impact.wav")
    apply_bounce(contact, restitution=0.5)
```

Problems:
- `"debris"` is a game concept — the physics engine shouldn't know it exists
- `play_sound` couples physics to audio — a structural simulation using this engine gets sound effects
- `restitution=0.5` is hardcoded — every caller gets the same bounciness

```python
# GOOD — mechanism provides capability, policy decides
def resolve_collision(contact, restitution, on_collision=None):
    apply_bounce(contact, restitution)
    if on_collision:
        on_collision(contact)
```

Now the caller decides restitution, decides what happens on collision (sound, logging, nothing), and decides which contacts to skip (by filtering before calling).

### Pattern 2: Function that silently narrows the caller's options

The function makes choices the caller can't override without replacing the function.

```python
# BAD — caller is forced into smoothing and a fallback strategy
def get_next_direction(robot, sample):
    raw = robot.model(sample)
    robot.history.append(raw)
    if len(robot.history) < 5:
        return raw
    return np.mean(robot.history, axis=0)
```

Problems:
- Every caller gets smoothing whether they want it or not
- The threshold `5` is a domain judgment ("not enough data") decided silently
- The fallback (return raw) is a policy the caller might disagree with

```python
# GOOD — pure mechanism, caller controls everything
def smooth_directions(history, new_direction):
    history.append(new_direction)
    return np.mean(history, axis=0)
```

The caller decides when to smooth, whether to have a fallback, and what "not enough data" means.

### Pattern 3: Conditional algorithm selection buried in mechanism

The function picks a strategy internally instead of receiving one.

```cpp
// BAD — mechanism chooses the algorithm
void compress(const std::vector<uint8_t>& data, std::vector<uint8_t>& out) {
    if (data.size() > 1024 * 1024) {
        zstd_compress(data, out);      // policy: big data gets zstd
    } else {
        lz4_compress(data, out);       // policy: small data gets lz4
    }
}
```

Problems:
- The 1MB threshold is a domain decision
- The caller might want zstd for small data too, or a different algorithm entirely
- Adding a new algorithm means editing this function

```cpp
// GOOD — caller picks the strategy
using Compressor = std::function<void(const std::vector<uint8_t>&, std::vector<uint8_t>&)>;

void compress(const std::vector<uint8_t>& data, Compressor compressor,
              std::vector<uint8_t>& out) {
    compressor(data, out);
}
```

### Pattern 4: Caller reaching into mechanism internals

The inverse problem: the caller does the callee's job.

```python
# BAD — caller orchestrates the model's internal pipeline
def run_rollout(robot, model):
    model.eval()
    with torch.no_grad():
        features = model.backbone(sample.left)
        neck_out = model.neck(features)
        direction = model.head(neck_out).detach().cpu().numpy()
    move(robot, direction)
```

Problems:
- The caller knows about backbone, neck, head — internal architecture
- If the model changes structure, this caller breaks
- This is mechanism leaking upward: the caller is doing the callee's job

```python
# GOOD — caller tells the model what to do, not how
def run_rollout(robot, model):
    direction = model(sample)
    move(robot, direction)
```

## When `if` Statements Are Fine in Mechanism

An `if` in mechanism code is acceptable when it branches on **the data the caller passed in** or on **conditions intrinsic to the mechanism's own domain**:

```python
# FINE — branching on the physics of the situation
def resolve(contact, restitution):
    if contact.is_resting():
        apply_friction(contact)
    else:
        apply_bounce(contact, restitution)
```

Resting vs. bouncing is a physics distinction, not a domain decision from above. Any caller in any domain would want this behavior.

**The test:** Would this `if` condition make sense if a completely different caller, in a completely different domain, used this function?

## The Core Principle: Undeclared Inputs

Every case of "output not determined by inputs" reduces to: **there's an input that isn't in the signature.** Hidden history buffer, closed-over variable, generator state, global variable, file system, clock, network, sensor — they're all undeclared inputs.

The question is always the same one: **does the caller know the undeclared input exists, either from the interface or from universal convention?**

### When undeclared inputs are acceptable

Some functions are universally understood to depend on something beyond their arguments:

```python
# FINE — everyone knows what a clock is
timestamp = time.now()

# FINE — "random" is the stated purpose
value = random.uniform(0, 1)

# FINE — reading a sensor is what the function does
image = camera.get_rgb()

# FINE — generators are universally understood as stateful iterators
value = next(fibonacci_gen)
```

These work because the caller already has a correct mental model from the interface alone. No one reads the source of `time.now()` to understand it returns different values each call. The non-purity isn't hidden — it's the entire point.

### When undeclared inputs cross the line

The function's stated purpose is one thing, but its output secretly depends on something else:

```python
# BAD — stated purpose is "compute direction from robot and sample"
# actual behavior depends on hidden call history
def get_next_direction(robot, sample) -> np.ndarray:
    raw = robot.model(sample)
    robot._history.append(raw)
    return np.mean(robot._history, axis=0)
```

The caller reasons: same robot, same sample, same output. They're wrong, and they can't discover it from the interface. The history is an undeclared input.

### Naming alone doesn't fix it

`get_next_direction_stateful(robot, sample)` hints at the problem but doesn't solve it. The caller now suspects state exists but still doesn't know:

- Where the state lives
- How to reset it
- Whether it's safe to call concurrently
- How many calls before output stabilizes

Naming solves discovery. Structure solves usage:

```python
# Naming: caller suspects statefulness, still can't manage it
direction = get_next_direction_stateful(robot, sample)

# Structure: caller sees the state, knows to construct one per rollout
policy = MovingAverageDirection(window=20)
direction = policy.next(robot, sample)
```

Naming is sufficient only when the abstraction is **culturally universal** (`time.now`, `random.uniform`, `next(generator)`). For anything domain-specific, the interface must structurally reflect the obligations.

### What the caller needs to know (and nothing more)

"Reason about behavior" does not mean "know the implementation." The caller doesn't need to know local variables, helper call order, or algorithm internals. They need to know **what they're responsible for and what they can rely on** — the contract:

- **Substitutability:** Can I swap this for a different implementation and have my code still work? If not, whatever breaks was missing from the contract.
- **What can go wrong:** Can I call it twice? Zero times? From two threads? If any of these silently breaks, that's contract information the caller is missing.
- **What the caller must manage:** Must I initialize something before? Clean up after? Maintain call order? If yes, those obligations belong in the interface.
- **Boundary of consequences:** Does anything escape the function's scope — persistent state, side effects, resource obligations? If consequences land on the caller, the caller needs to know.

Local variables, internal branching, helper decomposition — the function's business. Statefulness, side effects, resource obligations — the caller's business, because the consequences land on them.

### Make state visible, not manipulable

When state is necessary, make it inspectable (Rule of Transparency) but control it through the right level of abstraction (Separation):

```python
class MovingAverageDirection:
    def __init__(self, window: int):
        self.history = deque(maxlen=window)  # public: caller can inspect

    def next(self, robot, sample) -> np.ndarray:
        raw = robot.next_direction_model(sample)
        self.history.append(raw)
        return np.mean(self.history, axis=0)
```

`history` is public for inspection — the caller can check `len(policy.history)` for debugging or test assertions. But the caller controls the object's lifecycle at the right abstraction level: need a reset? Construct a new one. That's "start fresh," not "reach in and clear the deque."

## When a Hardcoded Operation Is Fine

Not every internal operation is a policy decision. The test: **is there exactly one reasonable operation, or many?**

`square(x)` hardcodes multiplication. But no caller would ever want `square` to do something other than multiply x by itself. The operation *is* the function's identity. There's no choice point — no place where reasonable callers would diverge.

`build_decision_tree(dataset, maxdepth)` hardcodes a splitting criterion. But callers absolutely diverge here — Gini vs. entropy vs. custom domain-specific splits. The criterion is a choice point, and the function has chosen for the caller.

Similarly, `MovingAverageDirection.next` uses `np.mean` internally. If you're a moving average, averaging is your identity, not a choice point. But *which direction policy to use* (moving average vs. exponential smoothing vs. raw) is a choice point — that belongs to the caller.

The principle: **if the operation is the function's identity, hardcode it. If reasonable callers would diverge, parameterize it.**

### Identity applies to data types too, not just operations

The same test applies when a data structure declares its field types. A type declaration is a hardcoded choice — it forecloses alternatives. The question is whether the foreclosed alternatives are ones any reasonable consumer would want.

```python
# BAD — union type abdicates the decision
@dataclass
class LossInfo:
    deviation: np.ndarray | torch.Tensor
    predicted: np.ndarray | torch.Tensor
    gt: np.ndarray | torch.Tensor
```

The union says "I don't know what I am." Every consumer must inspect or defensively convert, because the type makes no promise. The format is shaped by the producer's convenience (torch was easy, so I left it as torch), not by a deliberate contract.

Ask: **would a reasonable consumer of `LossInfo` want torch tensors?** `LossInfo` is a post-inference summary — its consumers are plotting, thresholding, aggregation, reporting. These are all numpy operations. No consumer feeds a `LossInfo` back into a model or runs autograd on it. The struct lives entirely in post-torch-land. Torch tensors aren't a reasonable alternative here — they're a leftover from the production side.

```python
# GOOD — type declares what it is
@dataclass
class LossInfo:
    deviation: np.ndarray
    predicted: np.ndarray
    gt: np.ndarray
```

Now the constructor (wherever it lives) converts to numpy as part of "construct a valid instance." That's not dictating policy — it's fulfilling a type contract, the same way `square(x)` multiplying is fulfilling its identity.

**Contrast with a real choice point:**

```python
# BAD — this forecloses a choice callers actually make
@dataclass
class TreeNode:
    split_criterion: str = "gini"  # callers diverge: gini, entropy, custom
```

Callers genuinely want different splitting criteria. Hardcoding one narrows their options. The criterion is a choice point, not the struct's identity.

**The test for data types mirrors the test for operations:** if every reasonable consumer of this struct expects the same representation, the type declaration is identity. If consumers would genuinely diverge on representation, the type is a choice point that should be parameterized or left to the caller.

**Where the conversion goes:** once the type commits, the conversion belongs at construction time — not in a downstream consumer (that's patching after the fact), not in a lazy `__getattr__` (that's hiding mechanism in the data container), and not as a separate "fixup" step in the orchestrator (that's compensating for a contract violation). The producer constructs a valid instance, which means satisfying the declared type. That's mechanism, not policy.

## Side Effects and Shared Resources

A side effect is any observable change to state that outlives the function call and isn't the return value.

```python
# No side effect — everything is contained in the return
def add(a, b):
    return a + b

# Side effect — mutates something that persists after the call
def append_and_sum(lst, value):
    lst.append(value)  # lst is changed for the caller
    return sum(lst)
```

After `add` returns, nothing in the world has changed except the caller has a new value. After `append_and_sum` returns, `lst` is permanently different. Any other code holding a reference to `lst` sees the change.

A function has a side effect when it does any of:
- **Mutates an input:** `lst.append(value)`
- **Mutates state reachable through an input:** `robot.camera._sim_app.update()`
- **Mutates global state:** writing to a global variable, advancing a singleton
- **Performs I/O:** writing to disk, sending network packets, printing, rendering
- **Changes control flow outside itself:** raising an exception, calling `sys.exit()`

The key word is **observable.** Creating a local variable isn't a side effect. Mutating a local list you created isn't either. But mutating something the caller or other code can observe is.

"Inputs are read-only" is necessary but not sufficient for being side-effect-free. A function can leave all inputs untouched and still have side effects through globals or I/O. The full statement: **the function doesn't change anything observable except through its return value.**

### Side effects on shared resources belong to the resource owner

When a function that looks like a read secretly triggers writes to a shared resource, the interface is dishonest about both its effects and its cost.

```python
# BAD — get_left_rgb looks like a read, but advances the renderer
class FilteredCamera:
    def get_left_rgb(self):
        hide_prims(self._prims_to_hide)
        self._sim_app.update()   # side effect: advances shared renderer
        image = self._camera.get_left_rgb()
        show_prims(self._prims_to_hide)
        self._sim_app.update()   # side effect again
        return image
```

Problems:
- The renderer is a shared global resource. Every `sim_app.update()` affects every camera, every robot, every visual in the scene. A "read pixels" call mutates simulation state.
- Cost is hidden. One `get_left_rgb` costs two render passes. With stereo (left, right, depth) and 10 robots, that's 60 render passes per step — but the call site looks like a cheap read.
- Render ordering is split across layers. The simulation loop (`step_sim`) orchestrates render and physics steps, but hidden render steps also happen inside camera calls. Debugging frame ordering requires tracing into the camera.

The principle: **side effects on shared resources belong to whoever owns the resource's lifecycle.** The simulation loop owns render ordering. The camera consumes rendered frames. When the camera triggers renders, it's reaching across an abstraction boundary to operate a resource it doesn't own.

### Domain constraints aren't mechanism properties

"Robots shouldn't see each other" is a rule of a particular experiment, not a property of cameras. Baking it into `FilteredCamera` means:
- A different experiment where robots *should* see each other needs a different camera class
- The camera mechanism changes not because cameras changed, but because experimental rules changed

When the reason an operation exists is "the rules of this use case require it," it's policy. Embedding it in mechanism means the mechanism breaks when the rules change.

### When operations should move up a layer

When an operation that currently belongs to an individual instance starts requiring **coordination across instances**, that's the signal it belongs one layer up.

One robot hiding its peers and rendering — local, self-contained. Ten robots that must hide each other efficiently with minimal render passes — coordination problem, belongs on whatever orchestrates the batch.

The general principle: **operations local to one instance belong on the instance. Operations requiring coordination across instances belong on the orchestrator.**

### Ferrying dependencies through layers

When a variable passes through intermediate layers that don't use it, those layers acquire a dependency on something outside their concern:

```python
# sim_app passes through Robot just to reach FilteredCamera
class Robot:
    def __init__(self, ..., sim_app, ...):
        self.camera = FilteredCamera(camera, sim_app)
```

`Robot.__init__` takes `sim_app` not because Robot needs it, but because its camera does. If cameras stop needing `sim_app`, Robot's constructor must change — along with every call site that constructs a Robot.

This isn't always wrong. The alternative (constructing cameras outside robots and passing them in) adds orchestration code. The tradeoff is between coupling (ferry pattern) and complexity (external assembly). Apply the Rule of Economy: if you're not changing camera construction often, the simpler ferry might win.

## The Fix Process

1. **Identify the boundary** — where does the level of abstraction change? Internal helper calls are fine as-is.
2. **List every silent decision** — defaults, thresholds, algorithm choices, domain-specific branches.
3. **For each decision, ask:** does this belong to the function's domain, or to the caller's?
4. **Push caller decisions upward** — make them parameters, strategy objects, or configuration.
5. **Keep domain-intrinsic decisions** — these are the function doing its own job.
6. **Verify interface honesty** — does the signature reflect statefulness, side effects, and non-determinism?

Present the refactored code showing what changed and why at each layer.
