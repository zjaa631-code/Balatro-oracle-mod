# 0.9.0 — expansion Phase 2: conditional Joker triggers

## Scope and source truth

Balatro 1.0.1o-FULL, Steamodded 26.829.0, Lovely 0.9.0. Audited the installed patched `Card:calculate_joker`, `Card:get_chip_mult`, `Card:get_p_dollars`, the four `reset_*` helpers, SMODS Glass enhancement, `SMODS.get_probability_vars`, `SMODS.pseudorandom_probability`, `SMODS.poll_seal`, and existing native creation/pool functions. Source is extracted locally for tests, not distributed. No Showman implementation was copied; its previously audited live-global approach remains unsuitable for Oracle.

The new `prediction/jokers.lua` adapter is registered in the existing prediction engine. Input is detached data; output is a next-qualified-trigger result. Both probability checks on Lucky are sampled: Money and Mult are not mutually exclusive. Probabilities use current `G.GAME.probabilities.normal`; native Oops context multiplication and the utility divisor cancel, as in the consumable adapter. Debuffed action cards and cards currently being sliced are rejected; global reset functions remain applicable even when the corresponding owned Joker is debuffed.

| Effect | Native RNG keys / call path |
| --- | --- |
| Space / Gros Michel / Cavendish | `space`, `gros_michel`, `cavendish` |
| Bloodstone / Business / Reserved Parking | `bloodstone`, `business`, `parking` |
| 8 Ball / Hallucination | `8ball`, `halu<ante>`; successful creation uses `8ba`, `hal` |
| Lucky / Glass | `lucky_mult`, `lucky_money`, `glass` |
| Misprint | integer `misprint` between current ability min/max |
| Invisible / Perkeo / Madness | `invisible`, `perkeo`, `madness` over current eligible objects |
| To Do List | `to_do`, visible hands excluding current target |
| Idol / Mail / Ancient / Castle | `idol<ante>`, `mail<ante>`, `anc<ante>`, `cas<ante>` |
| Riff-raff / Cartomancer | Common Joker creation `rif`, Tarot creation `car` |
| Sixth Sense / Vagabond / Superposition / Seance | creation append `sixth`, `vag`, `sup`, `sea` |
| Marble / Certificate | `marb_fr`, `cert_fr`; Certificate guaranteed seal `certsl` |

Current source contains no separate random roll for Lucky Cat or Hit the Road. Conditions such as an 8 scoring, a qualifying Straight, a non-Boss Blind for Madness, available consumable space, and Invisible readiness are explicit. Generators use actual buffers, limits and native pool exclusions; Riff-raff's callback fixes its count before the loop and each created Joker joins the owned pool. Invisible excludes itself and strips Negative on its copy; Perkeo creates a Negative copy. Madness excludes Eternal and already sliced targets. Native `pseudorandom_element` sorts Card candidates by `sort_id`; Oracle preserves that behavior rather than assuming displayed Joker order equals sampling order.

Idol, Mail and Castle retain each eligible physical card, so repeated ranks/suits carry their native multiplicity. Stone cards are excluded; empty-pool fallback preserves the native retained fields. Ancient excludes its current suit using the native four-suit ordering. Hidden hands enter To Do only when currently visible. Reset UI explicitly chooses current or next Ante; no unproven future deck or future hand history is fabricated.

## What the result promises

One qualified invocation, using the exact current RNG and relevant pools. Not a whole hand, retrigger chain, end-of-round timeline, or Blueprint/Brainstorm ordering solver. Earlier calls on the same stream can change the result. The UI states this next to the native card preview and marks every new forecast Experimental. Creation after a conditional check assumes no intervening relevant RNG or pool change before its callback. Current state is reread when opening or switching the page; data signatures invalidate cached previews after changes.

The output includes generated cards, direct random targets, reset targets, check results and Misprint's multiplier. It does not claim to apply every downstream Joker reaction to a reusable future branch; that belongs to subsequent deck/branch phases. No automated play or choice is performed.

## Actual-call validation

`debug/joker_validator.lua` verifies actual native probability calls, target draws, reset helper results, Misprint values, generation calls and Certificate seals against independent predictions. Target validation captures keyed RNG immediately before native `pseudoseed`, then detaches the actual selection pool before the native draw. It never calls a live RNG for a preview. Original functions are invoked once for gameplay; reset wrappers preserve nil-containing return tuples. Validation records include seed, Ante, input, relevant pool/owned cards, RNG trace and before/after keyed state. Mismatches retain the existing session-wide fail-closed behavior.

Probability validation uses a small data snapshot rather than reconstructing all shop pools for each scoring roll. No full forecasts run every frame. Actual-call validation is controlled by the existing developer validation setting.

These actual-call comparisons verify the immediate invocation; they must not be presented as validation of an entire earlier conditional turn prediction. The native multi-seed tests separately verify that the page's candidate/eligibility construction matches each native trigger context.

## Tests

`tests/run.py --jokers` includes prior phases; `--jokers-only` loads prior fixtures and runs the new suite. Both execute the installed game's LuaJIT DLL. Native source hashes and test provenance are in the generated report.

The focused suite passes seven groups / 1,720 native trigger scenarios: probability checks across 80 seeds and probability multipliers; 320 reset cases including empty/Stone decks; 350 selection, copy, front/seal and multiplier cases; 240 creation/buffer cases; plus readiness/Oops/hidden-hand edges. Each forecast checks input immutability and live keyed/global RNG preservation before comparing native outcomes and final keyed RNG. Tests inject wrong probabilities, choices and stickers and require validation failures. Native UI constructors exercise caching and RNG refresh. Rendering, sound and the event clock are stubbed in native-function regressions; real-game UI checks are reported separately.
