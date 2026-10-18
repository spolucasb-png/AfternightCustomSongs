# Handoff (AfternightCustomSongs)

## Current state (2026-10-17/18 — session 29; hold layering + 5K centre lane, v2.3.0)

- USER REPORTS (live plays): hold bodies drew over the PRESSED receptor
  ("hold bodies when holded stay above the pressed receptor"); the 5K
  centre ("space") lane did not wear the applied skin; Etterna skin scale
  off on some lanes; results cards showed the internal chart id.
- RESULTS TITLE (`src/afn_rayfield.lua`): the stats `Results.create` wrap
  now swaps in `c.playTitle` / `c.playDiff` — menu-style labels, no
  `afn_`/`_` leakage. LIVE-VERIFIED (user: "fixed and better now").
- SKIN SPRITE ENV: the `skin-sprite-env-missing` abort fixed via the
  engine's own module-require route. LIVE-VERIFIED ("works fine now").
- SKIN SCALE (`converters/skins2afn.py`, `tests/test_skins2afn.py`):
  per-direction normalization — NOTE_REF = 154, ratio deadband 0.8-1.25
  -> 1.0, clamp 0.5-12, written as per-dir `sizeMult` in the manifest;
  applied by `buildSkinFolder`. LIVE-VERIFIED on covered lanes ("works
  perfectly").
- 5K CENTRE LANE: Ambie is a 4K pack (no `Square` dir), so the centre
  column borrowed the game's own space art. Preference is now pack
  `Square` -> pack `Up` files verbatim (`sq=square=packUp`; mirrors the
  engine's own Square->Up chain) -> stock module -> engine fallback(Up).
  LIVE-VERIFIED: "now the middle note skin works!".
- HOLD LAYERING root cause (live `Zdiag` + client decompile): receptor
  sprites carry no zindex of their own (baseline max Obj.ZIndex 5); hold
  pieces are created in the chart parse as
  `getSetting(New_14.side, "LowerZIndexSustains") and 2 or 6` (decompile
  line 7549). The option SET true pre-load reads back FALSE by play time
  (the engine resets it — verified live: setter "lowered", `Rfalse` right
  after load), so pieces parsed at 6, tied with the receptors (6 vs 6
  after our raise), and the tie is broken by sibling order -> the later
  child (body) draws over the pressed receptor (both under one "Game"
  root, ZIndexBehavior.Sibling).
- FIX (v2.3.0): right after `loadSong` (all notes still pooled, nothing
  spawned yet) a sweep pins EVERY player-side hold piece to `zindex 2`
  directly (`sust2=<count>/R<flag>` in the report; live `sust2=188/Rfalse`).
  The old option setter stays as a record (`sustz=`). Step 8.8 raises the
  receptor sprites to 6 (top safe value: tap notes at 7, splashes at 8)
  via a field write -> direct Obj write -> `ForceUpdate` chain, prints
  one `Zdiag` line (strum/sus Obj ranges, sprite field, held count,
  render-tree parent#siblingidx@ZIndexBehavior, flag/set/z2) and teardown
  restores the fields (`step "strum-z"`).
- LIVE EVIDENCE (user pastes): `... clip=R=true | sustz=lowered | ...
  z=base5 | sust2=188/Rfalse | sq=square=packUp | note0=R/0@1307` and
  `Zdiag: a3 strum=6..6 sus=nil..nil/fnil n0/h0
  tree=Game#16@Enum.ZIndexBehavior.Sibling|? flag=false set=lowered
  z2=188/Rfalse` (early samples had no hold piece live yet — n0; the win
  is the user's visual confirmation).
- VERSION: bumped 2.2.2 -> 2.3.0 at the user's request for this release
  (all of the above ships together; 2.2.2 was the working number). All 11
  test suites green. DEPLOYED: Madium workspace root `afn_rayfield.lua` —
  sha256 1A53575BD8821D0986F7212B2C740A3214FC21624C53D729B8E563B3AF603C59,
  193371 bytes; `loadstring` compile OK (not executed).
- ROADMAP.md now also has section 23 (this cycle; sections 20-22 =
  v2.2.0 / v2.2.1 / content wave).
- Commit status: session 29 committed as 7da4f28 (pushed; user-approved
  "change the version to 2.3.0 and commit please :3", v2.3.0
  live-verified). Untracked wave tooling/reports (`converters/batch_port.py`,
  `docs/megapack_scan.csv`, `docs/wave1_picks.txt`,
  `docs/wave1_staged.csv`, `docs/osu_families_staged.csv`) and scratch
  files (`_extract_afn.txt`, `_last30.txt`, `.cursor/`) are deliberately
  left untracked as before.

## Current state (2026-10-17 — session 28; HUD shows menu title + real difficulty, v2.2.1)

- USER REPORT (screenshots): the game's Now Playing card read
  `afn_daisan_4k_sc` / "By: daisan" and the time bar read
  `afn_daisan_4k_sc (Easy)`. Wanted: the nicer name the song-select menu
  shows, and the difficulty that was actually selected.
- ROOT CAUSE (client decompile + live read-only decompile on PID 3264):
  * `loadSong` builds `songData`: `SongName = Song:GetAttribute("DisplayName")
    or Song.Name`, `DisplayDiffName = Translator.GetOr("Difficulties_" ..
    Chart.Name, Chart.Name)`. Now Playing (`showNowPlaying`, `SongLabel`),
    the time bar (`TimeBar.Song`, `SetInformation`), the old-style info
    label, Discord RPC, window title and the results clip name all read
    those two fields.
  * We were setting `songInst.Name = <chart id>` (no attribute) and naming
    the chart ModuleScript the fixed `DEFAULT_DIFF` ("Easy"). That is the
    whole bug; nothing else in the HUD path is ours.
  * "By: daisan" comes from the chart's own `song.artist` (`t_12.artist`),
    already correct, untouched.
- FIX (`src/afn_rayfield.lua`, v2.2.1):
  * new `currentEntry` (set in BOTH selection paths: `selectMenuEntry` and
    `selectEntry`) remembers the menu entry behind `currentChart`.
  * new `playLabels(chart, path)` (above `playChart`, forward-only locals):
    title = song group display (= chart `song.title`, else the id-derived
    pretty name, same as the menu row), difficulty = `entry.diffLabel`
    (same string as the menu's difficulty button). Fallbacks when no menu
    entry matches the loaded path: chart `song.title` / `song.difficulty`,
    then the raw id / "Custom".
  * `songInst:SetAttribute("DisplayName", playTitle)`; `songInst.Name` stays
    the internal id because it keys our registry entry
    (`Songs[rep.songName]`) and `SongFile.Name` is what results/metadata
    lookups use. `chartMod.Name = playDiff` instead of `DEFAULT_DIFF`.
  * loading pre-flip banner text and the Rayfield "Loading" toast use the
    same labels; `rep.title` / `rep.diff` now carry them in the report.
  * `DEFAULT_DIFF` is still defined but no longer used for the chart name.
- WHY RENAMING THE CHART MODULE IS SAFE (checked, not assumed): `parseChart`
  ignores its difficulty argument; `fixChart(chart, Chart.Name)` forwards the
  name to the format fixers, and only `BaseGame` reads it, behind a
  `generatedBy`/`version` guard our charts never have (ModernPsych,
  OffsetFixing, CameraFixing ignore it). `songData.SongInfo` looks up
  `Songs[Song.Name.."-"..Difficulty]` then falls back to `Songs[Song.Name]`.
  `Translator.GetOr(key, default)` is a plain table lookup returning the
  default when the key is missing, so `4K SC` shows as `4K SC`. (A label that
  equals a localized difficulty key, e.g. "Easy", would show its localized
  text: harmless.)
- DAISAN DATA: `afn_daisan_4k_sc` has `title="-+"`, `artist="daisan"`,
  `difficulty="4K SC"`. The six daisan files share title `-+`, so they are one
  song group with six difficulty buttons. If two charts of a group share a
  difficulty label the menu appends "(2)" and the HUD shows that too.
- VERIFIED THIS SESSION: tests/test_afn_rayfield_local_only.py green incl. 2
  new checks (HUD labels wiring; `playLabels`/`currentEntry` above first
  use); whole file compiles in the client (`loadstring` of the deployed
  copy, negative control rejected); deployed to the Madium workspace root
  `afn_rayfield.lua` (hash 325E8915 -> 1E5640BE, 176643 bytes, VERSION 2.2.1).
- LIVE-VERIFIED (user): "the live checks out ... everything works!" — the
  Now Playing card and time bar show the menu title + selected difficulty
  ("-+" / "4K SC"), console clean, and the wave-1 library plays on with no
  regressions.
- NOT CHANGED: legacy single-chart players (`src/player_core.lua`,
  `player_windui.lua`, `loader_windui.lua`) still name the song by id and
  the chart "Easy"; they predate the song-grouped menu and were left alone.
  The game's own second `enterLoadingState` call inside `loadSong` uses
  `Song.Name` (the id), so the loading banner may still show the id; that
  text was not checked live.
- ROADMAP.md now has sections 20 (v2.2.0 stats/sorting), 21 (v2.2.1 HUD
  labels) and 22 (content wave: batch porter + osu diff families).
- Commit status: session 28 committed as 6b354db (pushed; user-approved
  "commit + push v2.2.1 only"). The wave-1 tooling/reports
  (`converters/batch_port.py`, `docs/megapack_scan.csv`,
  `docs/wave1_picks.txt`, `docs/wave1_staged.csv`,
  `docs/osu_families_staged.csv`) were deliberately left untracked per the
  user call; scratch files (`_extract_afn.txt`, `_last30.txt`, `.cursor/`)
  untouched.

## Current state (2026-10-17 — session 27; local play stats + sorting, v2.2.0)

- FEATURE: local play stats. Own file `Stats.json` in the workspace folder
  (the game's saved data is never touched; the "no saved-data writes" test
  guard still holds). Keyed by chart file name: plays started (`n`), finishes
  (`f`), last/best accuracy + score, best combo, cleared flag, last finish
  time, plus an 80-entry Recent list (newest first). `noteRecent` runs at
  play start (so a quit still counts as a play and shows in Recent);
  `recordResult` runs when our own endSong raises the local results screen.
- CAPTURE: `installStatsHook(c)` wraps the engine's `Results.create`
  (`c.t1.Results`) for the length of OUR play only: it copies
  score/accuracy/topCombo/cleared/keyCount into `c.lastStats` and forwards
  the call unchanged. `restoreStatsHook` puts the original back in teardown
  (`step("stats-hook")`). This is the ONE new game-table write in v2.2.0
  (a rawset on `Results.create`); the user picked "Recently Played + stats"
  from the next-feature menu, but it is a new boundary touch, so keep it in
  mind before adding anything similar.
- PANEL: the in-menu selected-song panel gets two lines once a chart has a
  finish: Plays/Finishes, and Best/Last accuracy (+ best score).
- SORT: `settings.sortMode` = "az" | "recent" | "favs" (default az,
  validated on load so a hand-edited Settings.json can't break it).
  * In-menu tab: left side of the "Custom Charts" header has a Sort button;
    click cycles A-Z -> Recent -> Favourites, saves, and re-sorts the live
    rows through LayoutOrder (nothing rebuilt). `buildHeaderRow` now takes
    the `ui` table (stores `ui.sortBtn`, reads `ui.groups`).
  * Rayfield: "Sort songs" dropdown under Difficulty; picking a mode saves
    and refreshes the Chart list.
  * Recent = a song's best (earliest) hit in `stats.recent` across its chart
    files; never-played songs trail in A-Z. Favourites = groups with a
    starred chart first, then A-Z.
- LIVE-VERIFIED (PID 3264, user's private solo server, deployed hash
  325E8915): boot gen=1 v2.2.0, console clean. Rayfield "Sort songs" exists;
  clicking its options changes the label and persists `sortMode`. A real
  autoplay play of Colorful (TV Size) Beginner 8 (473 notes, ~61 s) went
  Idle -> Playing -> "Finished" with the results screen up, and wrote
  `Stats.json`: n=1 f=1, acc 100, score 189200, bestCombo 473, cleared.
  Recent sort then put Colorful first, rest A-Z. Stop was clean
  (stage=stopped, no warnings). `sortMode` restored to az afterwards.
- NOT LIVE-TESTED: the in-menu header Sort button (needs the game's own song
  select open); Favourites ordering (Settings.json has no favourites, so it
  is indistinguishable from A-Z right now); the hook restore is by
  construction only (no direct probe of `Results.create` after Stop);
  non-autoplay scoring (autoplay was on, so the stored 100% / 189200 is a
  botplay number).
- HEADS-UP: that test play left a real entry in the workspace `Stats.json`
  (botplay 100%). Delete `AfternightCustomSongs/Stats.json` in the Madium
  workspace to reset stats; the file is recreated on the next play.
- Tests: +5 checks in `tests/test_afn_rayfield_local_only.py` (own Stats.json
  only; Results.create wrap + restore; sort modes in both UIs; panel lines;
  definition order). Full suite green, and the whole file passes a Luau
  `loadstring` compile (luau 0.742; negative control confirmed it fails on
  bad syntax).
- NEXT (user picked three from the menu: stats [done], Polish round, More
  maps): More maps = wave-1 staging is on disk but uncommitted
  (`converters/batch_port.py`, `docs/wave1_*.csv`, `docs/megapack_scan.csv`,
  `docs/osu_families_staged.csv`, `_extract_afn.txt`, `_last30.txt`,
  `.cursor/` are all still untracked; deliberately NOT in the v2.2.0 commit).
  Polish round = CI workflow is stale (misses half the suite), README
  refresh, wide-lane skin art. ROADMAP.md has no v2.2.0 entry yet.
- Commit status: session 27 committed locally (v2.2.0; see `git log`), not
  pushed.

## Current state (2026-10-17 — session 26; song covers, v2.1.0)

- FEATURE: per-song cover art. Staged as `Covers/<chart-stem>.<png|jpg|jpeg>`
  in the workspace folder (same stem as the chart/audio). Art extracted from
  the source packs: Quaver `.qp` (BackgroundFile reference, else the largest
  image), osu `.osz` ([Events] 0,0,"file" reference, else the largest
  non-storyboard image), Etterna folders (wenkz.png / BG.png). All 17 staged
  charts covered (9 png / 8 jpg). Staging collision fixed: halloween + SOUND
  ARCHITECT both ship a `bg.jpg` — the temp-extract name clashed, halloween
  re-extracted (1.40 MB vs SA's 0.82 MB).
- PLAYER: `COVER_DIR`/`COVER_EXTS`, `listCoverFiles()`, `automatchCover(entry)`
  (stem first, then any sibling chart stem of the same song group — one art
  can serve every difficulty). Applied in two native spots, both probed live
  first:
  * in-menu selected panel: `SelectedSong.Icon` (direct child, 0.287×0.919 of
    the panel; default img rbxassetid://87401558648287, ScaleType Fit) ->
    cover with `ScaleType.Crop`, transparency 0; charts without a cover get
    the default image AND default ScaleType back.
  * menu rows: the row template's `BG` ImageLabel (full-size, accent gradient
    on top) -> cover with `ScaleType.Crop`; cover rows keep bgBase >= 0.35 so
    the name reads while unselected, full art when selected.
- LIVE: user verdict after opening the tab: "nice! looks so well". Mod boots
  v2.1.0 clean on the new client (the old game session had restarted; the
  mod was re-run there — boot gen=1, no console errors).
- Tests: +2 boundary checks (covers staged per stem; covers feed the icon +
  row BG with default restore). Full suite green.
- Commit status: session 26 committed as a8e6b46 (pushed; user-approved:
  "nice! looks so well").

## Current state (2026-10-17 — session 25; spawn-window SOLVER hook, v2.0.2)

- USER FOLLOW-UP: "it fixed some maps, day by day included, still spawning
  midway in the stutter sections; hold bodies look weird in sv maps; other
  sv maps work fine". RESIDUAL CAUSE: the clamp hook yields a FIXED window
  (1750/(base*min(|m|,1))) — where a window's average SV is below 1 (day
  by day's stop runs), notes still land under the line (sim: 0.2% f<0.5,
  worst f=0.42 near the 68-70s stutters).
- FIX — TWO HOOK MODES, chosen per chart by the existing flingy test
  (|m|>10 counts):
  * SOLVER (sane-SV charts): per call, walk the SV table backwards from
    the note time until the engine's SIGNED distance budget is consumed
    (budget = 1750 engine units = noteSpawnTime 1.75s; motion scales by
    v199=1.44*mult in both mapVelocityChanges and getPosFromTimeSV, same
    scale), then return 1750/W so the gate window equals W EXACTLY. The
    table is re-read from the reader's upvalue per call (the engine
    reassigns it per chart load; a captured reference would be stale).
    Walk capped at 12s/4096 steps; incomplete -> clamp fallback.
    LIVE-VALIDATED against the engine's own table: 16 sample times (incl.
    every stutter hot spot 68.7-86.4s) all solved with forward-integral
    distance 1750.00, worst error 0.000. Python sim: all 2410 day-by-day
    notes + every other sane chart solve (0 fallbacks).
  * CLAMP (flingy charts, |m|>10): unchanged — the proven ballin'/bozo
    fixed-time behaviour.
  Play line: `tame=solved(<svN>sv)` for solver charts, `hooked(N@x1)`
  for flingy ones.
- HOLD BODIES ("weird in sv maps"): engine-side investigation — hold
  pieces are integrated-correct (each piece renders
  getSusLength(pos(pieceStart), pos(pieceEnd)) = delta/44 * multSpeed;
  the sustain recompute is TRIGGERED by getSVFromTime but the geometry
  never consumes it, so the hook cannot change bodies). Day by day has
  only 21 holds; several span its stop runs (420 entries with |SV|<=0.05,
  ~20-40ms wide) — the bodies compress/expand exactly like the notes do
  (map-intended, and osu renders them the same way). Other SV maps
  (smooth ramps / net-zero teleports) have no stops, so nothing looks
  off there. Remedies OFFERED, unapplied: the existing "Ignore SV" (flat)
  toggle, or a new play-copy SV-floor option ("soften stops") if wanted.
- v2.0.2 deployed, re-executed gen=7; boundary +1 check (solver) HELD;
  suites green; compile OK; locals 164/200.
- NEXT LIVE: replay Day by day (`tame=solved(2353sv)` in the line) —
  spawns should sit exactly on the line through the stutters. Hold-body
  look stays as-is pending the user's call on stop-softening.
- Commit status: sessions 24+25 committed as 33ed318 (pushed,
  user-approved: "u got it right").

## Current state (2026-10-17 — session 24; day-by-day SV spawn fix, v2.0.1)

- USER REPORT: Day by day "notes spawn mid way instead of be THERE with
  the sv ... make sure it doesnt mess up with other songs".
  ROOT CAUSE (engine-model sim in exact units): the RAW spawn gate
  (L = 1750 / (v199 * |mult|), v199 = 1.44 from getSVFromTime's upvalue;
  mapVelocityChanges/getPosFromTimeSV both scale by v199) mispositions
  notes whenever the SV varies inside the window. Day by day's
  stop/stutter wobble (0.01/2.0 pairs, 6.0 spikes; 2353 SV entries)
  spawned 15.3% of notes below HALF the spawn line (2.2% deep) under the
  raw gate — and the session-20 spawn HOOK never installed because its
  trigger required |SV| > 10 while day by day's max is exactly 10.00
  (missed by 0.01).
- FIX: the hook now installs whenever the chart HAS any SV map
  (`svN > 0`; flat/off unchanged). The clamp is a passthrough for
  |mult| <= 1 and was already the thing that fixes ballin'/bozo. SIM
  across the full staged set (exact engine formulas, f = spawn-distance /
  line): day by day 15.3% -> 0.2% bad; halloween 6.7% -> 0%; ballin
  0.6%/bozo 2.7% unchanged (already hooked); EVERY other staged chart
  0% -> 0% (the hook is invisible-or-better there: clamped notes spawn
  higher/offscreen only). The report count is derived from the installed
  lim (day by day: 1013 entries |mult| > 1 -> `tame=hooked(1013@x1)`);
  a failed install on a non-extreme map reports `raw(hook:...)`.
- v2.0.1 deployed (5270CEB9...), re-executed as gen=6; live-verified
  read-only that the hook's locator + upvalues still land (SV table 2353
  entries, base 1.44); boundary +1 check (wider hook trigger) HELD;
  suites green; compile OK; locals 162/200.
- NEXT LIVE (user): replay Day by day — the Play line must read
  `tame=hooked(...@x1)`; notes should approach from the spawn line
  through the stutter sections. Other charts: unchanged by design (sim
  table above).
- Commit status: fixed forward in session 25 (window solver + install
  for any SV map); both sessions committed as 33ed318.

## Current state (2026-10-17 — session 23; multi-key 5-10K support, native wide charts staged)

- USER ASK: multi-keys — "5k, 6k and 7k on osu and quaver". ENGINE RECON
  (decompile + read-only live): the engine fully supports it — ManiaData
  dirs[N]/angles[N]/size[N] exist for 1-21 keys per side (5K center =
  "Square", 6K/7K add Left2/Right2), keybinds per count live in the
  player's own saved data ('5'..'7' present: 6K = SDFJKL, 7K = SDF+Space+JKL),
  per-lane art resolves by dir name with in-set strip fallback (getSetBelow
  "Left2" -> "Left"), and createNote maps player rows as lanes
  [keyCount, keyCount+playerKeyCount) with column = (lane-keyCount) %
  playerKeyCount (client 7361-7386). Note palette has proper Square/Left2/
  Right2 colors.
- CONVERTERS: afn_common `NATIVE_MAX = 10` — sources up to 10K now emit
  NATIVE (build_wrapper lanes=N -> keyCount=playerKeyCount=N; build_rows
  places rows at lanes N..2N-1); >10K still folds to 4 lanes with the loud
  warning. `build_rows`/`build_wrapper`/`report_chart` take `lanes`.
  osu + qua suites updated (native-7K tests, >10K fold tests); eterna
  unchanged (dance-single is 4 columns). Suites: osu 10/10, qua 10/10,
  eterna 8/8.
- PLAYER: readChart accepts keyCount-driven lane ranges and stores
  _keyCount/_playerKeyCount; chartInfo + the menu stats show the real key
  count. CUSTOM SKINS APPLY TO WIDE CHARTS (live report "skin doesnt
  apply" fixed): re-reading getSetBelow showed the full dir fallback chain
  (Square -> rUp2 -> rUp -> Up2 -> Up; Left2 -> Left; ...), so 4-dir packs
  cover every lane EXCEPT the centre; the skin folder now additionally
  carries a Square module — a pack-provided Square wins, else the game's
  own Square (the "Space" art) is borrowed: its XML is requireable from
  the executor (live-proven, 3140 B, round-trips through loadstring) and
  its Image+Color attrs are copied into our module. Play line
  `skin=custom:<name>(wide:NK)`, subs carry
  `skin-square=stock|pack|fallback(Up)`. Boundary +2 checks (wide lane
  bounds, stock-Square borrow). Full suite green; whole file compiles in
  the client; locals 162/200. VERSION 1.2.0 -> 2.0.0 (song grouping +
  multi-key = major).
- STAGED (workspace now 17 charts + 17 audio; 13 songs; 5 wide charts):
  * RESTAGED NATIVE: Dragon Blade [6K Blade] (1558 rows, lanes 6-11; was
    folded to 4K) and Blue Zenith [JINDIMENSIONS] 7K (7270 rows, lanes
    7-13 — ALL 1531 fold-dropped notes restored).
  * NEW: daisan -+ [5K NM] (349 rows) + [5K SC] (1142) + Ievan Polkka
    [7K NSV] (985), stem-named mp3 copies staged. In the UI -+ now shows
    three difficulty buttons (4K SC / 5K NM / 5K SC) and Ievan two
    (4K NSV / 7K NSV).
- QUAVER: Keys5-Keys10 convert natively now; the local .qp packs are all
  Keys4, so nothing new was staged from them (drop a Keys5+ pack and it
  just works).
- Deployed (35429FA0...); re-executed as gen=4; read-only verified: 17
  charts / 5 wide / 13 songs with the expected difficulty groups.
- NEXT LIVE (user): replay a wide chart with the custom skin selected — -+
  [5K NM] (5 lanes), Dragon [6K Blade] (6 lanes), Zenith [JINDIMENSIONS]
  (7 lanes): the SKIN now applies (Play line `skin=custom:...(wide:NK)`,
  subs `skin-square=stock`); the centre key (Space in 7K) shows the stock
  Square art, 6K/7K extra lanes reuse the pack's Left/Right via the
  engine's fallback. The wide layouts/keybinds themselves were already
  user-verified ("works!").

## Current state (2026-10-17 — session 22; song grouping + difficulty buttons in BOTH UIs)

- USER ASK (live): "put difficulties in the select song ui, not just rows of
  individual song difficulties" — for both UIs (custom = Rayfield window,
  in-game = the SongSelect tab). Charts now group per SONG; difficulties
  get their own native-styled buttons.
- METADATA (converter-level, durable): all three map converters emit
  `song.title` / `song.artist` / `song.difficulty` via the new
  `afn_common.build_wrapper(meta=...)` (ids and note emission untouched;
  the engine ignores the extra keys). Labels per source: osu Version, qua
  DifficultyName (unquoted), eterna "<Diff> <meter>". Suites: osu 10/10,
  qua 9/9 (new quoted-diff case), eterna 8/8.
- ALL 14 STAGED CHARTS RECONVERTED with metadata (restage script + diff
  report in `Temp/opencode/restage22/`; 12/14 byte-identical notes + meta).
  SA and Ievan came out under NEW artist-in-id ids (session-20 standard):
  `afn_kyutatsuki_sound_architect_harmonic_bliss` and
  `afn_otomania_ievan_polkka_4k_nsv` — notes/bpmChanges identical, SV =
  anchor + old (the in-memory t0 anchor is now materialized in the file),
  mp3s copied to the new stems, old chart+mp3 files deleted. All other
  files kept their ids; note data verified equal before replacing.
- GROUPING: `groupEntries` (key = title+artist; no metadata = own song) =>
  14 charts = 13 songs; ball hard merges its two diffs ([SV] ballin' /
  Skrubble's Ball). Duplicate difficulty labels get (2)/(3) counters.
- IN-GAME UI (menu tab): rows = songs (SongName = title; week line = the
  selected difficulty's stats); the Difficulties panel rebuilds one native
  button per diff (`renderDiffButtons`; the selected button keeps a full
  stroke); diff click = select + preview (session-19 behaviour, now per
  difficulty); row click = select the song (first diff); the star is now
  song-level (sets every file of the group in settings.favorites); search
  matches title/artist/difficulty; auto-pick keeps the prior chart else
  the first song's first diff.
- CUSTOM UI (Rayfield): Chart dropdown = songs; NEW Difficulty dropdown
  (options per selected song, recursion-guarded Set), either pick loads
  the chart.
- VERIFIED STATIC: rayfield boundary +3 checks (grouping, diff buttons,
  diff dropdown) HELD; full suite green; the whole file loadstring-
  compiles in the live client (150,342 bytes; top-level locals 160/200).
  Read-only live (PID 3380): 14 charts group to 13 songs, no missing
  metadata; the Rayfield window shows Chart + Difficulty + Refresh.
  Deployed (1F141BDB...); re-executed as gen=3.
- SAME-DAY: user confirmed the etterna OFFSET fix in play ("now is in
  sync"); the console line shows note0@1251.316 for sayonara +
  `synth_chunks=single` (the new Play-line field works; ballin' already
  carried `tame=hooked(4472@x1)`).
- Commit status: repo HEAD ee8f5df; uncommitted since session 21: docs,
  converters (offset fix + metadata), tests, src/afn_rayfield.lua
  (synth_chunks line + grouping UI). Staging is outside git.
- NEXT LIVE (user): in the song-select Custom tab verify rows = songs, the
  ball hard pair shows 2 difficulty buttons, a difficulty click previews,
  and Play plays the selected difficulty; then the Rayfield
  Chart→Difficulty flow. Commit on approval.

## Current state (2026-10-17 — session 21; Etterna ports staged + #OFFSET sign FIXED, porting queue COMPLETE)

- ETERNA PORT DONE (staged live, UNCOMMITTED): `afn_insert_coin_hard_6`
  (535 rows / 388 holds, 178 BPM, 2 BPM changes, 0 SV) and
  `afn_sayonara_cruel_world_reworked_hard_2` (803/232, 95 BPM, 6 changes,
  0 SV), converted with `converters/eterna_to_afn.py` and staged into
  workspace Charts/; mp3s staged into
  Audio/ under the exact chart stems (`afn_insert_coin_hard_6.mp3`,
  `afn_sayonara_cruel_world_reworked_hard_2.mp3`) — the automatch rule is
  stem-first, so the converters' `audio.mp3` hint alone would not match.
- PICK CONFIRMED BY FINGERPRINT: "sayonara" = Sayonara CRUEL WORLD
  (tailsdk) — its 803 rows / 232 holds match the session-16 verified
  numbers exactly; Sayonara Heaven (LovelySerenade) is a different map
  (1061/205) and was NOT staged. Insert Coin matched too (535/388).
- The session-20 porting queue is COMPLETE (qua 4 + osu 6 staged in
  session 20, etterna 2 here). Workspace now 14 charts + 14 audio;
  staged copies hash-verified byte-identical to converter output.
- LIVE ROUND 1 (user, same client PID 3380, console captured): ballin'
  played to results — Play line `tame=hooked(4472@x1)` => the session-20
  SPAWN HOOK is live-verified; the 420KB chunked-synth chart loaded and
  ran (chunk mechanism worked). User: "ball hard works so well". NOTE:
  `rep.synth_chunks` was carried but NOT printed by summarizeReport — the
  Play line now includes `synth_chunks=` (src edited, 1 line, deployed;
  needs a re-execute to show in the running client).
- USER BUG REPORT: "audio is delayed in etterna charts" (insert_coin +
  sayonara; console seq 14/19 show note0@1458.427/3801.316 = the old
  values). ROOT CAUSE = converter bug, #OFFSET applied with the WRONG
  SIGN: StepMania maps beat 0 to second = -#OFFSET (initial timing line
  ends at end_second = -m_fBeat0OffsetInSeconds; verified in upstream
  TimingData.cpp + TimingData.h field order), so every timestamp must be
  integral(beat) - OFFSET. The old +offset put charts 2x OFFSET late:
  insert_coin 1400 ms, sayonara 2550 ms. BOUNDARY PROOF: under the old
  sign insert_coin's last note fell at 39667.9 ms vs a 38452 ms mp3 (past
  the song end); flipped it lands 38267.9 ms (184 ms before the end).
- FIX (this session): eterna_to_afn.py negates OFFSET at load (+comment);
  notes before the audio now warn (negative ms); new offline test
  `test_offset_sign`. Both charts RECONVERTED + replaced in the workspace
  (exact row shifts -1400/-2550 verified, bpmChanges shifted identically).
- SUITE (2026-10-17, after fixes): rayfield/player/windui/loader HELD,
  osu 10/10, qua 9/9, eterna 8/8, skins 15/15, escape 2/2, synth 7/7.
- Session-15 header note checked: STALE — the `## Current state` header
  exists in every commit (8d820d8..HEAD, git-verified); nothing was eaten.
- Commit status: repo HEAD is ee8f5df (session 20, pushed); uncommitted
  this session: HANDOFF/ROADMAP docs, `converters/eterna_to_afn.py` +
  `tests/test_eterna_to_afn.py` (offset fix), `src/afn_rayfield.lua`
  (synth_chunks line; deployed to workspace, sha256 DEEE5BCB...).
  Staging is outside git.
- NEXT LIVE: user re-selects insert_coin / sayonara in the mod (the mod
  re-reads a chart's file on select — press Refresh first) and replays:
  expect the audio in sync. Optional: re-execute the deployed mod first
  (gen=2) so the Play line shows `synth_chunks=chunked:N` on the next
  chunked chart.

## Current state (2026-10-16 — session 20; map-porting queue, NOBPM deleted)

- Workspace `AfternightCustomSongs/Charts/afn_sound_architect_NOBPM.chart.json`
  DELETED on user orders (diagnostic done; anchor fix + svflat toggle cover
  its uses). Charts/ holds only Ievan + full SOUND ARCHITECT.
- NEXT (user plan, not started): port Quaver maps (ball_hard, halloween,
  bozo .qua verified) + Etterna maps (insert_coin, sayonara verified) + the
  remaining osu! maps (Drag, Day by day, Blue Zenith, -+-, me & u, d_for
  .osz need extraction) into workspace Charts/ (+mp3s to Audio/).
  Converters ready: quaver/eterna 7/7, osu 9/9 via afn_common.
- Session-15 `## Current state` header was eaten by an edit collision
  (body intact); restore it when convenient. [SESSION 21: STALE — header
  verified present in every commit (8d820d8..HEAD); nothing to restore.]
- PORTING DONE (quaver+osu, staged live, UNCOMMITTED): 4 qua + 6 osu charts
  + matched mp3s in workspace Charts//Audio (12+12 total). Loader bumped
  to v1.2.0 (was stuck at 1.1.0 since skins). Two converter fixes: fold
  None-sort crash (6K/7K mixed hold+tap) + Artist in osu ids (`afn_4k_sc`
  -> `afn_daisan_4k_sc`). Picks: Dragon 6K Blade, Day by day Moving on,
  Zenith JINDIMENSIONS (1531 dropped in 7->4 fold), -+- 4K SC, me&u hyper,
  d_for cCulmination. Old staged (Ievan/SA) keep prior ids — fine.
  Regression test added (osu 10/10). Etterna (insert_coin, sayonara) NOT
  started — next.
- QUAVER SYNTH-FAILED ROOT-CAUSED + FIXED (deployed, needs one live Play):
  `ModuleScript.Source` caps at 200000 chars (probed live); halloween
  (637KB), bozo (432KB), ballin (391KB) JSONs exceeded it, so the synth
  Source write threw before loadSong. Osu maps worked (all <200KB).
  Fix: oversized payloads split into ~100KB raw pieces in child
  Chunk1..N modules with a `require(script.ChunkN)..`-shim as the main
  Source (byte splits safe — per-chunk %q round-trips exactly; 450KB live
  probe reassembled EXACT). Require-wrap (identity-keyed) untouched, so
  engine path unchanged. Play report now carries synth_chunks
  (single|chunked:N). Skrubble (22KB) was never affected.
- QUAVER SV FEEL (ballin'/bozo pop-in, user-confirmed): root-caused to the
  ENGINE's spawn gate (`checkNoteSpawns`: lead = spawnTime/|SV at note|).
  Measured: 55%/62% of ballin'/bozo notes spawn <50ms before hit (median
  39/10ms) vs halloween 0% (median 667ms) — teleport blips (±4.4M, sub-ms)
  leave insane SV active across note ranges, so nothing spawns until the
  receptor. Motion itself is bit-faithful (step integration = Quaver).
  NO motion-preserving fix exists (spawn+motion read the same table; gate
  is game code; spawnTimeMult is a class default, not chart-settable).
  Delivered: (a) SV time FULL precision (was round-3-decimals: 20,039
  timestamps corrupted across the 3 SV maps; net-zero pairs drifted) —
  restaged verbatim, strict win; (b) opt-in `--sv-cap C` on all 3
  converters (qua 9/9 incl. 2 new tests) — NOT applied to staged charts;
  suggested start C=3 (~330ms leads). User choice: cap, svflat, or raw.
- TELEPORT TAMER, PLAYER-SIDE (deployed, needs one live Play): pre-load
  play-copy clamp, |M|>10 -> +-x3, auto-applies only when extremes exist
  (default ON, toggle "Tame teleports", svflat still wins). Same math as
  --sv-cap but per-play, no reconvert. Simulated on staged charts:
  ballin 4472 capped / bozo 2894 capped / halloween 0 (verbatim), median
  lead 10-39ms -> 333ms, sane SVs + notes untouched. Play line carries
  tame=capped(N@x3)|clean|off(flat|setting). Boundary HELD + new check.
  Engine injection assessed: possible in principle (upvalue hook IF the
  executor exposes it — unprobed) but barred by the standing no-hooks
  rule, fragile across client versions, and unnecessary — the tamer fixes
  the spawn side with zero injection. Only revisit on explicit approval.
- SPAWN HOOK (EXPLICIT user approval 2026-10-16, "this is THE project"):
  one game-global write — chunk-global getSVFromTime clamped to +-x1.0
  (full base-speed approach; motion untouched, hook-compatible with the old
  x3 copy-tame which stays as fallback). Verified live: install/passthrough/
  restore + stub-clamp branches; locator scoped to the Client chunk (a bare
  line scan grabbed a chat module's line 3250); export-mirror restores the
  PRIOR value (svFunctions may hold a wrapped copy). Toggle renamed
  "Tame teleports (engine spawn fix)". Boundary HELD + 4 hook checks.
  Deployed — needs ONE live ballin' Play (tame=hooked(N@x1) in the line).

## Current state (2026-10-16 - session 19; the 4-item polish list is implemented, static-green + live-checked, UNCOMMITTED until the user approves)

- STANDING INSTRUCTION (from the session-18 section below): the polish stays
  uncommitted until the user approves it. `git status`: only
  `src/afn_rayfield.lua` modified (section 6.5 rewritten, 616 -> 1095 lines,
  file now 3124 lines). Untracked leftovers (`.cursor/`, `_extract_afn.txt`,
  `_last30.txt`) are not ours to commit. Branch is already 1 ahead of origin
  (session-18 commit); nothing pushed.
- ITEM 1 - mod-list entry: pinned `AFNModRow` (clone of the native mod-list
  `Template` row, 343x50, ModIcon + "Custom Charts") at the top of
  `UpperPanel.Mods`. The mod scroller is shrunk by 56 px to make room
  (`AFNShrunk` attribute, Size {0.98,0,0.925,-56}) and restored by
  `restoreModScroller`. Clicking the row opens/closes the tab; pressing any
  native mod row (`hookNativeModRows`, `Activated`) closes it (click-away).
  The StatsPanel `AFNToggle` button is kept. Row stroke goes back to 0.75 on
  close.
- ITEM 2 - info column: `AFNSelected` (SelectedSong clone: icon, small
  italic ModName "Custom Charts", bold SongName, week line "N notes . BPM .
  m:ss"), `AFNCreds` (Credits clone), `AFNStats` (SongStats clone, 7 lines),
  `AFNDiffs` (Difficulties clone, one `AFNDiff` button labelled "Custom").
  Native SelectedSong/Credits/SongStats/Difficulties and
  `ListSkip.SelectWarning` are hidden while open and restored on close.
  Measured live (SongInfo = 697.8 px tall): 97.1 / 141.0 / 163.6 / 264.8 px,
  i.e. the native proportions (old build: SelectedSong alone was 287 px,
  ~40%). The root cause of the old oversize was never isolated; the fix is
  that the panels are now clones of the native frames at native sizes.
- ITEM 3 - header + stars: `AFNHeader` row (26 px, right-aligned italic mod
  name) above the rows; hidden when the search matches nothing, shown again
  when cleared. Rows (`AFNRow`, 63 px) carry the native `Icons.Favorite`
  star (33 px), gold (255,193,8) when on. Favourites persist in the settings
  JSON under `favorites`, keyed by chart filename (`saveFavorite`). Roblox
  JSONEncode writes an EMPTY table as `[]`, so after un-starring the file
  holds `"favorites":[]`; the reader only checks `type == "table"`, so both
  forms load.
- ITEM 4 - difficulty preview: clicking `AFNDiff` runs `startMenuPreview`
  (does NOT start the chart): Sound `AFNPreview` (vol 0.5) from the matched
  audio file via `getcustomasset`, starting roughly 30% into the track
  (observed 46.9 s of 146.5 s). The menu music is ducked to 0 and restored:
  `RS.Modules.UI.SongSelectV2.Audio.UIMusic` is an AudioPlayer (it has
  `.Volume` but no `.Playing`). Preview stops on selecting another chart,
  closing the tab, and native click-away. A chart with no matching audio
  gets the notify "No audio file matches this chart." and no preview.
- VERIFIED STATICALLY: Luau `loadstring(readfile(...))` compile OK, 125205
  bytes; boundary grep for request / rbxassetid / startSong / SongEvent /
  FireServer / getconnections / hookfunction in src = 0 hits; offline suite
  green (rayfield / player / windui / loader HELD, osu 9/9, quaver 7/7,
  eterna 7/7, skins 15/15, escape 2/2, synth 7/7). (Later update, bug-fix
  round: the rayfield boundary test gained two checks - polish pieces present
  and play-leaves-the-song-select - suite still green.)
- VERIFIED LIVE (PID 17284, run as gen=2, SongSelect forced visible,
  driven with `firesignal` - NOT a human click-through): pinned row present
  and sized; open/close leaves no AFN pieces behind (the game's own hidden
  `AFNCredits` label is native - see below); fav toggle writes/clears
  settings; header hide/show on search; click-away; preview plays and stops;
  UIMusic duck + restore on close, on switching chart and on click-away
  (re-tested with UIMusic forced to 0.5 because its baseline outside the
  real menu is 0; set back to the original afterwards).
- NOT VERIFIED: a human look at the result (screenshots), the new Play button
  end-to-end after the rewrite, real lobby with native menu music, scrolling
  with more than 3 charts, and whether "difficulty click = preview" is the
  behaviour the user meant (item 4 was an interpretation).
- TRAPS: the game's Credits frame contains its own hidden `AFNCredits` label
  (lo=2) - native, not ours, never sweep it by an "AFN" prefix. Luau 200-local
  limit: ~123 top-level locals before this session, the file compiles, but
  headroom is unknown. The git warning "LF will be replaced by CRLF" is just
  autocrlf (src is LF).
- DEPLOY: `src/afn_rayfield.lua` copied to
  `C:\Users\Administrator\AppData\Local\Madium\Workspace\afn_rayfield.lua`
  (CURRENT: sha256 980C61C9E9B95A9A0C5D925AF75386606A98D9938FF8BC9F0A8763613F8087E6,
  132394 bytes, after the blur/music/results fix below; identical to src).
  The RUNNING client (PID 17284, gen=4) was loaded from the previous build
  (sha256 3D73E9FD7A7C42C8F580A0E75AFE995B4E5E88C730F193B03962C9FB09504CB0,
  125724 bytes, the play-leaves-menu build; the first session-19 build was
  36CEC820...), so it does NOT have the fix: re-execute the deployed file to
  load it (gen=5).
- USER FEEDBACK (live, 1 screenshot, after re-executing the deployed file as
  gen=3): "everything seems to work fine for now" - the user will check
  deeper later, so the four polish items are NOT yet signed off. ONE BUG
  REPORTED, status FIXED-PENDING-USER-CONFIRMATION (see below): after pressing "Play Custom" the chart starts
  (gameplay HUD up, "afn_sound_architect_harmonic_bliss (Easy) (0:11 /
  6:20)") but the SongSelect menu STAYS on screen over the gameplay - tab
  still open, the stats-row toggle still reads "Close Custom", Skip Vote /
  "Time Left For Selection: 0" visible. Not yet known whether this is a
  regression from the polish rewrite or was already there in session 18.
  FIX APPLIED (gen=4 loaded live; NOT yet confirmed by the user):
  root cause - NOT a polish regression, session 18 had the same gap. The
  tab's Play button and `doPlay` start the chart through our own
  `playChart` path; the native flow hides SongSelect on play, ours did
  nothing, and our tab (`menuTab`) was never closed. Live read after the
  report: `AFNCustomTab` still alive (stale `menuTab`) while SongSelect.Visible
  was false again (cause of that hide not established; the chart timer label
  was frozen at 1:02 / 6:20, i.e. the chart was no longer running).
  Fix in `doPlay`, in the `rep.stage == "playing"` branch, only when
  `menuTab ~= nil` (play came from the menu; Rayfield plays never touch the
  menu): `pcall(closeMenuTab)` (restores the hidden native pieces, stops the
  preview, toggle label back to "Custom Charts") then `menuRoot().Visible =
  false`. The game re-shows SongSelect itself on its next selection phase.
  A failed start leaves the menu up so the error stays visible. Local UI
  only. Two static checks added to the rayfield boundary test; suite green,
  boundary grep 0 hits, Luau compile OK. Loaded in PID 17284 as gen=4
  (verified no chart was running first); mod row + toggle present, no stale
  tab. NOT live-tested: pressing "Play Custom" with the fix (starts a real
  chart in the user's client, so the user does it).
- BUG ROUND 2 (stuck blur + lobby music after Play; results blur after the
  song ends) - FIXED-PENDING-USER-CONFIRMATION, deployed but NOT loaded in the
  running client, NOT reproduced live (diagnosis is from the decompile).
  Symptom (user): a stuck blur and menu music after Play. The results-blur
  part below is from the decompile, not something the user reported.
  ROOT CAUSE (decompile, Client SetSongSelector listener @9663 + SongSelectV2
  + ResultsRework; evidence files in the Madium workspace:
  `_blur_music_scan.txt`, `_menu_SongSelectV2.lua`, `_results_rework_decomp.lua`):
  * The lobby blur is `Lighting.SettingsBlur` (16 when the select shows, 0.7 s
    Quart InOut). The lobby music is the `UIMusic` AudioPlayer inside the
    SongSelectV2 module. The game's "Hide" branch does: `t_7.inSongSelect =
    false`, `songSelect:hide()` (clears the module's private shown-state,
    hides the frame, `setMusicVolume(0, true)` = tween to 0 then `UIMusic:Stop()`,
    `deselectSong`, cursor manager Disable), SettingsBlur -> 0, and then
    `DataManager:SetData("Favorites"/"Recents")`. Our Play only hid the frame,
    so none of the rest ran (same gap as session 18).
  * The song-end watcher raises the local results screen (`ResultsBlur` -> 32,
    frame `ResultsRework` cloned into `Main.Overlay`); teardown never cleared
    it, so it stayed until the on-screen Continue button.
  FIX (all in `src/afn_rayfield.lua`, two new top-level locals, helpers sit
  above `doTeardown`):
  * `leaveSongSelect(c, fromMenu)`: finds the song-select object as an upvalue
    of the `remoteListen["SetSongSelector"]` listener (first upvalue table
    having `hide` + `deselectSong`; live: exactly one match, index 2). The
    listener is only READ, never invoked (its Hide branch writes Favorites /
    Recents, which stays out). Then `t7.inSongSelect = false`, the object's
    own `hide()` at identity 2 (`atGameIdentity`), and a SettingsBlur tween to
    0 with the game's own timing. Gated: acts only when the select was up
    (`fromMenu`, frame visible, or `inSongSelect` true), because the Settings
    menu uses the same SettingsBlur. Result string lands in
    `rep.subs["leave-select"]`; FAIL or "hide=skipped" raises an error notify.
    Called from `doPlay` (`playing` branch) after `closeMenuTab`, before the
    old `Visible = false` fallback (kept; the test still pins it).
  * `clearResultsScreen(c)`: finds the `ResultsRework` frame (has a `Continue`
    child) in `Main.Overlay`, with a PlayerGui scan as fallback, and calls the
    results module's own `t1.Results.clearUp(frame)` (fades ResultsBlur to 0,
    slides the frame out, destroys it after 1.1 s; pure UI). Run from a new
    `results` step in `doTeardown` (after `leaveLoadingState`), only when
    `c.resultsRaised` is set. The song-end watcher sets it right after its
    successful `endFn(true)`, so a results screen the game made for anything
    else is never touched. No frame found (Continue already pressed) is a
    clean no-op. `teardownReport.resultsNote` records what happened.
  * The boundary test forbids the identifier `createResults` in code, so the
    frame is found by name, not through that function's upvalue.
  VERIFIED: boundary test 6 new checks green (leave helper, SetSongSelector
  read-only + no `lst(` call, no "Favorites"/"Recents"/SetData, call site,
  results step + single `resultsRaised` site, helpers above `doTeardown`);
  the whole offline suite green (rayfield / player / windui / loader HELD,
  osu 9/9, quaver 7/7, eterna 7/7, skins 15/15, escape 2/2, synth 7/7);
  `loadstring` compile OK on a scratch copy of the 132394-byte build (so the
  200-local limit is not hit; scratch file removed); grep for request /
  createResults / FireServer / SetData / "Favorites" / "Recents" in src = 0.
  Live, READ-ONLY (PID 17284, idle): the exact discovery loop found one song-
  select object (idx 2), the gate returned "skipped(select not shown)" in the
  idle state, SettingsBlur = ResultsBlur = 0, nothing written.
  NOT VERIFIED: any of it with a real Play (the user presses Play), whether the
  blur and music really are gone right after Play, whether the results blur is
  gone after the song ends and after Stop, and whether `hide()` at identity 2
  from our thread behaves exactly as from the game's own thread. KNOWN
  LIMITS: a gamepad user keeps the results cursor enabled after our clearUp
  (the game's own Show path has the same behaviour); touch controls are
  re-enabled by `hide()` after the engine loaded (PC client, not exercised).
  UNEXPLAINED, still open: in the earlier report the SongSelect frame hid
  itself while our chart was frozen at 1:02 / 6:20; possibly the game's own
  selection-phase timer (a server Hide), not established.
- NEXT: re-execute the deployed `afn_rayfield.lua` (gen=5), user presses Play
  Custom from the menu tab and reports: (1) blur + menu music gone right after
  Play? (2) any blur left after the song ends, and after Stop? Also still
  open from before: user eyeballs the four polish items. Then commit (suggested
  message: "Session 19: custom charts mod-list entry, native-layout info
  panels, section header + favourite stars, difficulty audio preview; leave
  song select and clear results on play/stop").

## Session 18 (2026-10-16 — session 18; in-menu tab rebuilt from the game's own templates — static-green, NOT run live)

- USER ASK: select menu / lobby menu / solo stage menu "looks bad", should
  look like the game's original UI.
- RECON (read-only live, PID 5532; SongSelect itself was hidden at the time):
  dumped SongTemplate (606x67 px; BG ImageLabel + UIGradient accent,
  StateStroke with per-state UIGradients, SongName / WeekName /
  PrefixDisplay / Icons / UnavailableDisplay), StatsPanel (horizontal
  UIListLayout: Skip lo1, Stats|MusicPlayer lo2, Play lo3), StatsPanel.Play
  (Song + Label, UICorner, UIStroke), SongInfo (vertical UIListLayout:
  SelectedSong lo1, SongStats lo2, ...), SongSearch, Songs.ScrollingFrame
  (4px scrollbar, Y auto-canvas). Old tab = flat boxes with none of that;
  its row-click path used `Cover`, which lives inside the hidden
  UnavailableDisplay and can never be hit.
- REBUILT section 6.5 of `src/afn_rayfield.lua` (draft was staged in
  `_menu_section_new.lua`, spliced in and deleted): every visible piece is a
  Clone() of the game's own template - rows = SongTemplate (SongName /
  WeekName / green PrefixDisplay "CUSTOM" / BG gradient per-chart accent /
  StateStroke default gradient, hover + selected stroke), search = SongSearch
  filtering OUR list, info = SongInfo.SelectedSong + SongStats clones,
  buttons = StatsPanel.Play clones (flat fallback uses the game's font).
  Clones are script-stripped; row click hooks the row button itself.
  Native list / info panels / Play are hidden while the tab is open and
  restored on close.
- ENTRY POINT: "Custom Charts" button (clone of the native Play) appended to
  the StatsPanel row (LayoutOrder 4), kept present by a 2 s watcher; label
  flips to "Close Custom" while open. The mod-list "★ Custom Charts" row is
  gone (superseded). Rayfield "Song-menu tab" button still toggles.
- SOLO STAGE: `SoloUI` is the countdown/tips pop-up ("Wait for 5 seconds to
  play solo"), not a song picker; lobby and solo stage reach the same
  SongSelect frame, so the one in-menu toggle covers both. Solo guard
  (#Players==1 at open AND at Play) unchanged. Zero vote/remote/data refs.
- STALE-BUILD SAFETY: boot + open sweep every piece by name (MENU_PIECES);
  if a stray AFNCustomTab is found the game's own song list is made visible
  again. Cleanup hook now `destroyMenuToggle` + `sweepMenuPieces(false)`.
- VERIFIED STATICALLY: Luau `loadstring` parse OK; rayfield boundary HELD
  with 5 new menu checks replacing the old "menu mod entry" one; full suite
  green (rayfield/player/windui/loader HELD, osu 9/9, qua 7/7, sm 7/7,
  skins 15/15, escape 2/2, synth 7/7). Deployed to workspace
  `afn_rayfield.lua` (sha256 1A63A187...; the previous workspace file was
  byte-identical to HEAD, nothing overwritten). Committed as the session-18
  snapshot (user-approved, before the polish work below).
- USER VERDICT (live, same day, 3 screenshots): the tab WORKS - native-
  styled rows, search, info column, "Play Custom" / "Close Custom" all
  render in the game's own look. Polish list (next work, in order given):
  1. No entry in the MOD LIST column (All / Favorites / Recently Played /
     ...) - the user wants "Custom Charts" listed there, not only the
     StatsPanel toggle button.
  2. Selected-song PREVIEW panel is wrong: the week line ("948 notes · 119
     BPM · 2:25") wraps over the song name, the "Chart Info" header
     overlaps the preview, and the native "Select a song first!" warning
     (SongInfo.ListSkip.SelectWarning) shows through our stats panel. It
     must also show DIFFICULTIES like the native menu (reference shot:
     compact SelectedSong = icon + small italic mod name + bold song name +
     italic week at bottom-right; then Credits, Song Stats, Difficulties
     list with one coloured/italic button per difficulty; Play below).
     Observed: our SelectedSong clone renders ~40% of the column height vs
     ~14% natively - cause not yet known (live read needed).
  3. Native song LIST has "separation" rectangles: a section header row per
     mod (e.g. right-aligned italic "Friday Night Funkin' Fan Remixes" in
     its own bordered rectangle) and each row carries a favourite star at
     the right. Ours has neither header nor star slot.
  4. Selecting a difficulty in the NATIVE menu plays a PREVIEW song (not
     the chart). User wants the same for custom charts: choosing a
     difficulty previews the chart's audio. (Interpretation of the user's
     remark; confirm with them if the behaviour should differ.)
  Standing: user asked for this handoff + a commit BEFORE any of the above
  is started; the polish itself stays uncommitted until they approve.

## Session 17 (2026-10-16) — menu-integration assessed: NOT viable (superseded in part by session 18)

- USER ASK (with lobby screenshot): put custom chart selection into the
  game song-select/freeplay menu. INVESTIGATED (read-only recon only):
  menu = `SongSelectV2` module (106KB decompiled) driving
  `PlayerGui.Main.SongSelect`; songs from local `ModData.Songs` (+ module
  child packs); rows rendered by a local pooled scroller; Play fires local
  signal `play:Fire(mod, song, diff)`; Skip fires `("","","")`; votes shown
  per-player; ad/teleport flows use `TeleportAd:FireServer`.
- VERDICT: not compatible with the no-server boundary. The menu is a
  multiplayer VOTING lobby (per-player votes panel, skip votes, selection
  timer — all server-relayed by construction); launching anything from it
  submits a server vote, and a vote for a server-unknown song is both a
  boundary violation and a guaranteed rejection. Hijack-the-Play-button
  variants lose too: the lobby keeps running the voted song (server-driven
  loadSong/teleport) alongside any local play = double-play chaos. Even a
  solo lobby runs the same vote machinery. The Rayfield picker remains the
  selection UI; the direct-loadSong player already serves solo custom play.
- VIABLE SLICE (offered, not built): read-only companion — mirror the
  menu's current selection/vote into our UI and flag whether a matching
  custom chart exists on disk. Zero server touch. Marginal value; user's call.
- USER CORRECTION: 2 join-stage variants exist (multiplayer game vs solo
  stage). CHECKED (`StageWait` LocalScript, 31KB decompiled): the Solo
  button fires `NetworkFunctions fireServer("StartSingleplayer")` — and
  only on VIP/private servers (`CanSolo` attribute gates public stages).
  VERDICT STANDS, strengthened: BOTH join paths are server-mediated, so
  menu-driven custom launches are out of bounds solo included. The
  direct-loadSong player remains the solo custom-play path.
- REVERSAL (user pushed back, correctly): the verdict covered VOTE-FLOW
  integration, but the user asked for a TAB. A tab-as-launcher never
  touches votes: renderSongs feeds a pooled scroller from data
  (`songScroll:setItems`), so foreign rows would fight the pool — instead
  the tab lives in SEPARATE static containers (own list + own info + own
  Play button calling the existing playChart). Zero vote/remotes/data
  writes; teardown destroys injected UI; gates: engine-idle preflight +
  solo/empty-server guard (#Players==1 refuse otherwise) + menu present.
  Cloned rows carry no engine connections (Clone drops them), so clicks
  can't leak into their selectSong path. Phased: (A) one "Custom Charts"
  button opening the Rayfield picker (~30 lines); (B) full in-menu list
  styled after SongTemplate (name/artist/diffs) with Play (~200 lines).
- Recon artifacts (workspace scratch): `_menu_UI_decomp.lua` (9KB loader),
  `_menu_SongSelectV2_decomp.lua` (106KB), `_menu_StageWait_decomp.lua`.
- NEXT: user decides on the companion slice (or drops menu integration).
- REVERSAL BUILT (user picked full tab B): in-menu Custom tab as pure-client
  launcher overlay. Own list (cloned SongTemplate rows showing pretty name +
  notes/BPM; FCIcon/Favorite/SorryDisclaimer hidden; clones carry no engine
  connections) + own info + own Play button -> existing playChart/doPlay
  (audio automatch reused; diffs single-Easy, noted). Overlay copies the
  list rect inside the Songs frame (its layout is engine-detached) and
  toggles their list off while open. Gates: menu present, #Players==1 at
  open AND at Play (multiplayer refused), engine-idle via playChart
  preflight. Zero vote/remotes/data references (verified by grep + boundary
  suite). Teardown via _G.AFNRayCleanup (restores list, destroys overlay).
  Rayfield "Song-menu tab" button opens it. Boundary +3, luau parse-clean,
  full suite green, deployed. NOT run live. Uncommitted.
- MENU TAB FIXES (user-tested): (1) row taps never registered (Cover clicks
  eaten, almost certainly by the open Rayfield window over the menu) ->
  shared selectMenuEntry with a "Picked:" notify + auto-pick first chart on
  open so Play works immediately. (2) Toggle behavior: Rayfield button now
  toggles open/close. (3) Mod-list entry: "★ Custom Charts" row injected at
  the top of the Mods scroller (re-injected on every open; may be wiped by
  their re-renders — Toggle restores). Boundary +3 (toggle/mod-row), suite
  green, deployed. Uncommitted.
- MENU TAB ROUND 2 (screenshot + `xpcall` line 1899): FOUR defects, all
  fixed: (a) nil-call was likely a nil `debug.traceback` errfunc masking
  the real error — all xpcall sites now use safeTraceback (plain tostring
  fallback). If Play still fails, the REAL error finally surfaces. (b) info
  label never updated: `infoLabel:Set` is Rayfield-only; game TextLabels
  take `.Text` (Set-then-Text fallback). (c) duplicate SA rows (shared
  internal id): display names deduped with (2)/(3) counters. (d) Play
  button fell back to flat green: clone path searched under UpperPanel,
  but StatsPanel lives at SongSelect.Main — exact navigation now.
  Boundary HELD, redeployed. NEXT: user re-executes + Play Custom; the
  traceback (if any) names the real fault.
- THREAD-CAPABILITY THEORY (UNPROVEN, explains everything if true):
  `Play error` = genuine `Instance` Plugin-capability throw, but ONLY from
  menu-button handler threads; Rayfield-thread work (overlay build,
  auto-pick, listfiles) succeeds. Corollaries: menu Cover taps can't write
  .Text (silent info death), menu X can't destroy (toggle-off broken),
  menu Play can't Instance.new (play dead) — while pure-Lua state
  (currentChart assignment) and file reads survive. If proven by the test
  below, the menu tab becomes SELECTION-BROWSER-ONLY (Cover sets chart +
  warn; all instance work moves to Rayfield-side controls) and the mod row
  loses its toggle (re-exec cleanup only).
- DECISIVE TEST (asked user): press RAYFIELD "Play chart" (not Play
  Custom). Works -> thread theory proven, redesign menu tab as above.
  Fails identically -> shared-path bug in recent edits, bisect from
  safeTraceback/LF-rewrite/dedup/clone changes.
- ROOT CAUSE (line 1899 = `xpcall(doPlay, ...)`): the menu section sits
  BEFORE doPlay's definition, and Lua locals scope forward-only — the
  handler bound the NIL GLOBAL, not the later local. Fix: `doPlayFn`
  forward cell + back-assignment after doPlay (+tripwire test). Same class
  audited: no other menu references to later-defined locals.
- CLONED ROWS INVISIBLE: template masters live hidden; Clone() copies
  Visible=false. Forced Visible=true on row + Play clones. (Explains empty
  tab + missing Play button in the screenshot.)
- INFO LABEL: Set-branch removed; direct .Text (Rayfield :Set never reaches
  this function). If display still shows default next cycle, the panel
  itself is a stale ghost — flagged as watch item.
- PLAY BLOCKER, NEW DATA: Rayfield Play fails IDENTICALLY (thread theory
  dead — shared-path bug). `cleanup-incomplete` + load=nil + genuine
  `Instance` Plugin-capability throw, twice-stacked. Prime suspects now:
  `holder.Parent = RS` and `chartMod.Source = ...` (Plugin-gated writes
  that always worked before — possible client/executor tightening).
  DIAG BUILD deployed (per-step DIAG notifies through synth/registry):
  user runs ONE Rayfield Play, last DIAG line names the throwing step.
  Shared path untouched otherwise; menu-only code exonerated for this one.
- STALE BUILD (user): gen=2 console predates the toggle/autopick/traceback
  deploy — user must re-execute before anything above is testable.
- PLAY BLOCKER: `Play error: attempt to call a nil value` with NO preceding
  "Loading" line (doPlay dies inside playChart; shared Rayfield/menu path).
  Added xpcall+traceback to BOTH Play buttons (titles now "Play error" vs
  "Custom play error") + restyled Play Custom by cloning StatsPanel.Play
  (native transparent+label+corner; flat fallback) and mod row with
  left-align/padding/corner. Boundary HELD, redeployed. NEXT: user
  re-executes, presses Play, pastes the traceback line.
- PLAY BLOCKER RESOLVED (user-found, user-fixed): `safeTraceback` was
  defined AFTER `atGameIdentity` uses it — Lua locals resolve forward-only,
  so the reference bound the nil global and `xpcall(f, nil)` threw before
  loadSong ever ran (load=nil, v963=false). The skipped setthreadidentity
  restore left everything at identity 2: teardown Instance ops failed
  (cleanup-incomplete) and Rayfield toast spawns threw the Plugin-capability
  lines. User moved safeTraceback above with a stay-put comment, wrapped
  the xpcall in pcall so restore always runs (failures return false,err),
  and removed the elevated-identity DIAG notifies. I removed the remaining
  playChart DIAG marks. Full play verified live by user (load/start true,
  skin+judge+clip+svflat all applied). Suites green, redeployed. The bug
  was mine (safeTraceback refactor), not environmental — all capability /
  thread / stale-chunk theories discarded.

## Current state (2026-10-16 — session 15; skin judge-swap FIXED + Quaver/Etterna converters)

Two pieces of work, both committed this session:

### 1. Judgement/combo art swap — pooled-label bug FIXED (`src/afn_rayfield.lua`)
The session-14 trail ended with "popup `.Image` takes ID strings" fixed but
never retested. Reviewing `pollJudgeSwap` found a second, independent bug
that would have kept it broken:

- Every terminal path stamped `d:SetAttribute("_AFNSwapped", true)` and the
  guard skipped anything marked. But `RatingsContainer` labels are POOLED:
  the engine reuses the same `FNF_Combo`/`FNF_Rating` ImageLabel and
  rewrites `.Image` / `ImageRectOffset` per popup. A boolean latch therefore
  freezes the FIRST swap of each label and lets every later digit/rating
  fall back to the engine's strip art — and the squeezed strip slice is
  exactly the "digits spawn small" symptom logged in session 14.
- FIX: the marker is now a REVISION, not a flag. `FNF_Rating` stamps the
  engine asset id it swapped on (`imgS`); `FNF_Combo` stamps the digit slot
  (`digit`); both re-swap whenever the live value differs. Unmappable cases
  stamp `<value>|miss` (a new engine write re-opens them) instead of latching
  forever; `FNF_Offset` keeps the `-1` sentinel (still by design).
- Boundary test +3 checks (`marker is a revision stamp`, `no boolean
  latch`, `revisions compare against live value`); rayfield boundary HELD.
- Luau compile PROVEN, not assumed: the edited function was extracted,
  base64'd through the executor, decoded and `loadstring`-compiled in the
  live client (PID 3004) — 5096 bytes, no error. (Whole-file staging is not
  possible yet: the workspace `afn_rayfield.lua` was removed by the earlier
  cleanup, so there is no deployed copy to diff against.)
- NOT yet live-tested by a human (needs a Play with a skin picked).

### 2. Quaver + Etterna skin support (`converters/skins2afn.py`)
`skins2afn.py` was osu!-only. It now resolves art per game and hands it to
one shared `build_pack` (atlas/XML/receptor-scale/body-band/judge/digit
plumbing are shared; each front-end owns its own art rules):

- `convert_osu_skin` — unchanged behaviour. VERIFIED byte-identical: the NC
  pack rebuilt with the refactored code diffs clean against both the
  committed-converter baseline AND the deployed workspace pack.
- `convert_quaver_skin` (new) — Quaver skin folder (`skin.ini` + `4k/`
  tree): `note-hitobject-N` / `note-holdhitobject-N` (head) /
  `note-holdbody-N` / `note-holdend-N` / `receptor-{up,down}-N`,
  `Judgements/judge-*`, `Numbers/combo-N` (score-N fallback). Grade mapping
  by mania equivalence: marv=300g, perf=300, great=200, good=100, okay=50,
  miss=0. End cap is FLIPPED once: Quaver authors it top-anchored, FNF tail
  frames are bottom-anchored.
- `convert_etterna_skin` (new) — Etterna/SM5 dance noteskin
  (`Noteskin.lua` + `Notes/`/`Receptors/`/`Holds/`). Faithful to
  `NoteSkin.Load`: `ButtonRedir` + clockwise `Rotate` for taps/receptors/
  hold heads (holds never rotate), per-direction art preferred over the
  redirect target, generic hold art as last resort, and SM's
  `(res WxH)`/`(doubleres)`/`NxM` frame naming honoured (take cell 1,
  scale to logical size). No judgement/digit art in SM noteskins (theme
  owned) -> engine defaults. Body width is normalized to the note width
  (`normalize_body=True`, Etterna only): Ambie's body is 104px vs a 58px
  note, and the engine stretches bodies to the lane.
- `--game {auto,osu,quaver,etterna}` with layout detection (Noteskin.lua
  or metrics.ini -> etterna; skin.ini + `4k/HitObjects` and no `[Mania]`
  -> quaver; else osu).
- Blank judgement/digit art: a file that exists but is fully TRANSPARENT is
  the author hiding that popup (Still's Circles blanks all six judgements).
  It now becomes a 1x1 blank so the default engine art does NOT reappear
  (previously the file was skipped and the default showed through).
- Tests 15/15 (5 new: blank-judgement, detect_game, Quaver pack, Etterna
  redirect+rotation with a corner-marker fixture, Etterna own-art frames).
  Full offline suite green: rayfield/player/windui/loader HELD, osu 9/9,
  escape 2/2, synth 7/7.
- DEPLOYED to workspace `Skins/`: `still_s_circles` (Quaver, judge 6 +
  digits 11 incl. dot, rec x1.22) and `ambiearrowsffr_skin` (Etterna, 3
  distinct sheets, rec x1.04, engine-default popups). Both converted with
  `--full-width-body` to match the deployed NC pack's `bodyScale 1.0`
  (the user's "verbatim port" rule).
- LIVE-VALIDATED with the game's OWN parser (`ReplicatedStorage.Modules.Lib.
  XML.XMLParser.parse`): all 3 packs x 4 directions = 12 XMLs parse, 19
  SubTextures each, every frame name the client looks up present
  (`{color}0`, `note0`, `{color} hold piece0`, `receptor press0`, ...).
  NOT yet visually tested in a play.

NEXT (needs a human):
- Play once with a skin picked and a skin with judgements (Still's Circles)
  to see the revision-marker fix actually reskin the popups across a full
  combo, and to eyeball the Quaver/Etterna highway art.
- Both new packs are untested live; orientation calls that still rest on
  reasoning rather than eyes: Quaver end-cap flip, Etterna rotation.

## Current state (2026-10-16 — session 16; judge-swap latch revert + event swap + qua/sm MAP converters)

### 1. Judge-swap: pooled revision REVERTED to boolean latch (user-tested)
- Symptom driving it: Quaver combo froze on all-zeros with real-count
  flicker. Live triple reads (Image, offset, stamp) mid-play showed labels
  frozen at (our-0-art, offset 0, stamp 0).
- Root cause: the loop poisoned ITSELF. After correctly swapping digit D
  it zeroes the offset for display; the next tick re-read its OWN zero as
  digit 0 and clobbered every nonzero digit within a tick. The flicker was
  the 1-tick window between correct swap and self-clobber.
- The session-15 pooling premise was WRONG: `releaseChildrenToPool`
  DESTROYS children and t_1.Combo/Judgement are destroyed per spawn —
  first sight carries birth truth, nothing is ever reused. So: swap once,
  latch unconditionally, never revisit (contents/idmap fixed per play make
  later visits decide identically anyway).
- Session-15 revision checks replaced with the once-only invariant plus a
  tripwire on the poison comparisons. Rayfield boundary HELD.
- The "digits spawn small" flash was the same story (strip-slice pre-swap).
- Fix for the residual flash: event-driven swap. Popups are fully built
  BEFORE the engine parents them, so container.DescendantAdded swaps land
  pre-render (zero flash, zero per-frame scan). pollJudgeSwap kept as the
  connect-time sweep; per-label logic extracted to swapJudgeLabel; the
  connection self-disconnects at play end; per-play notifies dropped.
  Boundary +1 (DescendantAdded). User verdict: "now is working".
- Deployed (hash-verified). Uncommitted.

### 2. Quaver + Etterna MAP converters (new, static-green)
- `converters/afn_common.py`: shared chart emission extracted VERBATIM from
  osu_to_afn (fold, hold clamp, stacks, SV anchor, wrapper, no-overwrite).
  osu_to_afn refactored onto it; refactor proven byte-identical on the full
  SA .osu (4659 rows / 32 BPM / 31 SV incl. anchor). osu suite 9/9 unchanged.
  (Side note: deployed workspace SA chart has 30 SVs — converted pre-anchor.
  Harmless: the player anchors in-memory every load, proven live by the
  31-entry Conductor read. File left as-is per no-overwrite.)
- `converters/quaver_to_afn.py`: mini-YAML reader (no PyYAML) for
  Mode/TimingPoints/SliderVelocities/HitObjects; ms-native clock; Keys4
  direct, wider folded, narrower direct-mapped; missing Multiplier kept as
  0.0 stop (qua2gakuran stop finding); degenerate holds become taps.
  Tests 7/7. Real files from the reference .qp packs: ball_hard (1556
  rows), halloween (1776 rows, 522 holds, 13986 SV, continuity smooth),
  bozo (1061 rows, 71 BPM, 0 holds — matches zero EndTime in source).
- `converters/eterna_to_afn.py`: .sm/.ssc dance-single blocks (each becomes
  a chart, id carries difficulty+meter); beat clock integrates BPM segments
  + stops/delays (strictly-after rule, documented) and subtracts warps
  (inside-warp notes dropped+warned); SM5 #SCROLLS -> SV; 2/4 hold+roll
  heads, 3 tails, mines/keysounds/fakes skipped, lifts as taps, unclosed
  holds warn. Tests 7/7 incl. hand-computed stop/warp math. Real LN files:
  insert_coin (535 rows, 388 holds), sayonara (803/232); source head count
  matches output holds exactly (388).
- Extreme-SV policy: Quaver teleport/stop spikes (e.g. +-4.4M around bozo
  7985ms) transcribed VERBATIM like qua2gakuran (engine integrates them;
  the effect is map-intended). No smoothing, no clamping.
- README converter list updated. Full suite green (osu 9/9, qua/sm 7/7,
  skins 15/15, all boundaries HELD). Uncommitted.
- NEXT: user decides whether to stage converted charts (+mp3s) into
  workspace Charts/.

## Standing rule change (2026-10-14, user): "no server" means the IN-GAME
server only (no game remotes/traffic). External servers and library
downloads (e.g. Rayfield via HTTP) are ALLOWED and optional — the old
vendored-only UI requirement is lifted. Next script restarts from basics
with a Rayfield UI; decompiles are kept as evidence.

## Session 14 (2026-10-15) — Phase 2 player skin support BUILT (static-green, NOT run live)

- `src/afn_rayfield.lua` v1.1.0: Skin dropdown (scan `Skins/`, manifest
  names, persisted `settings.skin`, boot restore) + synth noteskin Folder
  at Play (per-direction ModuleScripts: Source = `return %q` pack XML,
  `Image` attr = getcustomasset PNG, parented to the play holder) +
  allowlisted `t21.loadNoteskin("R", folder)` post-Start (single resolve +
  single call site) + teardown `skin` step (clears the engine's persistent
  `noteSets` entry via validated `cacheNoteskin` upvalue, destroys folder;
  unique `AFNRaySkin_<gen>_<seq>` names make any leftover inert).
  Require-wrap generalized to serve skin XMLs (same mechanism as charts).
  Play report gains `skin=`; info label shows pack name. WindUI path
  untouched (Rayfield is the going-forward UI).
- Boundary test: +3 checks (loader allowlisted once, applied once,
  set-cache cleared). Suites green: rayfield/player/windui/loader HELD,
  osu 9/9, skins 5/5, escape 2/2, synth 7/7.
- Deployed (hash-verified): workspace `afn_rayfield.lua` + reference NC
  Skin pack as `Skins/bojii_04_02_2023_svnth_s_edit/` (4 sheets, per-lane
  Left/Right split). Uncommitted.
- KNOWN RISKS for the live test: `Cache.cacheImage` with rbxasset:// ids;
  hold-body stretch/scale type (eyes decide); engine require hitting our
  wrap for synth modules. One attempt, stop on first error.
- NEXT: live test (user presses Play with the NC pack picked): notes +
  receptors render in skin art; Stop teardown clean (`skinCache=cleared`,
  no residue). Then commit on approval.
- LIVE TEST 2 (user): skin applies, but RECEPTORS ARE SMALL (Gakuran deja
  vu). Root cause (source-read): the engine sizes notes/receptors from art
  rects (Sprite FrameSize), and NC key art is 92x95 vs 148x145 note heads
  (~62%). Fix (converter): receptor auto-scale — uniform bilinear upscale
  of receptor+pressed art to note height per lane (clamped 0.5x-4x,
  manifest receptorScale, --no-receptor-scale opt-out). NC pack now
  rec x1.53 (140x145 vs 148x145). Tests 6/6 (+scale-on/scale-off asserts);
  full suite green. Pack reconverted in workspace Skins/ (derived artifact
  refresh). Uncommitted.
- USER Q: "are SVs inverted in SOUND ARCHITECT (fast on slow parts, slow
  on dense)?" Answer: NOT inverted by us — the map's SVs are compensation
  SVs verbatim from the .osu (SV ~= 165/bpm: 0.97@170, 0.89@185), so dense
  high-BPM sections genuinely scroll slower, sparse ones faster. The osu!
  map plays the same way. Offered follow-up (not built): constant-scroll
  option (flatten SVs at convert or ignore-SV toggle at play).
- USER FOLLOW-UP: original osu! map "literally goes faster on dense parts"
  + "are AFN SVs FNF-like rather than osu-like?" SETTLED LIVE (read-only
  call, engine's own functions, zero state change): getPosFromTime slope
  at 190s (SV 1.10) = 1.584 vs at 290s (SV 0.74) = 1.0656, ratio 1.4865 =
  1.10/0.74 exactly. The engine MULTIPLIES approach speed by SV, same as
  osu!mania — no FNF/osu difference, no inversion. Density table: the
  densest stretch (270-315s, ~20 n/s) sits at the slowest SV (0.74), so it
  scrolls slowest in EVERY client with these values; any faster look in a
  video is density perception/playback conditions, not engine math. Live
  map also confirms the t0 anchor is in effect (31 SVs, first {0,1}).
- USER VERDICT: receptors correct after x1.53 auto-scale.
- SV-FLATTEN OPTION (user-approved): Playback toggle "Ignore SV (constant
  scroll)", persisted `settings.ignoreSV`; at Play the JSON copy (same one
  as the offset path) empties `sliderVelocities` -> engine raw-ms path
  (proven-clean config), reported as `svflat=emptied(N)` in the Play line.
  Loaded chart untouched; boundary +1 check, HELD, redeployed. Uncommitted.
- PHASE 3 (skin visual verification) STARTS: user eyeballs the skinned
  highway; open items: hold-body stretch behavior, teardown residue
  (`skinCache=cleared`), Stop-then-replay with skin.
- PHASE 3 TEARDOWN VERIFIED LIVE (read-only snapshot after user's Stop):
  pools 0/0/0/0, loadedSong/inSong false, v963 false, holder gone, zero
  RS skin leftovers, zero stale skin set-cache entries, registry nil,
  Character remote restored. Same-session skin replay was already clean
  in console (gen=2, gen=3). Phase 3 teardown: PASS.
- USER REPORT: notes good, hold/end caps work, BUT hold heads vanish (tap
  disappears, body only — osu keeps the hold head). VERDICT: engine design,
  WONTFIX (client 8681-8684: `if not sustainNote then wasHit=true,
  Destroy()` — heads die on hit by construction; sustains persist as body;
  osu-style persistent heads need engine changes). Our headHold art still
  ships (covers the no-body fallback where hold=head art).
- USER REPORT: BPM pulse restarts mid-pulse on BPM change (tiny cosmetic).
  VERDICT: engine-native, WONTfix (runtime 9958-9992: changeBPM swaps
  Crochet/StepCrochet instantly; DecimalStep recomputes from the
  non-accumulated stepTime -> beat phase jumps -> bop tweens restart;
  official charts do the same; engine code untouchable).
- FONTS/JUDGEMENTS RECON (read-only; RatingManager 20 kB decompiled):
  judgement art = `Settings.JudgementImages[name]` else set-child `.Value`,
  applied as `"rbxassetid://"..id` onto a cloned Rating template (RM
  339-377); combo digits = same prefix on a digit-STRIP sheet
  (`ImageRectOffset = 100*digit`, RM 73-96). Both paths HARD-PREFIX
  rbxassetid://, so local getcustomasset URIs cannot flow through them.
  Ways: (a) user uploads PNGs -> numeric IDs in manifest (CDN fetch, not
  game-server; needs boundary carve-out + approval); (b) post-spawn swap:
  poll while playing for FNF_Rating/digit popups, overwrite .Image with
  local Content (no uploads, no state, teardown-free; new per-frame touch
  surface); (c) game-template swap (most invasive, not proposed).
- USER PICK: post-spawn swap. Template recon: Rating/Number/Decimal slots
  are all ScaleType Fit (no converter aspect work needed). Popup names
  exact: judgement labels = "FNF_Rating", combo digit labels =
  "FNF_Combo" (combo text is pure digits, offset/100 safe incl. 0),
  "FNF_Offset" skipped (symbol slots share the strip).
- BUILT (uncommitted): converter emits `judge/hit{300,300g,200,100,50,0}`
  + `digits/score-{0-9,dot,comma}` + manifest maps (tests 7/7);
  player 8.6 builds per-rating/per-digit Content + asset-id map (defensive:
  digits swap map-free, judgements skip gracefully without an id map),
  doPlay poll loop 20Hz cap-30/tick with marker attrs, `judge=` in report;
  no teardown (popups engine-owned). Boundary +2 checks, full suite green.
  NC pack reconverted (judge 0/50/100/200/300/300g, digits 0-9+dot+comma),
  script redeployed. NEXT: user plays (autoplay ideal: constant sick +
  climbing combo), eyeballs judgements/digits; console shows swap count.
- LIVE TEST 1 (user, same session): TWO errors, both diagnosed from console:
  (1) `Skin Callback Error ... stack overflow` at boot: selectSkin called
  skinDropdown:Set, and Rayfield Set fires the callback -> infinite
  recursion (triggered by the persisted-skin boot restore). Fix: never Set
  inside selectSkin (dropdown already shows the pick; boot restore's single
  Set -> callback -> selectSkin terminates).
  (2) `skin-apply-failed ... Requested module experienced an error` in
  Sprite.GetAnimationsFromXml: the require-wrap was installed only in
  loadSong's env, but Sprite frame parsing runs in a DIFFERENT env table
  (proven live: getfenv differs, require nil in both raw envs), so
  require(synthModule) fell through to the engine. Fix: install the same
  wrapper (it already consults skinXmlByMod) in the Sprite env too, found
  via getgc source scan; teardown restores both envs. Chart plays
  unaffected (default-skin path installs nothing extra).
  Static green (boundary HELD + new sprite-env check), redeployed.
  NEXT: user re-executes the file (fresh boot) and retries one skinned
  play. Uncommitted.
- USER VERDICTS (Phase 3): notes good, receptors fixed (x1.53), hold/end
  caps work. Hold heads vanish by engine construction (wontfix, client
  8681-84). BPM-pulse restart is engine-native cosmetic (wontfix).
- USER ASK: hold bodies must stay behind receptors. DONE:
  `t21.setSustainClipping("R", true)` post-Start (single call site,
  `clip=R=true` in report) — engine pins held sustains at the receptor
  line (FNF-standard; hit logic untouched per 10116-20); flag lives on
  throwaway strumlines (pools 0 post-teardown) so no restore. Boundary +1,
  HELD, redeployed. Uncommitted.
- USER REPORT: combo/judgements/ms-counter not applied on re-execute.
  Console: plays show `judge=armed` (loop armed, no errors) yet zero
  visible swaps. Added diagnostics: first-swap notify + first loop-error
  notify (the pcall was swallowing everything). NOTE: the ms counter
  (FNF_Offset) is skipped BY DESIGN (digit/symbol slots share one strip;
  swapping corrupts symbols). NEXT: user re-executes + plays once; the
  notifies say whether the loop swaps nothing (data) or dies (loop).
- QUAVER COMBO ALL-ZEROS (user): combo grows to 2-3 digits but every slot
  shows "0", real count flickering through. ROOT CAUSE (live triple reads):
  labels frozen at (our-0-art, offset 0, stamp 0). The loop poisoned ITSELF:
  after swapping digit D it zeroes the offset for display; the next tick
  re-read its OWN zero as digit 0 and clobbered every nonzero digit within
  a tick (the flicker = the 1-tick window between correct swap and
  self-clobber). The session-15 pooled-revision premise (label reuse) was
  WRONG: releaseChildrenToPool DESTROYS children and t_1.Combo/Judgement
  are destroyed per spawn — first sight carries birth truth, nothing is
  ever reused. FIX: back to boolean latch, swap once, never revisit
  (contents/idmap fixed per play make later visits decide identically
  anyway). Session-15 revision checks replaced with the once-only
  invariant (+tripwire on the poison comparisons). Boundary HELD,
  skins 15/15, redeployed. NEXT: user re-executes + plays; combo digits
  should read correctly with only the inherent 1-frame strip flash.
- EXIT NOTIFY VERDICT (user): "No popups matched (scan sees 72 nodes)".
  72 nodes = small tree, zero FNF_* inside -> popups live in a DIFFERENT
  subtree (method reparent), not a naming/attribution problem. User's worry
  (their custom art IDs broke it) is absolved: idmap built fine either way
  (Play line said `armed`, not `armed(digits-only)` — data.JudgementImages
  is readable). NEXT: user plays to the results screen WITHOUT pressing
  Stop; then a read-only UI inventory finds the real popup parent; fix
  scan roots to match. Bodies reverted to full-width in the same build.
- JUDGEMENTS WRONG ASSETS (user): converter used root mania-hit*/hit*
  files, but the skin AUTHOR overrides via [Mania] Hit0/Hit50/Hit100/
  Hit200/Hit300/Hit300g refs into Judgements/ (e.g. Hit300g ->
  Judgements/MANIA400). FIX: judge_path honors the Hit* refs first,
  stable names only fallback (mirrors NoteImage/KeyImage handling).
  Tests 9/9 (+ini-refs test). Pack reconverted (judge PNGs now the small
  author art). No script change; Play reads current files (content-hashed
  asset URIs, no staleness). Uncommitted.
- GRADE MAPPING FIX (user): Marvelous showed hit300, should be hit300g
  (Geki outranks plain 300). Player prefs swapped: marvelous ->
  {"300g","300"}, sick -> {"300","300g"} (fallbacks both ways, skins
  without 300g unaffected). Boundary HELD, redeployed. Needs re-execute
  (prefs are code). Uncommitted.
- COMBO SMALL-THEN-FIX (user): digits spawn small, correct within ~50ms.
  Mechanism: engine shows a strip-SLICE (ImageRectOffset with no rect size
  squeezes several strip digits into the label) until our swap lands; the
  50ms was our poll throttle. FIX: poll every frame (marker-skip + caps
  keep it cheap). Residual ~1-frame flash is inherent to post-spawn
  swapping and cannot go lower. Boundary HELD, redeployed (re-execute).
  Uncommitted.
- EVENT-DRIVEN SWAP (flash kill): the 1-frame floor assumed polls, but
  popups are fully built BEFORE the engine parents them — so a
  container.DescendantAdded hook swaps pre-render (zero flash, zero
  per-frame scan). pollJudgeSwap kept as the connect-time sweep;
  per-label logic extracted to swapJudgeLabel; latch semantics unchanged.
  Connection self-disconnects at play end (gen/playing/ctx guard); no
  teardown (popups engine-owned). Per-play notifies dropped (working art
  is self-evident). Boundary +1 (DescendantAdded), full suite green,
  redeployed. NEXT: user re-executes + plays; digits should appear
  correct from the first visible frame. Uncommitted.
- UNEVEN DIGIT SIZES (user): engine strip gives every numeral an identical
  100px cell, but osu! score PNGs vary in width ("1" vs "0") — Fit into
  equal slots renders different visual sizes. FIX: converter centers 0-9
  on the max-digit canvas (dot/comma keep native punctuation size).
  Tests 10/10 (+uniform-cell). Real pack: all digits one 24x28 cell.
  Judgements intentionally untouched (grade art varies by author design).
  No script change; Play reads current files. Uncommitted.
- DURING-PLAY INVENTORY (user-approved sampling, autoplay running):
  popups ARE under `Main > Game > RatingsContainer` (tree was right!) —
  but all 4 live labels already carry OUR `_AFNSwapped` marker with
  UNCHANGED default images. So the loop sees them and marks them skipped:
  art resolution misses at play time even though the same paths resolve
  fine idle (verified: judge/hit300.png + digits/score-5.png files exist,
  getcustomasset + Content.fromUri all ok). Static review of every link
  (manifest/prefs/Content/idmap/branch conditions) finds no defect, so the
  failure is runtime state invisible post-hoc. NEXT: armed line now reports
  `armed arts=N digits=M map=K` (counts built at Play) — one more user run
  reveals exactly which table is empty. Redeployed.
- PLAY LINE: `judge=armed arts=6 digits=10 map=8` — ALL TABLES FULL, yet
  still zero swaps. ROOT CAUSE (live experiment on a real popup):
  `label.Image = <Content object>` throws "ContentId expected, got
  Content" — popup .Image takes ID STRINGS only (audio is the opposite:
  SongPlayer wants Content objects). Every swap died in the pcall and fell
  through to mark-skip. FIX: judge/digit arts stored as URI strings.
  Boundary HELD, redeployed. (Side effect of the probe: one live combo
  digit was swapped to the string URI successfully — feature proven.)
- HOLD-BEHIND, ROUND 2: clipping pins position but does NOT change draw
  order (sustain Z > receptor Z either way) — and the flag provably landed
  on R (skin works through the same t_27 key mapping; a miss would have
  aborted the play). True occlusion needs per-instance Z writes (live
  structure recon required — deferred). INSTEAD: narrow body band in the
  converter (true body art squeezed to 45% FNF-style, bilinear;
  head-art fallbacks keep full width via byte-compare; manifest bodyScale;
  --full-width-body opt-out). Tests 8/8. Pack reconverted (piece 58x32
  vs 148x145 head). Combined with clipping pin + x1.53 receptors, the
  receptor shows around the body. Uncommitted.
- USER VERDICT on bodies: skins stay faithful to the osu! original —
  REVERTED to full-width bodies (`--full-width-body`; pack reconverted).
  Clipping stays (harmless standard). Documented principle: ports are
  verbatim, no aesthetic reshaping (receptor auto-scale REMAINS — sizing
  is engine-necessary, not a look change).

## Session 13 (2026-10-15) — Phase 1 skins2afn converter DONE (osu! only, uncommitted)

- `converters/skins2afn.py` (new, stdlib-only PNG codec reimplemented, no
  Gakuran imports): skin.ini [Mania] NoteImage*/KeyImage* (+H/L/T/D states,
  stable mania-note*/mania-key* fallback) -> `Skins/<slug>/` pack: per-4K-
  direction PNG atlas + Sparrow XML (`purple/blue/green/red` + generic
  `note*`/`receptor*` frames per the Phase-0 contract) + manifest.json
  (`afn-skin/1`). No aspect framing (engine uses exact rects); alpha-crop
  only; identical lane sheets deduped to sheet.png; no-overwrite rule like
  osu_to_afn. Fallbacks: head->body bar, none->no tail frames, key->pressed.
- `tests/test_skins2afn.py` 5/5: basic pack (frame-name asserts per dir),
  per-lane split (sheet_left/right), bare fallback skin, idempotent+refusal,
  PNG codec round-trip (RGBA/gray/palette).
- REAL-SKIN SMOKE (reference NC Skin, read-only in -> Temp out): converts,
  Left+Right split (matches Gakuran's tap1/tap4 split of this skin), 19
  frames/dir, PNGs decode at manifest sizes.
- ENGINE-LEVEL PROOF (live, read-only): the game's own XMLParser (required
  from RS.Modules.Lib.XML) parses our purple.xml: 19 SubTextures, all 9 key
  animation names resolve (`ok=true`). Scratch check file deleted after.
- Full offline suite green: skins 5/5, osu 9/9, rayfield/player/windui/
  loader boundaries HELD, escape 2/2, synth 7/7.
- KNOWN UNKNOWNS for Phase 2 (player): hold-body stretch/scale type (Phase
  3 visual check decides); `Cache.cacheImage` with rbxasset:// ids;
  require-wrap must cover synth skin modules (engine require fails on
  executor instances — same mechanism as charts); new allowlist item
  `t21.loadNoteskin` post-load (needs explicit user approval); set
  Metadata modules omitted (only ModFile Metadata is read anywhere).
- NEXT (Phase 2, needs approval): Skin dropdown in Rayfield UI + synth
  noteskin Folder at Play + restore at Stop. Uncommitted.

## Session 12 (2026-10-15) — Phase 0 skin recon DONE (read-only live, PID 13832)

- Noteskins are LOCAL: `RS.Assets.Noteskins` holds 171 sets (incl.
  "Afternight", "osu!mania Default", "Quaver Circles"); lookup is pure
  FindFirstChild (client decompile 832, 6233+). `getAsset("Noteskins")`
  only fires when strumline has no NoteskinPath (9139 fallback).
- Set shape: Folder of per-direction ModuleScripts (Left/Down/Up/Right
  minimum; `getSetBelow` self-resolves r-variants/Plus/Square/2-suffixes).
  Each dir module's Source is `return "<Sparrow XML>"` (verified live:
  FNF Left requires to an XML string of SubTextures); `Image` attribute =
  spritesheet id; attrs Framerate/SizeMult/Factor/Antialiasing.
- Frame names (client 5964-5996, 6036-6061): notes `{color}0` (+`alone0`,
  dirname aliases), hold body `{color} hold piece0`/`hold0`, tail
  `{color} hold end0`/`end hold0`/`tail0`, receptors `receptor0`,
  `receptor confirm0`, `receptor press0`/`pressed0`. 4K colors live:
  Left=purple, Down=blue, Up=green, Right=red (ManiaData.dirXmlColor).
- Injection: `t21.loadNoteskin("R", <our Instance>)` post-load accepts ANY
  Instance (6379, 6256) — synth Folder (local, never RS) + per-dir
  ModuleScripts (`return %q` XML, same trick as charts) + `Image` attr =
  `rbxasset://` getcustomasset PNG. New allowlist item; needs user OK.
- Effects: `RS.Assets.Notesplashes` local (Entity set: 4 dir modules +
  Metadata, same shape); `Holdsplashes` in `__AssetContainer` (4 sets) =
  container-hit silent, custom set MUST be pre-seeded (miss = FireServer).
- Ratings/Afternight children are NumberValues (timing windows, not art);
  judgement ART comes from `Assets.Templates` via RatingManager — mapped
  for the later judgements phase. `Modules.Customization` holds
  RatingStyles/JudgementWindows/HUD (same).
- loadSong 13205 takes skin names from SETTINGS (`v1.Noteskin`,
  per-side `getSetting`), NOT the chart: our plays use the user's
  configured skin. Custom skin does not touch settings (post-load
  loadNoteskin call instead).
- Decompiles saved (workspace scratch): `_phase0_Note_decomp.lua` (19 kB),
  `_phase0_Sprite_decomp.lua` (74 kB). No game state changed (6 read-only
  calls + 2 decompile/writefile).
- NEXT (Phase 1): `converters/skins2afn.py` (osu! only): atlas osu!
  head/body/cap/key PNGs into per-direction sheets + emit Sparrow XML
  with the names above + manifest; `Skins/<slug>/` packs; offline tests.
  Needs user approval to start building.

## Session 11 (2026-10-14) — SV-map root cause FOUND + anchor fix (built, static-green, NOT run live)

- ROOT CAUSE (source-traced, user's "fix it" order): the engine's
  `mapVelocityChanges` (client decompile 4624) anchors cumulative track
  position at `SV[1].startTime x speed x mult`, but `getPosFromTime`
  (4666) uses the raw `time x speed` path for anything BEFORE
  `SV[1].startTime`. A first SV after t=0 makes track position
  DISCONTINUOUS there: jump = t·v·(1-m). SA: 40833·v·0.03 = 1225·v.
  Render Y = CurrentTrackPos - initialPos (MathFuncs, session 8), so every
  note at/after 40.8 s sits 1225 ms-equiv too close to the receptors from
  spawn-lead (~35 s) until the crossing, where the whole field snaps by
  1225 and is correct after. Hit accuracy is unaffected (Y=0 at T=S either
  way) -> matches "botplay fine, self-correcting". BPM map exonerated for
  placement (runtime use is changeBPM scalars + DecimalStep/stepHit only,
  9958-9992; dedup 7876 only picks which stacked note survives).
  Why Ievan is fine: its 4 SVs are all x1.0 (jump = 0). Why the old
  emptied-map NOBPM was clean: raw path everywhere.
- .osu semantics (read-only, reference .osu): effective SV is 1.0 before
  the first inherited point (SA: reds at 3015+, first inherited at 40833
  x0.97); the converter dropped that implicit prefix. FIX = materialize
  `{startTime=0, multiplier=1}` when SV[1] starts > 0 (idempotent).
- OPEN INCONSISTENCY (flagged, not buried): the session-8 "SV-stripped +
  audio still glitched" verdict does not fit this mechanism (any stripped
  map takes the raw path). Possible test error or choppiness misread; the
  anchor live test re-decides it.
- PROOF (executable, before fix): Luau harness with the engine functions
  verbatim + SA's real 30 SVs (`Temp/opencode/sv_glitch_verify.lua`):
  raw map worst 10 ms CTP jump 1215 @40830 ms, probe-note (S=45000)
  misplacement 1225 pre-crossing -> 0.0 after; anchored map worst step
  10.0 (=speed x dt, smooth), misplacement 0.0 everywhere.
- FIX (3 sites, same logic): `converters/osu_to_afn.py` emits the anchor +
  warning; `src/player_core.lua` `normalizeChart` anchors in-memory (covers
  WindUI path); `src/afn_rayfield.lua` `readChart` anchors in-memory, sets
  `_svAnchored` (info label still counts map SVs: "30 SV +t0-anchor", Play
  report `subs["sv-anchor"]`). Player-side is in-memory only: deployed
  charts need NO reconversion (no-overwrite rule respected).
- VERIFICATION: anchor-logic harness 7/7 in real Luau (incl. idempotency,
  empty/missing/malformed/NaN cases); suites green: osu 9/9 (2 new: no
  anchor at t0, track-position continuity regression), rayfield/player/
  windui/loader boundaries HELD, escape 2/2, synth 7/7.
- DEPLOYED (hash-verified, NOT committed, NOT live-tested): workspace
  `afn_rayfield.lua` + `afn_player_core.lua` match `src/`.
- NEXT: decisive live test (user presses Play): FULL SA + mp3 + autoplay,
  watch 35-45 s. Expect no teleport. Clean => root cause confirmed;
  glitch persists => mechanism wrong, re-open.
- LIVE VERDICT (user, same session): FIXED. Full SOUND ARCHITECT plays
  clean through the 35-45 s window. Root cause confirmed; the session-8
  "SV-stripped still glitched" verdict is discarded as a test error.

## Session 10 (2026-10-14) — new Rayfield script (built, static-green, NOT run live)

- `src/afn_rayfield.lua` v1.0.0 (self-contained, staged to workspace as
  `afn_rayfield.lua`, 53 kB): FunkyChart-style flow (Charts/Audio/Assets
  folders, chart list + audio auto-match, options, underframe, Play/Stop),
  Gakuran-style shell (capability check, gen cleanup + Rayfield sweep,
  Settings.json, chart validation, Rayfield tabs Charts/Options/Misc),
  player_core 1.3.0 play path ported verbatim (preflight, subs, synth %q,
  registry + local Content audio, loadSong @8058 identity 2, Start
  listener, autoplay, endSong(true) watcher, abruptGameEnd teardown).
  Side fixed "R" (proven); offset slider shifts rows at play (logged).
  Rayfield loads via one HttpGet to sirius.menu/rayfield (rule-lifted).
- Static: new `tests/test_afn_rayfield_local_only.py` HELD; existing
  player/windui/osu suites still HELD.
- LIVE TEST (PID 13152, 2026-10-14, approved "do some tests in game"):
  pre-snapshot clean (PlaceId ok, pools 0/0/0/0, loadSong@8058 found,
  loadedSong=false, inSong=false, v963=false). Boot `afn_rayfield.lua`:
  gen=1, Rayfield window created (visible, all 5 elements), notify wired.
  Driven via `firesignal(MouseButton1Click)` on the real UI buttons
  (madium click_gui_button could not resolve gethui() paths; inspect_visible_ui
  crashes on a foreign ReNotifyV2 ImageButton — tool bugs, not ours).
  Results, all PASS in one session:
  1. Chart dropdown select (Ievan) -> info label "119 BPM | 948 notes |
     0 BPM changes | 4 SV | audio: audio.mp3", audio auto-matched to the
     stem mp3, "Chart loaded" notify.
  2. Play (Ievan): stage=playing, load=true, start=true, Unspawned=948,
     Strums=8, note0=R/0@399, audio=local mp3, Conductor advancing
     18.2s -> 20.3s over 2s (audio clock). Stop -> stage=stopped;
     post pools all 0, loadedSong/inSong false, holder+remoteHold gone,
     Character remote back, ratings clone destroyed, AFN registry nil.
  3. SAME-SESSION REPLAY: second Play/Stop cycle identical PASS.
  4. Refresh button -> "Refreshed: 2 row(s)"; SOUND ARCHITECT select ->
     validated "4659 notes (865 holds) | 32 BPM changes | 30 SV" (exact
     converter match), audio auto-matched. Play: Unspawned=6259,
     note0=R/0@3015, load/start true; Stop -> stopped. Post idle re-read:
     pools 0, flags false, v963 false, AFN entry nil, HideLobby=false,
     SVChanges=true, ShowResults=true.
  NOT yet tested live: song-end results screen (needs a full song through
  the UI), autoplay toggle, offset slider, background options.
  Caveat: console showed foreign "Aimbot/ESP" Rayfield labels — another
  script shares the Rayfield GUI container; our elements are distinct
  paths (Main/Elements/Charts/*) and unaffected.

## Session 7 (2026-10-13) — local-audio pipeline (probe GREEN, play test pending)

The full-play core and WindUI chart picker are implemented; UI boot and
three-chart discovery are recorded live, and a full-play smoke path succeeded in
session 4. This change adds a `forceIdle` cleanup attempt for idle flags and pool
tables plus a simplified Chart / Refresh / Play / Stop UI. Same-session replay
is NOT yet live-verified. Table clearing cannot prove orphaned Roblox Instances,
render bindings, camera, or HUD state are restored; rejoin only if Stop remains
`cleanup-incomplete` after retry until live evidence establishes a stronger
recovery contract. The player's boundary is non-invocation, not strict network
silence: see the documented indirect `UpdPreferences`/`Sync` side effect below.

### Session 7 detail — local-audio pipeline (probe GREEN, play test pending)

Goal from user: charts play but no music yet — wire local music in-game.

Engine audio contract (read from source):
- `songIds[Mod].Songs[name].Audio` -> `t_14.SoundInfo` -> `v90:load(SoundInfo)`
  (client decompile 12929, 13443-13445). `load()` wraps a bare table as
  `{Paths={_default=<SoundInfo>}}`, so the registry `Audio` table IS the
  path desc `parsePath` consumes.
- `parsePath` non-segment branch builds `SoundNames` from
  `Instrumental`/`Voices` keys; a `Content` object value is used directly
  (no `rbxassetid` round-trip) — `afn_decomp_SongPlayer.lua:296-338`.
- `_CachedAudio` attr is only a length fallback when `timeLength<=0`
  (decompile 14210-14216) — kept as-is; real audio reports its own length.
- Stop is audio-safe: `abruptGameEnd` -> `clearUp(true)` tweens `Music` to 0
  and `v90:unload()`s ~1s later (decompile 11476-11488). No extra teardown
  needed, but a Play within ~1s of Stop could race the delayed unload.

Live probe (PID 17616, PlaceId 13042495892 — approved copy+probe):
- Copied `.../_scratch_convert/extract/993703/audio.mp3` (2,344,662 B) to
  workspace `AfternightCustomSongs/Audio/afn_ievan_polkka_4k_nsv.mp3`.
- Probe (temp `AudioPlayer` in `SoundService`, destroyed after): `isfile`
  true, `getcustomasset` -> `rbxasset://...` string,
  `Content.fromUri` -> Content ok, `TimeLength` 0 -> **146.52 s in 0.25 s**,
  preload call ok, cleanup `yes`. Local audio loads — engine path viable.
- Camp's `AudioFilename: audio.mp3` has NO file in its folder (audio
  missing); synth/easy_001 have no audio. Ievan is the first audio test.

Built (uncommitted, offline-tested, deployed — NOT played live):
- `src/player_core.lua` **1.3.0**: new `opts.audioFile` (workspace path).
  Resolved live via `Content.fromUri(getcustomasset(path))` into registry
  `Audio={Instrumental=<Content>, Volume=1}`; resolve failure aborts to
  `audio-resolve-failed` with full teardown. Omitted -> audio-free
  free-run as before. `rep.audioFile` / `rep.subs["audio"]` recorded.
- `converters/osu_to_afn.py`: records `song.audioFile` basename from the
  `.osu` `AudioFilename` (workspace `Audio/` resolution is a player
  concern). Existing fixtures unchanged (no reconversion).
- `src/player_windui.lua`: new **Audio** dropdown over
  `AfternightCustomSongs/Audio/*.{mp3,ogg,wav}`, auto-match by chart stem
  (`<stem>.mp3/...`) else the chart's `audioFile` hint; manual override;
  passed as `audioFile` to `core.play`; Play desc updated.
- Tests: `test_osu_to_afn.py` 4/4 (new `audioFile` assert),
  `test_player_local_only.py` HELD (audio gated on `opts.audioFile`,
  getcustomasset+Content.fromUri only, single Instrumental site, no
  `rbxassetid` literals), `test_player_windui_local_only.py` HELD (audio
  dir/dropdown/automatch checks); tap harness + escape + synth suites
  still pass.
- Deployed (file copy only): workspace `afn_player_core.lua` (1.3.0) +
  `afn_player_windui.lua`. Workspace Ievan chart verified: 948 notes,
  119 BPM, no `audioFile` key (old converter) — stem auto-match covers it.
- NOT yet run live: audio play (load+start+audible check+Stop) needs
  explicit approval per one-attempt rule. No engine state changed this
  session (probe instances only, destroyed).

### Live audio play (PID 17616 — approved, `afn_audio_test.lua`, one attempt)
- PRE: idle (pools 0/0/0/0, `SongPlayer` paused/curAudio nil/timeLength -1).
- PLAY Ievan + matched mp3 (`keepAlive`): `load_ok`, `start_ok`,
  `stage=playing`, UnspawnedNotes=**948**, Strums=8, Strumlines=2,
  note0=R/col0 @399 mustPress.
- OBSERVE 6 s: `SongPlayer` unpaused, `timePosition` 0 -> 2.00 -> 5.02 s,
  `timeLength` 146.52, 1 path/1 audio; Conductor -980 -> 2010 -> 5023 ms —
  **conductor tracks the audio clock** (2.005 s vs 2010 ms). Character
  survived (misses, no death). Transport-level PASS; speaker audibility
  needs a human ear (user asked to confirm).
- STOP: `stage=stopped`, `ok=true`, every step ok (abruptGameEnd,
  leaveLoadingState, idle-flags, pools-notes, pools-strums, require,
  charRemote, ratings, registry, holder). 2.5 s later: flags false, pools
  0/0/0/0, audio players unloaded (a Paths/audios 0, paused, pos frozen).
- Cosmetic bug found by the report: `stop.err` was always set
  (`rep.ok and nil or x` is always x in Lua). Fixed with if/else in
  `player_core` (uncommitted) + redeployed workspace core. UI unaffected
  (it branches on `stage`/`ok`, not `err`).
- Same-session replay still NOT proven (second play unattempted); strum
  Instance/HUD/camera residue unknown. Rejoin advised before next play.
- UI re-executed on user request: fresh boot, splash + locator-retry fix
  now live in the running window (`player_core 1.3.0 ready`, 4 charts).
- USER VERDICT (2026-10-13, PID 17616): audio works, Stop + replay work,
  no problems at all — custom chart with local music is PLAYABLE. This
  clears the two pending live items: speaker audibility and same-session
  replay, both confirmed by human testing rather than instrumentation.
- User bug report: songs never end (no end screen; only Stop works) +
  "delete test files" (both workspace sets).
- Root cause (source-read, decompile 11269-11272): at audio end the engine
  only fires the `onSongEnded` modchart hook; real ending is server-driven
  (`Clear` -> `endSong` -> `createResults` + `clearUp`), which never arrives
  locally. `createResults` itself is fully local (score/judgement reads +
  `Results.create` UI; the only server lines in the 15k-line client are
  elsewhere), `ShowResults=true` live, `t21.endSong` is a function, and
  loadSong ends with `v963=false` (14303) so `endSong`'s `clearUp(true)`
  takes the full path. Residual: `MedalAutoclip=true` live may attempt a
  `TriggerClip` inside `endSong` (module exists, required at boot) —
  our call is pcall-wrapped with an abruptGameEnd fallback.

## Session 8 (2026-10-13) — song-end + results screen (built, needs a full-song live test)

- `player_core` (uncommitted): keepAlive path spawns a song-end watcher
  (0.5 s poll, exits on Stop/phase change). At audio-clock end
  (`timeLength-timePosition<=0.25`, unpaused) it calls the ONE allowlisted
  `t21.endSong(true)` at game identity: local results screen, then
  `phase="ended"`, `stage="ended-results"` — results stay up until the
  user's Stop. Failure -> fallback full stop (`ended-fallback-stop`).
  Stop refuses only during transient `preparing`/`finishing`. Audio-free
  plays have no clock end: Stop-only, unchanged.
- `player_windui` (uncommitted): finish poller notifies "Finished — results
  on screen" when the report flips to `ended-results`. No `endSong` in UI.
- Boundary tests updated (endSong allowlist: one resolve site, one
  `endFn(true)` site, never createResults, clock-gated): all suites green
  (core/windui HELD, osu 4/4, escape 2/2, synth 7/7, tap harness HELD).
- Deployed to workspace (core + windui). Live test needs a FULL 146 s song
  (>MCP 120 s window), so it runs via the user's UI, not via executor call.
- Workspace cleanup done (user-approved): test charts deleted (Camp, synth,
  easy_001 — Ievan kept; Ievan chart backed up to
  `fixtures/converted/`), all recon/probe/savedecomp/verify/decomp-save
  `.lua` removed. Deployed player files + Charts/Ievan + Audio/mp3 kept.
- UI boot for user testing (PID 17616, `afn_player_windui.lua`): `boot
  gen=1`, 4 charts, `player_core 1.3.0 ready`. Default select is Camp
  (audio-free, file missing); picking the Ievan chart auto-matches its mp3.
- Boot splash (user request): native `AFN-Loading` ScreenGui in PlayerGui
  with status lines (library -> window -> charts -> core), destroyed on
  ready and on every abort path; re-exec cleanup removes strays. Boundary
  test covers order + teardown (HELD). Needs a UI file re-execution to be
  seen live.
- First UI Play failed at `loadSong-found` with an idle engine; the second
  press (no rejoin, nothing else) played fully (948 notes + audio, clean
  Stop). Verdict: one-off locator flake in the getgc/debug.info scan, not
  engine state — proven by 5/5 read-only preflights passing right after
  (49–198 ms scan time). Fix: `findFnByLine` retries 3x (reads only) and
  records `locator-attempts`; boundary test extended, still HELD;
  workspace core redeployed (running UI still holds the pre-fix table
  until the file is re-executed).
- External AI review triaged (no files changed by reviewer): accepted and
  done now = README status reconciled with HANDOFF/ROADMAP (replay, UI
  play, hits all user-verified; results screen pending) + converter input
  hardening (garbage Mode/CircleSize refused cleanly, skipped rows counted
  and reported; new offline test, suite now 5/5). Deferred with reasons =
  per-mechanic live tests + multi-BPM conversion (need live engine work,
  stay in ROADMAP §5/§6), large-chart limits (Ievan-size loads fine;
  premature), engine-internals reliance (already gated by preflight;
  nothing actionable).
- Mechanics unblocked from source (no live calls): `mapBPMChanges` reads
  top-level `bpmChanges`; SV reads top-level `sliderVelocities` behind the
  client `SVChanges` flag (live true) — prior `song.SVChanges` was inert,
  so every play so far ran SV-free. Converter emits both (tests 6/6);
  SOUND ARCHITECT (4659 rows / 865 holds / 30 SV / 32 BPM changes /
  9.1 MB audio) converted + staged in workspace for the combined live
  case. Isolated BPM/SV/sustain checks proposed, awaiting approval.
- Converter-fault audit (user's question — verdict: NOT the converter):
  SOUND ARCHITECT output vs `.osu`: times verbatim ms, lanes standard,
  zero exact duplicates (song-wide), zero same-lane overlaps (song-wide),
  SV/BPM values exact per live checks; sole transform is the documented
  sub-step clamp (<=10 ms, warned). Output is a faithful transcription.
- Video forensics (4.6 s clip, 60 fps, autoplay MFC): the 0:37 green bar
  aligns with the 37196/728 ms lane-6 hold under a long spawn lead
  (spawn lead = noteSpawnTime/|SV| shows notes seconds early) — consistent
  with normal early-spawn rendering, not a phantom. "Future section"
  feeling matches spawn lead directly. Proposed discriminator: SV-stripped
  diagnostic copy (awaiting user ok).
- SV discriminator DONE (user): glitch stays without SVs — scroll math
  acquitted. BPM-mirror discriminator DONE (user): positions CORRECT with
  empty map (just choppy; botplay fine) — tempo machinery implicated for
  placement. Both temp files deleted after verdicts.
- MathFuncs decompiled live (`Other.MathFuncs`): `getYPosAt` =
  `(CurrentTrackPos - initialPos)` (SV map) or `(SongPosition - pos) ×
  speed` (no SV) — NO bpm input anywhere in Y math; `getSusLength` same.
  Every positional code path is map-clean, yet misplacement correlates
  with the map. Standing confound: was the NOBPM run WITH audio? NOBPM
  can't auto-match the mp3 — audio-free (uniform free-run clock) vs
  audio-driven full chart (SongPlayer clock + correction snaps) could
  explain it WITHOUT the map. Asked user; decisive 2x2 pending.
- CONFOUND CONFIRMED (user): NOBPM ran AUDIO-FREE. The "BPM map" verdict
  is VOID — the isolated variable was the audio clock, not the map.
  Mechanism now favored: audio-driven conductor follows the AudioPlayer
  clock (update() blends toward discrete TimePosition reads); free-run is
  uniform. Note the complaint window MOVED between reports (50–70 s, then
  41–47 s) — weak section-lock, consistent with a systemic clock cause.
  Decisive test proposed: FULL chart audio-free (same notes+maps, silent
  clock). If correct -> audio clock; if misplaced -> map for real.
- User console log (NOBPM run): audio-free + autoplay, full 6259-note
  content, load/start clean — then a 5.3-MINUTE run ending in a clean
  `stopped` (12:10 -> 12:15). Long-session stability datapoint: no errors,
  teardown complete. NOBPM file has since been deleted (user later hit
  "file does not exist" trying to replay it — restore on request, though
  the decisive test needs only the full chart + "(no audio)").
- Reference note (user pointed at both): `GakuranChart.lua` stays the
  architectural reference (studied, read-only). `FunkyChart.lua` is a
  112-byte HTTP loader stub with no logic — not usable as a reference
  (fetching its remote payload would also break local-only rules); the
  `.osz` maps in its folder ARE useful and already in use. Gakuran's
  `osu2gakuran` clamps SV to [0.1, 10] (no hold-clamp precedent); our map
  SVs (0.74–1.1) need no clamping, so no transform added.
- SOUND ARCHITECT issue triage (user: "BPM used as SV" + 50–70 s rendering
  glitch). Source verdicts: (1) scroll math is provably BPM-independent
  (positions flow only through the SV map; hold SEGMENT COUNT is the sole
  BPM-derived value) — the visible coupling is the map's own design (SVs
  mirror BPMs inversely at identical timestamps: 165/170=0.97 etc.,
  constant pixels-per-beat); (2) 50–70 s input is clean (402 rows, chords
  <=2, zero stacks, min gap 40 ms) — no data defect. REAL defect found
  adjacent: sub-step holds (`sus // StepCrochet == 0`) build zero segments
  and render as taps — 65 song-wide, 6 in-window. Fix: converter clamps
  sub-step holds up to one base step + warns (test 7/7); both workspace
  charts reconverted (stable filenames) + redeployed. Note: Ievan now
  carries 4 real SVs (previously inert) — scroll will feel slightly
  different there. Remaining glitch (if any beyond vanishing holds) needs
  a sharper symptom or screenshot — no sampling per user.
- One-time test autoplay (user-authorized 2026-10-13, NOT a standing
  feature): `opts.autoplay` flips the engine's own `t21.SetAutoplay`
  botplay flag (a pure local setter; the dev-gate guards only its hotkey),
  verified via `GetAutoplay`, reset to false in teardown so it never leaks
  into the next play. UI Toggle "Autoplay (test)", default off. Boundary
  tests cover the single set/reset sites. Treat any future autoplay
  request as a new exception, not precedent.
- LIVE MECHANIC VERDICT (PID 6604, one load of SOUND ARCHITECT, 3/3 PASS):
  BPM map = 32 entries, base 165, times/BPMs exact; SV table = 30 entries,
  values exact (SV ingests now); sustain chains present (800 heads in pool,
  sample R/col0 @3015 +454.5 ms x5 segments; pool holds 6259 entries =
  heads + segments). Stop clean, post pools 0, `stop.err` nil (cosmetic
  fix confirmed live).

## Session 9 (2026-10-14) — takeover (new agent), static re-baseline; NO live calls yet

- Read FOR_NEXT_AGENT.md (untracked, takeover prompt) + HANDOFF + ROADMAP in full.
- Repo state: master, 1 commit ahead of origin (`eb92c26`); uncommitted:
  HANDOFF/ROADMAP, converter, player_core, player_windui, 3 test files.
  Untracked: `.cursor/`, FOR_NEXT_AGENT.md, `_extract_afn.txt`, `_last30.txt`.
  Nothing committed or pushed this session (needs explicit user approval).
- Static suites re-run (offline, all green): player local-only HELD, windui
  local-only HELD, loader local-only HELD, osu_to_afn 7/7, chart_source_escape
  2/2, synth_a_fixture 7/7. Static evidence only — not runtime proof.
- Madium `runtime_status`: one client alive, PID 13152 (connected ~100 s at
  check time). Read-only call; no executor code run, no files written to the
  workspace.
- Next: static read of conductor / SongPlayer.update (audio-clock vs free-run)
  to sharpen the pending decisive test (FULL SOUND ARCHITECT, audio-free,
  autoplay, watch 41-47 s). Live test only with explicit user approval and a
  freshly resolved PID.
- Deploy check (read-only hashes): `src/player_core.lua` and
  `src/player_windui.lua` match workspace `afn_player_core.lua` /
  `afn_player_windui.lua` (SHA256). Workspace Charts = Ievan + SOUND ARCHITECT
  (reconverted 2026-10-13 15:33); Audio = both mp3s (SA 9,121,430 B). Workspace
  root also holds older files not covered above (afn_holds_forensics.txt,
  afn_rl_bot.lua, afn_chart_reader.lua, afn_d1-4.lua, afn_loader_windui.lua;
  dated Oct 9-12) — left untouched, not part of this player.
- STATIC FINDING (decompile only, NOT live-verified) — clock model for the
  Instrumental (non-Segments) audio path. `SongPlayer.update`
  (`experiments/decompiled/afn_decomp_SongPlayer.lua:882-918`) sets
  `timePosition = (os.clock() - _startTime) * speed`. The audio object's
  `TimePosition` is consulted only while `_appliedFix ~= 10`: first advance
  hard-snaps `_startTime` (905-908), the next <=9 blend 0.2 (909).
  `_appliedFix` is reset to 0 only in `Resume` / `ResumeSyncedWith` (831, 849).
  Client `updateConductor` (client decompile 9564-9582): `timePosition<=0` ->
  free-run `RawTimePosition + dt*rate`, else `Conductor.setSongPos(timePosition)`.
  `usesSplits` is set only in the Segments branch (SongPlayer 205), not ours.
  Implication: after ~10 audio advances the "audio-driven" conductor is a plain
  os.clock clock, so per-frame discrete audio reads at 41-47 s are NOT
  supported by the source. This WEAKENS the takeover's prime suspect. Real
  audio vs free-run differences left: startup snap/blend, and dt-accumulated
  (free-run) vs absolute os.clock (audio) under frame hitches. Live check that
  would settle it (read-only): `_appliedFix`, `_startTime`, audio TimePosition
  vs `Conductor.SongPosition` during an audio play.
- Re-confirmed by grep of the client decompile: `StepCrochet`/`Crochet` appear
  only in parse-time sustain build (7528/7531: segs = sus // StepCrochet,
  susEndTime = start + segs*StepCrochet), DecimalStep/beat hits (9989) and
  effect durations (9510). Per-frame sustain (10753-10820) has no StepCrochet
  reference. No live-BPM dependence in note/hold placement found — consistent
  with the earlier audit.
- 2x2 status (BPM map x audio): NOBPM+free-run = OK (user); FULL map+audio =
  BAD (user); FULL map+free-run = PENDING (decisive); NOBPM+audio = PENDING
  (needs manual Audio pick; stem auto-match won't fire).
- USER UPDATE (2026-10-14 ~12:30): the visual glitch actually STARTS between
  ~35 s and ~45 s (earlier reports said 41-47 s, before that 50-70 s; the
  window keeps shifting, so treat it as 35-45 s from here). User APPROVED the
  decisive live test (FULL SOUND ARCHITECT, audio-free, autoplay, watch that
  window) and asked that progress handoffs be kept current after every step.
  Test plan: resolve live PID via runtime_status -> read-only pre-snapshot ->
  boot `afn_player_windui.lua` (the one state-changing executor call) -> user
  presses Play with Audio = (no audio) + Autoplay on -> post-snapshot after
  Stop. One attempt; stop on first error.
- LIVE LOG (~12:40): pre-snapshot PID 13152 alive, PlaceId 13042495892, console
  empty. Booted `afn_player_windui.lua` (gen=2): "UI ready", "player_core 1.3.0
  ready", 2 charts found, audio auto-picked for Ievan. I issued NO Play and ran
  no other state-changing call. The test was superseded when the user came back
  at ~19:20 with a Rayfield edition (below) and the same symptom.
- USER (2026-10-14 19:24): pasted `afn_rayfield.lua` (single-file Rayfield UI +
  the same player_core 1.3.0 play path; workspace copy 53,524 B, 12:50) and the
  converter. Ievan still fine, SOUND ARCHITECT still shows the "section bug".
  Same play path => same symptom expected; UI swap is not the variable.
  Settings.json: offsetMs=0, autoplay=true (offset ruled out; note the Rayfield
  edition shifts note rows by offsetMs but NOT bpmChanges/sliderVelocities).
- OFFLINE CHART ANALYSIS (read-only, deployed JSONs, 2026-10-14):
  Ievan: 948 rows, 0 holds, base 119, **0 BPM changes**, 4 SV all x1.0 (16.4,
  48.2, 97.1, 128.8 s) -> never exercises the BPM-change path.
  SOUND ARCHITECT: 4659 rows, 865 holds, base 165, 32 BPM changes, 30 SV.
  **First BPM change AND first SV are both at 40.8 s** (170 BPM / x0.97), then
  43.7 (175/0.94), 46.4 (180/0.92), 49.1 (185/0.89); then 185 BPM until 126.9 s.
  SV multiplier == 165/bpm (2 dp) everywhere checked (osu compensation SVs).
  The user's glitch window (35-45 s now; earlier 41-47 s) matches this first
  ramp; pre-roll look-ahead explains onset a few s before 40.8. Rows sorted, 0
  same-lane hold overlaps, max 3 simultaneous holds (227.5 s), 65 clamped
  holds, 2209 hold segments total; hold density at 35-50 s is LOW (3-10 holds
  per 5 s) so hold density is not what differs there.
- STATIC (decompile): `Conductor.mapBPMChanges`
  (`afn_decomp_Conductor.lua:119-139`) sets `stepTime = startTime /
  t.StepCrochet` with the BASE StepCrochet for every entry (not accumulated), so
  step numbering is inconsistent after the first change (e.g. entry at 126.9 s:
  stepTime ~1395.9 vs ~1505 accumulated). Consumers: TimeFunctions step/beat
  conversion (quant skin line 9206, stacked-note dedup 7876), runtime
  `changeBPM` (9958-9992). Re-grep incl. lowercase aliases (`stepCrochet`,
  `crochet`, `bpm`): only 3899, 7969 (section builder), 14768/14804 (beat-timed
  tweens). Still NO placement math using BPM found -> mechanism UNEXPLAINED.
- HYPOTHESIS (unproven): BPM-change path is the trigger, not the audio clock
  (audio is not consulted mid-song per session-9 clock finding, so it cannot
  start a glitch at 40.8 s). Earlier SV-stripped test kept bpmChanges and still
  glitched; earlier NOBPM test was audio-free. Cheapest discriminators:
  (A) SA with `bpmChanges=[]`, SV intact, audio ON; (B) FULL SA audio-free.
  A correct => BPM changes guilty (audio+SV exonerated). Candidate mitigation if
  confirmed: converter option to omit `bpmChanges` (positions are absolute-ms
  rows; only beat-synced visuals/quant colours lose BPM sync).
  Variant charts need user OK (user had earlier test charts deleted).

- LIVE EVIDENCE (2026-10-14 ~19:38, PID 21716, read-only: console tail + one getgc
  read of the Conductor): user feared the NOBPM chart "ran the BPM one" because
  the log said `Loading: afn_sound_architect_harmonic_bliss`. WRONG READING: the
  NOBPM file (`afn_sound_architect_NOBPM.chart.json`, made 19:32 by a script run
  on the client, bpmChanges 32->0, 4659 rows, 865 holds, SV 30 kept) keeps
  `song.song = afn_sound_architect_harmonic_bliss`, and `Loading:`/`song=` print
  that id, not the file name. Proof NOBPM ran: (1) the 3 plays after `Chart
  loaded: ..._NOBPM.chart.json` all show `audio=none(free-run)` (audio
  auto-match is by FILE STEM; the full file auto-picks its mp3, NOBPM has none);
  (2) live `Conductor.BPMChangeMap` has 0 entries, BaseBPM 165 after the last play.
  Timeline (console epoch): 16286 FULL chart + mp3 + autoplay, stopped after
  ~73 s (user: glitch started ~30-40 s) = the known-bad combo; Ievan + mp3 played
  to results (fine); 17132 NOBPM written; `Already playing` at 17162 = Ievan's
  results screen still up (`playing` stays true until Stop); then 3 NOBPM plays,
  audio-free, SV on, autoplay on, lasting ~14 s, ~45 s, ~2.7 s.
  OPEN: did the glitch appear in the ~45 s NOBPM audio-free play? Yes => BPM
  changes AND audio are exonerated; suspects become the 30 SVs (first also at
  40.8 s) or chart content; run NOBPM+NOSV next. No => BPM changes are the cause.
  Tooling traps: log shows song id not file name (give variants a distinct
  `song.song`, or print the file name); NOBPM needs the mp3 picked manually in
  the Audio dropdown if audio is wanted; press Stop before switching charts
  after a results screen.

## Save protocol

Sessions can end abruptly. After every meaningful step, update this file and
`ROADMAP.md`. Do not commit unless the user explicitly approves. Never claim a
runtime result without a live observation behind it. Every live claim below
cites the probe or test that produced it.

## Current state (session 1, 2026-10-12)

Independent repo at `Referencesandmods/AfternightCustomSongs` (local git, no
remote). Baseline commit `d825804`: 16 probes, synth fixture + offline test
(7/7), README, spike-status doc. Empty `src/` + `converters/` (no loader).

Target: Project Afternight, PlaceId `13042495892` (name "Ugc"). Executor:
Madium only. Server-cleanliness desired, not required. Chart schema frozen
only on the Gakuran side; Afternight format follows engine evidence.

## What the spike established (all read-only unless noted)

- Engine: FNF-style gameplay module, ~120 methods (`probe_c`). Native SV
  (`svFunctions`: `getPosFromTime`, `getPosFromTimeSV`, `getSVFromTime`,
  `getSpeed`, `mapVelocityChanges`, `sliderVelocities`) — `probe_d`.
- Notes live in `Notes` / `UnspawnedNotes` pools; `strumTime` in ms on the
  Conductor axis; lanes 0–7 (opponent 0–3 / player 4–7), `column` mirrors lane;
  sustains are segment chains (`isSustain`, `susLength`, `prevNote`,
  `totalSustains`) — `probe_n`, `probe_n2`.
- Native rows are `[timeMs, lane, sustainMs]`; sections carry
  `{id, mustHitSection, sectionNotes}` (`probe_h`).
- Conductor: `BPM`/`BaseBPM` = base tempo, `CurBPM` = live tempo, `Offset` in
  seconds, `BPMChangeMap` + tempo-change events (`probe_t`, `probe_s`).
- SV entries are `{startTime, multiplier}` — Quaver-identical shape
  (`probe_t`). Gakuran discovery shapes find nothing here.
- Caller evidence (`probe_i`): one orchestrator references `parseChart` +
  `addNotesFromChart` + `addSectionsFromChart` + `createNote`; `parseChart`
  does not reference the spawners in constants (but see correction below).
- `getinfo` line markers match Claude's decompile refs to the line
  (parseChart 5287, addNotesFromChart 5053, createNote 4761).
- Lane routing (from decompile model, matches all live data): lanes 4–7 +
  `mustHit=false` → player side R cols 0–3; lanes 4–7 + `mustHit=true` →
  opponent side L.

## Test history
- **Test A** (addNotesFromChart-only, idle): clean failure,
  `nil with 'KeyCount'`, zero state change. Verdict: missing strumline
  context, not schema rejection.
- **Test A2** (parse → sections → notes, wrapper `{song=chart}`):
  parseChart OK, built 8 Strums + 2 Strumlines; `addSectionsFromChart`
  rejected the wrapper (`nil.notes` — likely wants the song subtable);
  **4/4 notes created by parseChart itself** (timestamps/lanes unverified —
  sampler gated on stage 3, fixed next time). Pools + Conductor/SV restored
  and verified; strums/strumlines persist (userdata, unrestorable by hand).
- **Correction:** parseChart evidently spawns via an aliased internal call —
  constant cross-referencing misses localized calls. Caller evidence is
  necessary but not sufficient; trust staged observation over it.
- **Test B2-min (parse-only, direct) — PASS, 2026-10-12.** On a rejoined
  idle engine (pools 0/0/0/0): `parseChart(wrapper, {}, nil, nil)` ok, built
  8 Strums + 2 Strumlines and exactly 4 UnspawnedNotes — times
  1200/1800/2400/3000, rawLanes 4/5/6/7 → columns 0/1/2/3, dirs
  Left/Down/Up/Right, `side="R"` + `mustPress=true` on all four
  (player-side routing now LIVE-PROVEN, not model-inferred). Pools wiped to
  0/0 in place, Conductor numerics + BPM/SV maps restored and verified.
  Strums/strumlines persist (expected) → rejoin required before next test.
  The WindUI loader window from this session is stale: do NOT press its Run
  (would double-parse); rejoin instead.

## Pending right now

1. User rejoins the client (Test A2's strums persist; pristine idle needed).
2. Then **first live harness run** (`src/test_loader.lua`, staged uncommitted —
   see "Staged harness" below): Inspect/Preflight → one gated Run → Cleanup →
   rejoin. Pass = 4 notes R/0–3 @1200/1800/2400/3000; PARTIAL also acceptable
   as evidence (taps/time/columns without observable side field).
3. After taps verify: sustain test, SV test, BPM test (one mechanic each),
   then the `src/` adapter decision.

## Staged harness (session 2, 2026-10-12 — NOT executed, NOT committed)

- Source: user-supplied `afternight_test_loader.lua`, saved as
  `src/test_loader.lua` (SHA256-verified identical copy, plus one
  behavior-preserving fix: the deferred log-scroll now runs inside `pcall`
  so closing the UI before it fires cannot throw).
- Preserved core: exactly one `parser(wrapper, {}, nil, nil)` call site
  (verified by scan), wrapper byte-matching
  `fixtures/afn_synth_a_taps.chart.json` (id, bpm 200, keyCount/
  playerKeyCount 4, one `mustHitSection=false` section, rows
  1200/1800/2400/3000 lanes 4–7, events empty).
- Verified absent from executable code (comment/string mentions only): zero
  calls to `addNotesFromChart`, `addSectionsFromChart`, `startSong`,
  `endSong`, remotes, HTTP, `loadstring`, `require`. Native Roblox instances
  only; no UI library, no downloads. Preflight + test both PlaceId-gated to
  `13042495892`; single-attempt lockout (`state.ran`) per client session.
- Supersedes the old 3-stage B2: the forensic audit found B2 internally
  inconsistent (mixed `wrapper` vs `wrapper.song` args; `addNotesFromChart`
  after a spawning `parseChart` risks duplicates), so the harness runs
  parse-only (B2-min). `add_*` shapes remain separate future experiments.
- Cleanup reviewed: restores pools (identity-preserving), Conductor scalars,
  `BPMChangeMap`, `lastBPMChange`, `sliderVelocities`, with serialized
  verify; deliberately leaves Strums/Strumlines/Maps untouched and labels
  the residue EXPECTED/UNRESTORED. **Pool-clear is never a clean session —
  rejoin is mandatory and the UI says so at every stage.**
- Compat: `+=`, `getgc(true)`, `gethui` all previously evidenced live
  (`probe_n`-family, `probe_a`); `task.defer` is standard Roblox (UI-scroll
  only, now pcall-guarded); `Draggable` is deprecated-but-functional, left
  as-is. No fixes were needed beyond the defer guard.
- Standing: staged file + doc updates are uncommitted per instruction;
  Gakuran repo verified untouched (`git status` clean apart from its
  pre-existing untracked `experiments/`).
- Local-only boundary (session 2): server/persistence/score access is
  prevented by never invoking it, NOT by hooking the network (no
  getconnections/hookfunction anywhere in the harness). Codified in
  `tests/test_loader_local_only.py` — 37/37 checks pass: zero executable
  references to sendServerEvent/fireStageRemote/SongEvent/startSong/endSong/
  setSongData/SaveData/add_* /HTTP/loadstring/hook primitives; exactly one
  parser call site via safeGet. Static evidence only; the live run must
  still confirm transport/scores unchanged via snapshots.
- Loader prototype, half 1 (session 2, offline only): `converters/osu_to_afn.py`
  converts osu!mania to `{song:...}` wrappers (ms rows, lanes 4-7,
  mustHit=false, verbatim SV with last-wins, >4K fold, single-BPM with loud
  multi-red warning, no-overwrite outputs). `tests/test_osu_to_afn.py` 3/3.
  Timing math follows osu2gakuran (reference-only, reimplemented — no
  Gakuran imports). Half 2 (in-game file staging + inject) waits for the
  tap-test verdict. UI stays native: catalog libs (WindUI/Maclib/Rayfield/
  LinoriaLib) all require downloading external code, which violates the
  local-only rule, and multiply the Instance-touch surface that already
  throws on some executor threads.

## Standing rules

- Idle engine + pre/post snapshots for every state-changing call.
- One attempt per approval; stop on first error, no permutation sweeps.
- No `startSong` (server remote), no scores, no hooks, no files in game.
- GakuranCustomSongs (`../gakurancustomsongs`) is reference-only: never
  modify its production code, converters, charts, or outputs.
- Workspace probe files (`afn_probe_*`) cannot be deleted remotely (no
  `delfile`); they are inert and clearly named. Repo `experiments/` copies
  are canonical.


## Session 3 (2026-10-12) — full-play path recon (read-only, no state change)

- Decompile works from Madium: `decompile(Players.LocalPlayer.PlayerScripts.Client)` -> 502,401 bytes / 15,644 lines (it is a LocalScript). This supersedes "no game-code decompiler" under Known limits. Decompile line numbers differ from `debug.info` source lines: loadSong = decompile 12548 / source 8058; `LoadSong` listener = decompile 15194 / source 9840.
- `afn_recon4.lua` (executor workspace) ran live on an idle engine (t_7.loadedSong=false, inSong=false). loadSong upvalues: 3 = ENGINE `t_1`, 5 = STATE `t_7`, 6 = MODULE `t_21` (identical to the gc module; has startSong / beginCountdown / endSong). `t_1.songIds[ModName] = { Songs = { [songName] = { Audio = {...} } } }` (sample: "Super Funkin' Galaxy" -> "MAJOR BURROWS"). `t_1.ChartFixing` = { fixChart, fixEvents }. Conductor exposes setSongPos / changeBPM. SongPlayer exposes new / setPosition / Resume / etc.
- loadSong contract (read from decompile 12548-12960, NOT yet exercised live): `loadSong(arg325, side "L"|"R", rate, stageModel, t17, playerIdx, players, ?, ?)`.
  - `arg325.Chart`: ModuleScript whose `require()` returns a JSON *string*; it is JSONDecoded, then `ChartFixing.fixChart(result, Chart.Name)`. Chart.Name is the difficulty. loadSong re-parents Chart's children into a new Folder.
  - `arg325.Song`: Instance (Name, optional `DisplayName` attribute). `arg325.Mod`: Instance (Name, optional `Metadata` child module). `arg325.ModchartsEnabled` / `GimmicksEnabled` flags.
  - `t_1.songIds[Mod.Name].Songs` is indexed unguarded, and `SongInfo.Audio` is read -> the registry entry must exist first.
  - `t17` and `players` must be `{L={},R={}}`-shaped tables.
  - `stageModel` nil => v23 (singleplayer flag) false and `stageRemote` nil. Unverified whether the rest of loadSong tolerates a nil stage (cameras table `t_11`).
- Not yet read: decompile 12960+ (Events module, audio load from SoundInfo.Audio, camera/stage use, parseChart call, render-step bind), plus the `Start` listener / beginCountdown / startSong.
- Rule tension to resolve before any live run: Standing rules say "no startSong". The decompile suggests the server notification inside startSong is gated on v23, so with v23 false it may be skippable. Verify in the decompile before calling it.
- loadSong is far heavier than parseChart-only (disables PlayerControls and StageZones, builds HUD/camera, reparents instances). Treat every live attempt as rejoin-required.

## Session 4 (2026-10-12) — local-play contract closed, loader built (no live run yet)

All reads below are from decompile sources saved in
`experiments/decompiled/` (byte-exact via in-executor `decompile()` +
`writefile`, live client PID 15352, PlaceId 13042495892). Live claims cite
the recon script that produced them.

### Q-answers (read from source, then verified live where noted)
- **Q1 `add(nil)` — SAFE.** `afn_decomp_ScriptPack.lua:146-149`:
  `function t.add(t8, arg2, b1) if not arg2 then return end`.
  Every NoteGroup/ForcedModchart/Modchart lookup is a no-op.
- **Q2 asset fetch — CONFIRMED server-on-miss, mitigated.**
  `afn_decomp_AssetReplicator.lua:239-311`: container hit returns with no
  traffic; miss does `RequestEvent:FireServer` + yields up to 5 s.
  Live (`afn_recon6.lua`): `__AssetContainer/Ratings` holds ONLY
  "Afternight", no "Countdowns" category. Live settings
  (`afn_recon7.lua`): `JudgementStyle="Custom"`, `HideLobby=false`,
  `BackgroundDim=1`, `FakeOpponentInput=true`, `HideCharacters=false`.
  Mitigations in loader: `SkipCountdown=true` (skips BOTH Countdowns
  lookups: loadSong decompile 13247 + beginCountdown's) and pre-clone
  Ratings/Afternight -> Ratings/Custom (cache hit, removed on teardown).
- **Q3 map block — NO-OP for these settings.** Else-branch taken
  (`MapService.Stage=nil`), no map calls. Loader still gates
  `HideLobby==false` + `BackgroundDim>0.05` and aborts otherwise.
- **Q4 fireServer — NOT wrapped** (no explicit approval; rule ambiguity
  stands). Residual: `CharReplicator.SetSettings` fires "UpdPreferences"+
  "Sync" ONCE when `loadStageCharacters` flips true->false (live t_2 read
  in `afn_recon7.lua`; left flipped, next real loadSong repairs it).
  `PlayerDeath`/`PlayerReset` only on death/reset/hitch — accepted, no
  death expected (4 misses, GhostTapping=true).
- **Q5 stop — `abruptGameEnd` via `getfenv(loadSong)`.**
  `afn_recon6.lua`: `getfenv(loadSong)` resolves; `abruptGameEnd`,
  `clearUp`, `beginCountdown`, `onUpdate` all functions. `endSong` is NOT
  a server path (body = createResults + clearUp, no remotes) but stays
  unused. Audio-free plays never self-terminate (decompile 11269 needs
  `not v90.paused`); loader stops via abruptGameEnd after ~3 s observe.
- **Q6 audio — audio-free first.** `SoundInfo=nil` => `v90:load` skipped
  => `Resume()` early-returns (`curAudio==nil`) => Conductor free-run
  branch (`updateConductor`, decompile 9564). `_CachedAudio=30` attribute
  on the Chart keeps timebar math sane.
- **New, not in prior summary:**
  - `NetworkFunctions.fireStageRemote*` nil-guard at source top
    (`afn_decomp_NetworkFunctions.lua`); `stageRemote` written once
    (loadSong, `v20 and FindFirstChild("Hits") or nil`); live nil.
  - `LoadingScreen.start` (afn_decomp_Loading.lua:170-174) Invokes
    `GetPreviewOverheadData` per non-bot side. Mitigation: pre-flip
    `enterLoadingState({Sides={L={},R={}}})` (v85 guard shared with
    `leaveLoadingState`, decompile 791-815) so loadSong's call returns
    early. Teardown always calls `leaveLoadingState` (no-op if already).
  - `CharacterModule.new` -> `LoadAnim` -> `Replicate("LoadAnim")` fires
    `Main.Character:FireServer` (afn_decomp_Character.lua:955-966,
    1331-1344). `Main.Character` used NOWHERE else (grep: 1 site).
    Mitigation: relocate it to a temp folder during the run, restore +
    verify in teardown.
  - Emote char (`t_245`) carries NO remote => its Replicate calls no-op.
  - `DescriptionReady=true` live — no unbounded wait.
  - `getfenv`/`debug.setupvalue` available; v963==false live (clean).
  - `getBotAppearance(getRandomFriend())` for the emote char is UNREAD —
    accepted risk (platform API, not game server), noted for the run.

### Built (session 4) — first live run GREEN (see ROADMAP §7)
- `src/player_loader.lua` was the one-shot smoke (now a thin wrapper).
- Live fixes: require-wrap for executor ModuleScripts; identity 2 for HUD.
- Decompile evidence in `experiments/decompiled/` (9 modules).

## Session 5 (2026-10-12) — WindUI player panel

Continued from Muse Spark / Claude handoff: put the full-play loader into
the vendored WindUI library UI with a local chart picker.

### Built (uncommitted)
- `src/player_core.lua` — callable API: `preflight()`, `play(opts)`,
  `stop()`, `normalizeChart()`. `keepAlive=true` leaves the song running
  until Stop; default smoke path observes ~3s then tears down. Accepts
  engine wrappers `{song:{...}}` and flat `{notes:[{time_ms,lane,hold_len}]}`.
- `src/player_loader.lua` — thin one-shot: reads `afn_player_core.lua`,
  plays synth fixture, `_G.AFNPlayerRan` lockout.
- `src/player_windui.lua` — WindUI window (Gakuran-style §0 / §0.5 only):
  capability check, re-exec cleanup, Tab **Play** with Chart dropdown
  (scans `AfternightCustomSongs/Charts`), Refresh / Preflight / Play /
  Stop. Play calls `core.play({keepAlive=true})`. Vendor = local
  `afn_windui.lua` (AFN-P1/P2/P3); the current player configuration does not
  enable the vendor's dormant HTTP-fetch, key-system or remote-asset paths.
  This is configuration-specific, not a blanket vendor guarantee.
- Charts staged in Madium workspace
  `AfternightCustomSongs/Charts/`:
  `afn_synth_a_taps.chart.json`, `easy_001.chart.json`,
  `afn_camp_hard_2_35_3_14_normal.chart.json` (from Camp .osu via
  `converters/osu_to_afn.py`). 2FAR .osu has no hit objects (skipped).
- Tests: `test_player_local_only.py` HELD (core + thin loader);
  `test_player_windui_local_only.py` HELD; tap harness still HELD.

### Deploy (Madium Workspace)
- `afn_player_core.lua`, `afn_player_loader.lua`, `afn_player_windui.lua`,
  `afn_windui.lua` (vendor).

### How to run
1. Rejoin Afternight (clean idle — no strum residue from prior plays).
2. `madium.run_executor_file` → `afn_player_windui.lua` (pid of client).
3. Preflight → pick chart → Play → hit notes → Stop → rejoin.

### Live this session (PID 15352)
- `afn_player_windui.lua` boot OK: `[AFN-PlayerUI] UI ready`, PlaceId
  13042495892, `Charts found: 3`, `player_core 1.1.0 ready`, dropdown
  selected `afn_camp_hard_2_35_3_14_normal.chart.json`.
- Play/Stop of a picked chart: not clicked yet this session (rejoin if
  prior strum residue; session 4 already proved core play on synth).

### Hardening (review patch, same day)
- Chart ModuleScript source uses `string.format("%q", chartJson)` (no
  fixed `[=[` embedding). Offline adversarial escape test added.
- Play teardown is transactional: cleanup `ctx` registered before the
  first mutation; per-resource retryable steps; Stop refused while
  `phase=="preparing"`; incomplete cleanup retains `ctx` for retry.
- Docs/ROADMAP clarify non-invocation vs strict network silence.
- Converter: same-timestamp red timing points keep file order.

### Live Madium test (PID 26420, after hardening commit `5431890`)
- Fresh idle: PlaceId 13042495892, pools 0/0/0/0, `DescriptionReady`.
- WindUI boot OK: 3 charts, `player_core 1.1.0 ready`.
- Programmatic `core.play` synth wrapper, `keepAlive=false`, observe 3s:
  `load_ok` / `start_ok`; after load UnspawnedNotes=4 Strums=8
  Strumlines=2; Conductor YES (-92 → 2422 ms); note0 R/col0 @1200
  mustPress; stage `done-cleaned`; every teardown step `ok`
  (abruptGameEnd, leaveLoadingState, require, charRemote, ratings,
  registry, holder); `playing_after=false`.
- Live `%q` adversarial payload with `]=]` in song title: loadstring
  round-trip OK (`return "` form).
- Post-teardown pools observed 0/0/0/0 and residue preflight passed
  this run (unlike earlier sessions that required rejoin for strum
  residue). Do not yet treat same-session replay as a guaranteed
  workflow; hit/judgement via UI still unverified.
