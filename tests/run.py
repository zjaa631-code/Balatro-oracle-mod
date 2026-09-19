"""Run against the installed game's actual LuaJIT DLL; no pip dependencies.

python tests/run.py --game-dir "D:/steam/steamapps/common/Balatro"
Native source stays in a temporary directory, never in the deliverable.
"""
import argparse
import ctypes
import json
import os
import sys
from pathlib import Path
import tempfile
import zipfile
import hashlib
import time

sys.dont_write_bytecode = True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--game-dir", type=Path, required=True)
    parser.add_argument("--phase2", action="store_true")
    parser.add_argument("--phase3", action="store_true")
    parser.add_argument("--phase4", action="store_true")
    parser.add_argument("--phase5", action="store_true")
    parser.add_argument("--phase6", action="store_true")
    parser.add_argument("--phase7", action="store_true")
    parser.add_argument("--consumables", action="store_true", help="Consumable native-use regression, includes prior phases")
    parser.add_argument("--jokers", action="store_true", help="Native Joker trigger regression including prior phases")
    parser.add_argument("--jokers-only", action="store_true", help="Development: load prior fixtures, test Joker triggers")
    parser.add_argument("--pack-opening-only", action="store_true", help="Development: native pack event scheduling with prior fixtures")
    parser.add_argument("--deck-state", action="store_true", help="Detached consumable deck regression plus all prior phases")
    parser.add_argument("--deck-state-only", action="store_true", help="Development: only detached consumable deck tests")
    parser.add_argument("--bosses", action="store_true", help="Boss rule native regression plus all prior phases")
    parser.add_argument("--bosses-only", action="store_true", help="Development: Boss rule tests with prior fixtures")
    parser.add_argument("--card-insight", action="store_true", help="Hook discard and face-down identity native tests")
    parser.add_argument("--quick-preview", action="store_true", help="Hover preview integration and cache regression")
    parser.add_argument("--event-depth", action="store_true", help="Sequential native probability checks and single-result hover regression")
    parser.add_argument("--undo", action="store_true", help="Native save checkpoints, persistence and rollback lifecycle tests")
    parser.add_argument("--consumables-only", action="store_true", help="Development: retain prior fixtures, run consumable tests only")
    parser.add_argument("--tag-rewards", action="store_true", help="Pack and Top-up Tag tests, including prior modules")
    parser.add_argument("--tag-rewards-only", action="store_true", help="Development: run reward tags with prior fixtures")
    parser.add_argument("--stress", action="store_true", help="Expand deterministic seed sweeps (implies Phase 7)")
    parser.add_argument("--seed-start", type=int, default=1, help="Starting index for deterministic seed sweeps")
    parser.add_argument("--report", type=Path, help="Write provenance, duration and failure context as JSON")
    parser.add_argument("--tags", action="store_true")
    parser.add_argument("--tag-chains", action="store_true")
    parser.add_argument("--fast", action="store_true", help="Skip Phase 2 tests, retaining their fixtures")
    parser.add_argument("--patched-dir", type=Path)
    parser.add_argument("--smods-dir", type=Path)
    args = parser.parse_args()
    if args.pack_opening_only:
        args.jokers_only = True
    if args.event_depth:
        args.jokers = True
        args.quick_preview = True
    if args.quick_preview:
        args.consumables = True
    if args.card_insight:
        args.phase2 = True
    if args.bosses_only:
        args.bosses = True
        args.jokers_only = True
    if args.bosses:
        args.deck_state = True
    if args.deck_state_only:
        args.deck_state = True
        args.jokers_only = True
    if args.deck_state:
        args.jokers = True
    if args.jokers_only:
        args.jokers = True
        args.fast = True
    if args.jokers:
        args.tag_rewards = True
    if args.tag_rewards_only:
        args.tag_rewards = True
        args.fast = True
    if args.tag_rewards:
        args.consumables = True
    if args.consumables_only:
        args.consumables = True
        args.fast = True
    if args.seed_start < 1:
        parser.error("--seed-start must be positive")
    if args.stress:
        args.phase7 = True
    if args.phase7:
        args.phase6 = True
    if args.consumables:
        args.phase7 = True
        args.phase6 = True
    if args.phase6:
        args.tag_chains = True
    if args.tag_chains:
        args.tags = True
    if args.tags:
        args.phase5 = True
    if args.phase5:
        args.phase4 = True
    root = Path(__file__).resolve().parents[1]
    started = time.perf_counter()
    report = {"status": "RUNNING", "phase7": args.phase7, "stress": args.stress,
              "jokers": args.jokers, "jokers_only": args.jokers_only, "deck_state": args.deck_state,
              "bosses": args.bosses, "bosses_only": args.bosses_only,
              "card_insight": args.card_insight,
              "quick_preview": args.quick_preview,
              "event_depth": args.event_depth,
              "undo": args.undo,
              "consumables": args.consumables, "consumables_only": args.consumables_only,
              "tag_rewards": args.tag_rewards, "tag_rewards_only": args.tag_rewards_only,
              "phase2_skipped": args.fast, "seed_start": args.seed_start,
              "sha256": {}, "samples": {"shop": 1000, "packs": 300, "tags": 300,
                                         "chains": 100, "rng": 1000} if args.stress else {}}
    dll_dir = os.add_dll_directory(str(args.game_dir.resolve()))
    lua = ctypes.CDLL(str(args.game_dir / "lua51.dll"))
    # LuaJIT's legacy LoadLibrary does not use add_dll_directory for dependencies.
    # Preload through Python's modern loader before testing real LOVE data APIs.
    love_native = ctypes.CDLL(str(args.game_dir / "love.dll")) if args.undo else None
    lua.luaL_newstate.restype = ctypes.c_void_p
    lua.luaL_openlibs.argtypes = [ctypes.c_void_p]
    lua.luaL_loadstring.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
    lua.lua_pcall.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int]
    lua.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
    lua.lua_tolstring.restype = ctypes.c_char_p
    lua.lua_close.argtypes = [ctypes.c_void_p]
    state = lua.luaL_newstate()
    lua.luaL_openlibs(state)
    with tempfile.TemporaryDirectory(prefix="oracle-test-") as temp:
        with zipfile.ZipFile(args.game_dir / "Balatro.exe") as archive:
            for name in ("functions/UI_definitions.lua",):
                archive.extract(name, temp)
            if args.undo:
                if not args.patched_dir:
                    parser.error("--undo requires --patched-dir")
                from source_truth import prepare_undo
                prepare_undo(archive, args.patched_dir, temp)
            if args.phase2 or args.phase3 or args.phase4:
                if not args.patched_dir or not args.smods_dir:
                    parser.error("--phase2 requires --patched-dir and --smods-dir")
                from source_truth import prepare
                prepare(archive, args.patched_dir, args.smods_dir, temp)
                if args.quick_preview:
                    from source_truth import prepare_quick_preview
                    prepare_quick_preview(archive, args.patched_dir, temp)
                if args.card_insight:
                    from source_truth import prepare_card_insight
                    prepare_card_insight(args.patched_dir, temp)
                if args.phase3 or args.phase4:
                    from source_truth import prepare_shop
                    prepare_shop(archive, args.patched_dir, args.smods_dir, temp)
                if args.phase4:
                    from source_truth import prepare_packs
                    prepare_packs(args.patched_dir, args.smods_dir, temp)
                if args.phase5:
                    from source_truth import prepare_deck
                    prepare_deck(args.patched_dir, temp)
                if args.tags:
                    from source_truth import prepare_tags
                    prepare_tags(args.patched_dir, args.smods_dir, temp)
                if args.tag_chains:
                    from source_truth import prepare_tag_chains
                    prepare_tag_chains(args.patched_dir, args.smods_dir, temp)
                if args.consumables:
                    from source_truth import prepare_consumables
                    prepare_consumables(args.patched_dir, args.smods_dir, temp)
                if args.jokers:
                    from source_truth import prepare_jokers
                    prepare_jokers(args.patched_dir, args.smods_dir, temp, archive)
                if args.deck_state:
                    from source_truth import prepare_deck_state
                    prepare_deck_state(args.patched_dir, temp)
                if args.bosses:
                    from source_truth import prepare_bosses
                    prepare_bosses(args.patched_dir, args.smods_dir, temp)
        # Hash the actual extracted truth and runtime; never include private source text.
        for source in sorted(Path(temp).rglob("*.lua")):
            report["sha256"]["truth/" + source.relative_to(temp).as_posix()] = hashlib.sha256(source.read_bytes()).hexdigest()
        for source in sorted(p for p in root.rglob("*") if p.suffix in (".lua", ".py")):
            report["sha256"]["Oracle/" + source.relative_to(root).as_posix()] = hashlib.sha256(source.read_bytes()).hexdigest()
        report["sha256"]["lua51.dll"] = hashlib.sha256((args.game_dir / "lua51.dll").read_bytes()).hexdigest()
        # Lua accepts JSON quoted slash-normalized paths without unicode escapes.
        bootstrap = (
            "io.stdout:setvbuf('no')\nORACLE_TEST_START=" + str(args.seed_start) + "\n"
            "ORACLE_TEST_SAMPLES={" + ",".join(k + "=" + str(v) for k, v in report["samples"].items()) + "}\n"
            "ORACLE_FIXTURES_ONLY=" + ("true" if args.consumables_only or args.tag_rewards_only or args.jokers_only else "false") + "\n"
            "ORACLE_JOKERS_ONLY=" + ("true" if args.jokers_only else "false") + "\n"
            "ORACLE_PACK_OPENING_ONLY=" + ("true" if args.pack_opening_only else "false") + "\n"
            "ORACLE_TEST_ROOT=" + json.dumps(root.as_posix(), ensure_ascii=False) + "\n"
            "ORACLE_TEST_GAME_DIR=" + json.dumps(args.game_dir.resolve().as_posix(), ensure_ascii=False) + "\n"
            "ORACLE_TEST_SOURCE=" + json.dumps(Path(temp).as_posix(), ensure_ascii=False) + "\n"
            "dofile(ORACLE_TEST_ROOT..'/tests/phase1.lua')\n"
            + "dofile(ORACLE_TEST_ROOT..'/tests/diagnostics.lua')\n"
            + ("dofile(ORACLE_TEST_ROOT..'/tests/phase6.lua')\n" if args.phase6 else "")
            + ("ORACLE_PHASE2_FIXTURES_ONLY=true\n" if args.fast else "")
            + ("dofile(ORACLE_TEST_ROOT..'/tests/phase2.lua')\n" if args.phase2 or args.phase3 or args.phase4 else "")
            + ("dofile(ORACLE_TEST_ROOT..'/tests/phase3.lua')\n" if args.phase3 or args.phase4 else "")
            + ("dofile(ORACLE_TEST_ROOT..'/tests/phase4.lua')\n" if args.phase4 else "")
            + ("dofile(ORACLE_TEST_ROOT..'/tests/phase5.lua')\n" if args.phase5 else "")
            + ("dofile(ORACLE_TEST_ROOT..'/tests/tags.lua')\n" if args.tags else "")
            + ("dofile(ORACLE_TEST_ROOT..'/tests/tag_chains.lua')\n" if args.tag_chains else "")
            + ("dofile(ORACLE_TEST_ROOT..'/tests/phase7.lua')\n" if args.phase7 else "")
            + ("dofile(ORACLE_TEST_ROOT..'/tests/tag_rewards.lua')\n" if args.tag_rewards else "")
            + ("dofile(ORACLE_TEST_ROOT..'/tests/consumables.lua')\n" if args.consumables and not args.tag_rewards_only else "")
            + ("dofile(ORACLE_TEST_ROOT..'/tests/quick_preview.lua')\n" if args.quick_preview else "")
            + ("dofile(ORACLE_TEST_ROOT..'/tests/jokers.lua')\n" if args.jokers and not args.deck_state_only and not args.bosses_only else "")
            + ("dofile(ORACLE_TEST_ROOT..'/tests/pack_opening.lua')\n" if args.jokers and not args.deck_state_only and not args.bosses_only else "")
            + ("dofile(ORACLE_TEST_ROOT..'/tests/events.lua')\n" if args.event_depth else "")
            + ("dofile(ORACLE_TEST_ROOT..'/tests/deck_state.lua')\n" if args.deck_state and not args.bosses_only else "")
            + ("dofile(ORACLE_TEST_ROOT..'/tests/bosses.lua')\n" if args.bosses else "")
            + ("dofile(ORACLE_TEST_ROOT..'/tests/card_insight.lua')\n" if args.card_insight else "")
            + ("dofile(ORACLE_TEST_ROOT..'/tests/undo.lua')\n" if args.undo else "")
        )
        bootstrap = "local ok,err=xpcall(function()\n" + bootstrap + "\nend,debug.traceback)\n" + (
            "if not ok then error(tostring(err)..'\\nREPLAY CONTEXT: '.."
            "(ORACLE and ORACLE.data.encode({case=ORACLE_TEST_CASE,context=ORACLE_TEST_CONTEXT}) or 'initialization')) end"
        )
        try:
            result = lua.luaL_loadstring(state, bootstrap.encode("utf-8"))
            if not result:
                result = lua.lua_pcall(state, 0, 0, 0)
            if result:
                raise RuntimeError(lua.lua_tolstring(state, -1, None).decode("utf-8", "replace"))
            report["status"] = "PASS"
        except Exception as error:
            report["status"] = "FAIL"
            report["error"] = str(error)
            raise
        finally:
            lua.lua_close(state)
            dll_dir.close()
            report["duration_seconds"] = round(time.perf_counter() - started, 3)
            if args.report:
                args.report.parent.mkdir(parents=True, exist_ok=True)
                args.report.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
