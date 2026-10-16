# Bad and good passages

All three come from one session that explained an ILP fine-tuning loss (imitation + BPTT +
advantage-weighted regression). The first two answer the same request, so they can be
compared directly.

- [Bad: glossary up front](#bad-glossary-up-front)
- [Good: one symbol per step, in invention order](#good-one-symbol-per-step-in-invention-order)
- [Good: reading order for a long expression](#good-reading-order-for-a-long-expression)

## Bad: glossary up front

From the first attempt at "explain the total loss". It opens with this before saying what is
being optimized (trimmed):

```markdown
Every symbol is defined once in section 1 and used by name after that.

## 1. Notation

Indices and shapes:

$$
\begin{array}{ll}
b = 1,\dots,B & \text{scene in the batch} \\
s = 1,\dots,N_s & \text{trajectory sample} \\
n = 1,\dots,N_t & \text{diffusion step} \\
t = 1,\dots,T & \text{future timestep}
\end{array}
$$

Per-element losses and their weights:

$$
\begin{array}{lll}
L_k[b,s,n,t] & \texttt{loss\_dict[k]} & \text{per-element loss } k \\
w_k & \texttt{loss\_weights[k]} & w_{\text{flow}}=1.0,\; w_{\text{xy}}=0.1,\;\dots \\
\lambda_{\text{IL}} & \texttt{il\_loss\_weight} & 0.12 \\
\dots
\end{array}
$$

Masks: p_b, v_b, tau_{b,t}, d_{b,s,n} ...
Finetuning and AWR: R_r, rho_r, A, c_a, beta_a, K_a, A_a[b], sigma_{b,t}, theta, m, ...
```

Why it fails:

- **About 25 symbols before a single idea.** None of them means anything yet, because the
  reader doesn't know what problem they serve.
- **Grouped by type** (indices, masks, weights), not by the step of the story that needs them.
  Two of the masks are defined in section 1 but first matter in sections 3 and 7.
- **Ordered like the code** (`forward_loss_impl` top to bottom), not like the ideas. Imitation,
  fine-tuning and AWR are all present, but the story is never told.

## Good: one symbol per step, in invention order

The rewrite, after the user asked for notation "in the natural order it was devised". The
user's verdict was "this is looking great so far".

```markdown
## Step 1. Imitation: copy the human driver

The first goal is behaviour cloning: given a scene, produce the trajectory the human drove.
A scene and the human's trajectory are written as a pair:

$$
(s, a), \qquad s = \text{scene (map, tracks, ego history)}, \quad a = \text{logged GT trajectory}
$$

The planner is a policy with parameters theta. Behaviour cloning makes the human's
trajectory as likely as possible under it, averaged over logged scenes:

$$
\max_{\theta}\; \mathbb{E}_{(s,a) \sim \mathcal{D}} \big[ \log \pi_\theta(a \mid s) \big]
$$

## Step 2. The ILP is a flow model, so the likelihood becomes a regression loss

The ILP generates trajectories by denoising, and the log-likelihood of a flow model is
expensive to compute. The standard replacement is the flow-matching loss ...

$$
-\log \pi_\theta(a \mid s) \;\;\leadsto\;\; \ell_\theta(s, a)
$$

Training works on a batch of scenes, so index them:

$$
b = 1, \dots, B, \qquad \ell_b = \ell_\theta(s_b, a_b)
$$

Not every scene is usable, and some interaction scenes are deliberately counted more, so
each scene carries a weight (`weighted_valid_mask`):

$$
p_b \ge 0
$$

The imitation objective for one batch is the weighted average:

$$
\mathcal{L}_{\text{flow}} = \frac{\sum_b p_b\, \ell_b}{\sum_b p_b}
$$
```

Why it works:

- **Each symbol arrives with its reason:** batches bring the scene index, unusable scenes bring
  the scene weight, the expensive likelihood brings the regression loss.
- **Each step fixes a problem with the one before:** likelihood → flow loss → batches → weights.

Not perfect: the Step 1 objective block introduces π_θ, θ and the dataset 𝒟 together, and θ
appears in prose as "theta". The step that follows introduces every other imitation term at
once (a weight and a loss for each remaining k). Under this skill's rules each of these would
come in its own step, or at least with its own plain-words sentence first.

## Good: reading order for a long expression

From the effective-sample-size section of a note on choosing an AWR temperature. The user said
"you do a pretty good job here" and asked for the same style elsewhere.

```markdown
**Why it matters.** Each gated scene pulls on the parameters in proportion to its weight:

$$
\nabla_\theta\, \mathcal{L}_{\text{AWR}}^{(\text{siren})} \propto \sum_b
\underbrace{u_b}_{\text{(2) how hard}}\;
\underbrace{\nabla_\theta\, \bar{\ell}_b}_{\text{(1) direction from scene } b}
$$

Read (1) first: each scene asks the model to imitate its GT. Then (2): how hard each request
is weighted.
```

Why it works: **the prose gives the reading order,** and it doesn't have to be left to right:
(1) sits to the right of (2).
