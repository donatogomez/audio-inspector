# Current working context

> **Contract — read before editing this file.**
>
> - **A single, overwritable snapshot** of the *current* working focus — **not a log.** Overwrite it in
>   place; never append history (git owns history).
> - **Intent only.** It records what is being worked on and *why* — the narrative no tool captures. It
>   is **never a source of truth** and must never contradict git, OpenSpec, or the ADRs. If it disagrees
>   with them, **they are right and this file is stale.**
> - **May be completely empty** (nothing under the template) when `main` is the latest and no thread is
>   open. **An empty `CURRENT.md` is the correct steady state**, not a gap to fill.
> - **Never put here:** task checklists (→ `openspec/changes/<name>/tasks.md`), branch/commit facts as
>   truth (→ git), decisions (→ `docs/adr/`), explanations (→ `docs/` / `OVERVIEW.md`), rules
>   (→ `CLAUDE.md`).
> - **To learn the real state**, do not trust this file — run `openspec list` and `git status` (see the
>   session protocol in `CLAUDE.md`).

---
**Open thread: `add-significant-bandwidth-measurement`.** Groups 1-5 are complete. The DSP is built and
it is **wired**: programme bandwidth is the sixth consumer of the one shared PCM read. Nothing is
visible yet — no UI, no export, no comparison, no findings — and that is deliberate.

**The accumulator reproduces group 2's targets exactly**, with no expected value changed and no
tolerance widened, and its shape was decided by arithmetic rather than taste: counters stratified by
each window's own peak, constant in duration at 7.57 MB for stereo at 192 kHz, because the budget
compares against a file peak that is unknown until the last chunk. Channels are measured apart, because
a downmix that sums can cancel opposite-polarity content and a measurement of where energy stops must
not be able to lose energy the file carries.

**The container came before the sixth payload, not after it.** `InspectionAnalyses` groups only what an
inspection derives from the samples; the report stays outside because it exists before the first chunk.
The compiler now carries what a test would otherwise have had to: the new field has no default, and the
six outcome types are all distinct, so a forgotten field and a swapped pair are both compile errors.

**The evidence group 5 needed is the evidence it has.** One read — one decoder, one decode call, one
sample read, with programme bandwidth `.available` rather than merely present. Isolation in both
directions, failure and cancellation without partial answers, shared equal to direct at four rates,
chunk independence through the composition. The bundle is atomic: a superseded operation's analyses are
dropped as a unit, asserted with six distinguishable values per operation rather than inferred from
fields that stayed `.loading`.

**Three things were believed and turned out to be wrong, and correcting them is most of what group 5
actually cost.** The numeric-extreme suite did not pin its own fix, because a quiet sine collapses
before the arithmetic it was meant to protect — only the linear DC and Nyquist bins carry a denormal
that far. What had been treated as one overflow is two, with two different protections. And the absence
that tasks predicted from a declining initialiser does not exist: no valid stream is ever declined, so
that is a property to state, not a branch to test.

**Cost and memory are measured, not assumed**: the sixth consumer costs what it costs alone, and adds no
overhead beyond itself; its footprint is 2.4 MB at 48 kHz and 8.7 MB at 192 kHz and does not grow with
duration. The numbers and the method are in ADR-0023 and in the change's 5.4.

**Next step: group 6, correctness against the fixtures.** It owns the property this whole design exists
for — the impulse control against **production** code, so a file silent but for one click reports no
wider a band than silence does. That is also the first of ADR-0023's two outstanding promotion
conditions; the second is human validation of a surface that does not exist yet, which group 7 builds.
ADR-0023 stays `Proposed`.

**Older threads, neither advanced here**: `add-static-spectrogram-visualization` (manual validation
battery deferred by product decision); `add-two-file-technical-comparison` (one accessibility criterion
open, blocked on the VoiceOver traversal gap shared with ADR-0015). The loudness debt recorded seven
snapshots ago is unchanged and still not a thread.

---
_Last touched: 2026-08-19. Overwrite freely; empty is fine._
