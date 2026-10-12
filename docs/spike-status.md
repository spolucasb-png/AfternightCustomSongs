# Spike status (pre-prototype)

- Phases 0–4 (discovery → preflight): engine mapped read-only; FNF chart
  engine with native SV; note pools, Conductor, song transport observed live.
- Test A: clean failure (`nil.KeyCount`, no strums on idle engine), zero residue.
- Test A2: `parseChart` OK (8 strums + 2 strumlines built); `addSectionsFromChart`
  rejected the wrapper (`nil.notes` — likely wants the song subtable); 4/4
  notes created by parse alone (timestamps/lanes unverified — sampler gating
  bug); pools + Conductor/SV restored, strums persist (rejoin required).
- Pending user approvals: rejoin, then Test B2 (sections-arg fix + per-stage
  sampling). No loader, no playback, no scores.
