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
**Focus:** a new change, **`add-shared-pcm-read`** — contract only, nothing built.
`add-true-peak-measurement` is finished up to its accumulator and **blocked at group 6** by its own
stop rule; this change is what unblocks it. Nothing of the true-peak work is lost or redesigned.

**Why this change exists.** An inspection decodes the same file three times today, and would decode it
four times to add true peak. Measured against the real pipeline, one more read costs about a quarter of
a compressed inspection, and the existing three already spend most of a FLAC inspection decoding the
same bytes over and over. ADR-0016 rejected a shared pass at the time *and wrote the condition for
revisiting it* — "possible on top of this seam if measurement ever justifies one". The measurement now
exists, so the condition is met rather than argued around.

**The distinction the whole change rests on**, recorded in **ADR-0020** (`Proposed`): *independent
analyses* is the invariant ADR-0016 protects; *independent decodes* was the implementation it chose
while a decode looked free. One analysis must not fail, cancel or delay another — none of which
requires a decoder each.

**What the architecture spike settled, so it is not re-argued.** One read feeds the spectrogram, the
signal level metrics and true peak, **sequentially, in the same task**, composed in the app layer.
`AudioDecoding` and `PCMChunk` are audited and unchanged; no protocol is introduced for three known
consumers; concurrency is rejected on a measured ceiling (~0.28 s against three deliberately
non-`Sendable` accumulators and a synchronous callback that exists for a sandbox reason); PCM buffering
is rejected outright because it would make memory scale with duration. **The waveform keeps its own
read** — different port, different accumulator shape, and migrating it is a change of its own — so
reads go from three (or four) to two, not to one.

**The measured saving is exactly the redundant decodes removed, 97–100 % of them.** For the compressed
formats this product exists to examine, that pays for the entire true-peak feature; in Debug every
measured format ends up faster than today *with* true peak included. Uncompressed files gain almost
nothing, because their decode was already nearly free — stated rather than averaged away.

**The known cost, named in advance**: several existing tests assert the *mechanism* — they script two
decoders by call order and state that each operation gets its own decoder instance. That sentence stops
being true, and rewriting them to assert the *property* instead, with a negative control proving the
rewrite still discriminates, is real work and the main risk in this change.

**Next step:** group 2 of `add-shared-pcm-read` — the composition itself. After it merges,
`add-true-peak-measurement` resumes at its group 6, wiring true peak as a consumer of the shared read
with its model, accumulator, methodology and tests untouched.

**Other open threads** (see `openspec list` for their real task counts, not restated here):
`add-static-spectrogram-visualization` (manual validation battery deferred by product decision) and
`add-two-file-technical-comparison` (one accessibility criterion open, blocked on a known VoiceOver
traversal gap shared with ADR-0015). Neither was touched this session.

---
_Last touched: 2026-08-12. Overwrite freely; empty is fine._
