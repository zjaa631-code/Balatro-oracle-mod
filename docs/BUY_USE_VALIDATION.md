# 0.8.2 — native buy-and-use validation boundary

## Report and cause

The user's 2026-09-14 19:17 screenshot shows `oracle_prediction_unavailable` on an Uncommon Tag in a new Blue Deck / White Stake run. The Lovely log immediately before this reports `MISMATCH consumable:c_wheel_of_fortune` at Ante 2 in seed U9WGYUR5.

The saved diagnostic shows identical Joker (Gros Michel), Foil edition, and all keyed RNG states. Only money differs: expected 0, actual -3. The consumable validator counted the $3 purchase as an effect of Wheel. Its session-wide mismatch protection then correctly refused further predictions, including the new run's Tag tooltip. No seed mapping or Tag rarity change is required.

## Native call order and fix

Audited installed Lovely dump of `functions/button_callbacks.lua`, `functions/common_events.lua`, and `card.lua` (Balatro 1.0.1o-FULL / Steamodded 26.829.0 / Lovely 0.9.0):

1. `buy_from_shop` enqueues a callback which calls `ease_dollars(-c1.cost)`.
2. `ease_dollars` with no instant argument queues the actual balance update.
3. The same purchase callback synchronously invokes `G.FUNCS.use_card` for `buy_and_use`.
4. `Card:use_consumeable` runs before the payment callback; its deferred effects run after payment.

The validation wrapper carries the explicit `buy_and_use` card and cost through this synchronous call only. Its copied action state accounts for the already queued purchase before forecasting and observing use effects. Hermit and Wraith therefore also use the correct post-purchase balance. Inventory and pack usage do not receive a price adjustment. Scope is restored on success or exceptions; original arguments, nil-containing returns and errors are preserved. The native functions are each called exactly once; no gameplay event, balance, card or RNG is modified for prediction.

Real mismatches still disable forecasts for the session. We do not clear a fault on new run or suppress money validation. Restart after upgrading to replace the old wrappers and clear the old false alarm.

## Regression

Added extraction of the installed native `buy_from_shop` and `ease_dollars` implementations. Regression runs them with the existing native consumable implementation; rendering and event clock are stubbed. Four seeds (including U9WGYUR5), five consumables (Wheel, Hermit, Wraith, Temperance, Judgement) and costs 0/1/3/6 provide 80 purchase/use scenarios. Each compares effects and all keyed RNG, checks settled dollars, then requests Uncommon Tag prediction. Additional wrapper tests cover arguments, nil returns, exceptions and ordinary-use scope. Existing injected effect mismatches must still close the prediction gate.

Targeted suite: 12 consumable test groups, 1,287 native use scenarios passed. Full regression results accompany this release separately. A native-function regression is not a claim of a new manually played run.
