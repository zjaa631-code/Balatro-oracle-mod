"""Extract functions verbatim from the user's installed/patched source.
No proprietary source is included in the mod or retained in the output archive.
"""
import re
from pathlib import Path


def function(source, name):
    start = source.index("function " + name + "(")
    tail = source[start:]
    end = re.search(r"\n(?:local )?function [A-Za-z_]", tail)
    return tail[:end.start()] if end else tail


def prepare(game_zip, patched, smods, destination):
    destination = Path(destination)
    parts = []
    sources = {
        "misc_functions.lua": ["pseudohash", "pseudoseed", "pseudorandom", "pseudorandom_element"],
        "common_events.lua": ["get_current_pool", "get_next_tag_key", "get_next_voucher_key", "get_new_boss"],
    }
    for filename, names in sources.items():
        source = (patched / "functions" / filename).read_text(encoding="utf-8")
        parts.extend(function(source, name) for name in names)
    utils = (smods / "src/utils.lua").read_text(encoding="utf-8")
    parts.extend(function(utils, name) for name in ["SMODS.size_of_pool", "SMODS.get_next_vouchers", "SMODS.add_to_pool"])
    weights = (smods / "src/utils/weights.lua").read_text(encoding="utf-8")
    parts.extend(function(weights, name) for name in ["SMODS.create_blind_pool", "SMODS.is_showdown_ante"])
    blinds = (smods / "src/game_objects/blind.lua").read_text(encoding="utf-8")
    # Limit get_new_blind before unrelated local override after the function.
    for name in ["SMODS.normalize_bosses_used_table", "SMODS.add_boss_to_used_table", "SMODS.get_new_blind"]:
        code = function(blinds, name)
        code = code.split("\nlocal blind_get_type")[0]
        parts.append(code)
    (destination / "truth.lua").write_text("\n".join(parts), encoding="utf-8")
    game = game_zip.read("game.lua").decode("utf-8")
    tables = ["local self = {}"]
    for name in ["P_TAGS", "P_BLINDS", "P_CENTERS"]:
        start = game.index("    self." + name + " = {")
        end = game.index("\n    }", start) + len("\n    }")
        tables.append(game[start:end])
    tables.append("return self")
    (destination / "prototypes.lua").write_text("\n".join(tables), encoding="utf-8")


def prepare_shop(game_zip, patched, smods, destination):
    (Path(destination) / 'inert_tag_truth.lua').write_text(
        function((patched / 'tag.lua').read_text(encoding='utf-8'), 'Tag:apply_to_run'), encoding='utf-8')
    destination = Path(destination)
    common = (patched / 'functions/common_events.lua').read_text(encoding='utf-8')
    ui = (patched / 'functions/UI_definitions.lua').read_text(encoding='utf-8')
    utils = (smods / 'src/utils.lua').read_text(encoding='utf-8')
    overrides = (smods / 'src/overrides.lua').read_text(encoding='utf-8')
    card = (patched / 'card.lua').read_text(encoding='utf-8')
    parts = [function(common, 'create_card')]
    start = ui.index('function create_card_for_shop(')
    parts.append(ui[start:ui.index('function create_shop_card_ui(', start)])
    for name in ['SMODS.create_card', 'SMODS.poll_rarity', 'SMODS.is_poker_hand_visible']:
        parts.append(function(utils, name).split('\nG.FUNCS.')[0])
    for name in ['poll_edition', 'get_pack']:
        parts.append(function(overrides, name))
    for name in ['Card:set_ability', 'Card:set_eternal', 'Card:set_perishable', 'Card:set_rental']:
        parts.append(function(card, name))
    (destination / 'shop_truth.lua').write_text('\n'.join(parts), encoding='utf-8')
    objects = (smods / 'src/game_object.lua').read_text(encoding='utf-8')
    start = objects.index("    SMODS.Edition:take_ownership('foil'")
    end = objects.index('------- API CODE GameObject.Keybind', start)
    (destination / 'edition_truth.lua').write_text(objects[start:end], encoding='utf-8')


def prepare_packs(patched, smods, destination):
    destination = Path(destination)
    objects = (smods / 'src/game_object.lua').read_text(encoding='utf-8')
    start = objects.index('    local pack_loc_vars = function(')
    end = objects.index('----- API CODE GameObject.UndiscoveredSprite', start)
    (destination / 'booster_truth.lua').write_text(objects[start:end], encoding='utf-8')
    utils = (smods / 'src/utils.lua').read_text(encoding='utf-8')
    (destination / 'seal_truth.lua').write_text(function(utils, 'SMODS.poll_seal'), encoding='utf-8')
    common = (patched / 'functions/common_events.lua').read_text(encoding='utf-8')
    card = (patched / 'card.lua').read_text(encoding='utf-8')
    (destination / 'tooltip_truth.lua').write_text(function(common, 'generate_card_ui').split('\n--- Divvy')[0]+'\n'+function(card, 'Card:generate_UIBox_ability_table'), encoding='utf-8')


def prepare_deck(patched, destination):
    area = (patched / 'cardarea.lua').read_text(encoding='utf-8')
    common = (patched / 'functions/common_events.lua').read_text(encoding='utf-8')
    parts = [function(area, n) for n in ['CardArea:emplace', 'CardArea:remove_card', 'CardArea:draw_card_from']]
    parts.append(function(common, 'change_shop_size'))
    (Path(destination) / 'deck_truth.lua').write_text('\n'.join(parts), encoding='utf-8')


def prepare_tags(patched, smods, destination):
    source = (patched / 'tag.lua').read_text(encoding='utf-8')
    parts = [function(source, n) for n in ['Tag:set_ability', 'Tag:apply_to_run', 'Tag:get_uibox_table']]
    ui = (patched / 'functions/UI_definitions.lua').read_text(encoding='utf-8')
    start = ui.index('function create_card_for_shop(')
    parts.append(ui[start:ui.index('function create_shop_card_ui(', start)])
    common = (patched / 'functions/common_events.lua').read_text(encoding='utf-8')
    parts.append(function(common, 'level_up_hand'))
    utils = (smods / 'src/utils.lua').read_text(encoding='utf-8')
    parts.append(function(utils, 'SMODS.upgrade_poker_hands').split('\nSMODS.ease_types')[0])
    (Path(destination) / 'tag_truth.lua').write_text('\n'.join(parts), encoding='utf-8')


def prepare_tag_chains(patched, smods, destination):
    tag = (patched / 'tag.lua').read_text(encoding='utf-8')
    parts = [function(tag, n) for n in ['Tag:init', 'Tag:yep', 'Tag:remove', 'Tag:remove_from_game']]
    ui = (patched / 'functions/UI_definitions.lua').read_text(encoding='utf-8')
    parts.append(function(ui, 'add_tag'))
    utils = (smods / 'src/utils.lua').read_text(encoding='utf-8')
    parts.append(function(utils, 'SMODS.add_voucher_to_shop'))
    game = (patched / 'game.lua').read_text(encoding='utf-8')
    parts.append(function(game, 'Game:update_shop'))
    callbacks = (patched / 'functions/button_callbacks.lua').read_text(encoding='utf-8')
    start = callbacks.index('G.FUNCS.skip_blind = function(')
    end = callbacks.index('G.FUNCS.reroll_boss_button', start)
    parts.append(callbacks[start:end])
    (Path(destination) / 'tag_chain_truth.lua').write_text('\n'.join(parts), encoding='utf-8')


def prepare_consumables(patched, smods, destination):
    card = (patched / 'card.lua').read_text(encoding='utf-8')
    misc = (patched / 'functions/misc_functions.lua').read_text(encoding='utf-8')
    common = (patched / 'functions/common_events.lua').read_text(encoding='utf-8')
    parts = [function(card, name) for name in ['Card:use_consumeable', 'Card:add_to_deck', 'Card:remove_from_deck']]
    parts.append(function(misc, 'pseudoshuffle'))
    parts.extend(function(common, name) for name in ['copy_card', 'create_playing_card'])
    objects = (smods / 'src/game_object.lua').read_text(encoding='utf-8')
    start = objects.index('    local function juice_flip(')
    end = objects.index('    ----- API CODE GameObject.DeckSkin', start)
    parts.append(objects[start:end])
    utils = (smods / 'src/utils.lua').read_text(encoding='utf-8')
    parts.extend(function(utils, name) for name in ['SMODS.get_probability_vars', 'SMODS.pseudorandom_probability', 'SMODS.change_base', 'SMODS.modify_rank'])
    parts.extend(function(utils, name) for name in ['CardArea:count_property', 'SMODS.should_handle_limit', 'CardArea:handle_card_limit'])
    parts.append(function((patched / 'blind.lua').read_text(encoding='utf-8'), 'Blind:disable'))
    (Path(destination) / 'consumable_truth.lua').write_text('\n'.join(parts), encoding='utf-8')
    callbacks = (patched / 'functions/button_callbacks.lua').read_text(encoding='utf-8')
    start = callbacks.index('G.FUNCS.buy_from_shop = function(')
    end = callbacks.index('G.FUNCS.toggle_shop = function(', start)
    (Path(destination) / 'purchase_truth.lua').write_text(
        function(common, 'ease_dollars') + '\n' + callbacks[start:end], encoding='utf-8')


def prepare_jokers(patched, smods, destination, archive):
    card = (patched / 'card.lua').read_text(encoding='utf-8')
    common = (patched / 'functions/common_events.lua').read_text(encoding='utf-8')
    parts = [function(card, name) for name in ['Card:calculate_joker', 'Card:get_chip_mult', 'Card:get_p_dollars']]
    parts.extend(function(common, name) for name in ['reset_idol_card', 'reset_mail_rank', 'reset_ancient_card', 'reset_castle_card'])
    parts.append(function((smods / 'src/utils.lua').read_text(encoding='utf-8'), 'SMODS.poll_seal'))
    parts.append(function((smods / 'src/utils.lua').read_text(encoding='utf-8'), 'SMODS.blueprint_effect'))
    objects = (smods / 'src/game_object.lua').read_text(encoding='utf-8')
    start = objects.index("    SMODS.Enhancement:take_ownership('glass', {")
    end = objects.index("    SMODS.Enhancement:take_ownership(", start + 10)
    parts.append(objects[start:end])
    (Path(destination) / 'joker_truth.lua').write_text('\n'.join(parts), encoding='utf-8')
    (Path(destination) / 'pack_event_truth.lua').write_text(
        archive.read('engine/object.lua').decode('utf-8') + '\n' +
        (patched / 'engine/event.lua').read_text(encoding='utf-8') + '\n' +
        function(card, 'Card:open') + '\n' + function(card, 'Card:explode'), encoding='utf-8')


def prepare_deck_state(patched, destination):
    card = (patched / 'card.lua').read_text(encoding='utf-8')
    (Path(destination) / 'deck_state_truth.lua').write_text(function(card, 'Card:set_base'), encoding='utf-8')
    # remove is the last native Card method; installed mods can append unrelated
    # top-level registrations. Retain exactly the method through its final call.
    remove = function(card, 'Card:remove')
    end = remove.index('    Moveable.remove(self)\nend') + len('    Moveable.remove(self)\nend')
    (Path(destination) / 'remove_truth.lua').write_text(remove[:end], encoding='utf-8')


def prepare_bosses(patched, smods, destination):
    blind = (patched / 'blind.lua').read_text(encoding='utf-8')
    card = (patched / 'card.lua').read_text(encoding='utf-8')
    utils = (smods / 'src/utils.lua').read_text(encoding='utf-8')
    parts = [function(blind, n) for n in ['Blind:debuff_card', 'Blind:debuff_hand', 'Blind:modify_hand']]
    parts.extend(function(card, n) for n in ['Card:set_debuff', 'Card:get_id', 'Card:is_face', 'Card:is_suit'])
    parts.extend(function(utils, n) for n in ['SMODS.has_playing_card_property', 'SMODS.has_no_suit',
                                           'SMODS.has_any_suit', 'SMODS.has_no_rank', 'SMODS.smeared_check'])
    parts.append(function(utils, 'SMODS.get_enhancements').split('\nSMODS.enh_cache =')[0])
    misc = (patched / 'functions/misc_functions.lua').read_text(encoding='utf-8')
    parts.append(function(misc, 'find_joker'))
    objects = (smods / 'src/game_object.lua').read_text(encoding='utf-8')
    start = objects.index("    SMODS.Enhancement:take_ownership('stone', {")
    end = objects.index("    SMODS.Enhancement:take_ownership(", objects.index("    SMODS.Enhancement:take_ownership('wild', {", start) + 10)
    parts.append(objects[start:end])
    (Path(destination) / 'boss_truth.lua').write_text('\n'.join(parts), encoding='utf-8')


def prepare_card_insight(patched, destination):
    blind = (patched / 'blind.lua').read_text(encoding='utf-8')
    (Path(destination) / 'hook_truth.lua').write_text(function(blind, 'Blind:press_play'), encoding='utf-8')


def prepare_quick_preview(archive, patched, destination):
    area = (patched / 'cardarea.lua').read_text(encoding='utf-8')
    packer = archive.read('engine/string_packer.lua').decode('utf-8')
    (Path(destination) / 'quick_save_truth.lua').write_text(
        function(area, 'CardArea:save') + '\n' + function(packer, 'STR_PACK'), encoding='utf-8')
    callbacks = (patched / 'functions/button_callbacks.lua').read_text(encoding='utf-8')
    start = callbacks.index('  G.FUNCS.end_consumeable = function(')
    end = callbacks.index('  G.FUNCS.blind_choice_handler = function(', start)
    (Path(destination) / 'quick_pack_close_truth.lua').write_text(callbacks[start:end], encoding='utf-8')


def prepare_undo(archive, patched, destination):
    misc = (patched / 'functions/misc_functions.lua').read_text(encoding='utf-8')
    parts = [function(misc, n) for n in ['recursive_table_cull', 'save_with_action', 'save_run']]
    parts.append(function((patched / 'cardarea.lua').read_text(encoding='utf-8'), 'CardArea:save'))
    parts.append(function((patched / 'cardarea.lua').read_text(encoding='utf-8'), 'CardArea:load'))
    card = (patched / 'card.lua').read_text(encoding='utf-8')
    (Path(destination) / 'undo_card_truth.lua').write_text(
        '\n'.join(function(card, name) for name in ['Card:save', 'Card:load']), encoding='utf-8')
    parts.append(function(archive.read('engine/string_packer.lua').decode('utf-8'), 'STR_PACK'))
    callbacks = (patched / 'functions/button_callbacks.lua').read_text(encoding='utf-8')
    start = callbacks.index('G.FUNCS.start_run = function(')
    end = callbacks.index('G.FUNCS.go_to_menu = function(', start)
    parts.append(callbacks[start:end])
    game = (patched / 'game.lua').read_text(encoding='utf-8')
    start = game.index('        if G.STATE == G.STATES.SMODS_BOOSTER_OPENED then')
    end = game.index('        if self.STATE == self.STATES.GAME_OVER then', start)
    # Exercise the installed update dispatch between individual load events,
    # including paused (dt=0) frames; do not replace its nil dereference.
    parts.append('function ORACLE_TEST_BOOSTER_UPDATE(self, dt)\n' + game[start:end] + '\nend')
    (Path(destination) / 'undo_truth.lua').write_text('\n'.join(parts), encoding='utf-8')
