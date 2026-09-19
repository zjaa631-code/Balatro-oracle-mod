return function(O)
    local M = {pages = {}, active = 'overview'}
    -- Every predictive page must present its validation status explicitly.
    function M.register(id, label, build)
        for _, page in ipairs(M.pages) do assert(page.id ~= id, 'Duplicate Oracle tab: '..id) end
        M.pages[#M.pages + 1] = {id = id, label = label, build = build}
    end
    M.register('overview', 'oracle_overview', O.overview)
    M.register('settings', 'oracle_settings', O.settings.definition)
    function M.definition()
        local tabs = {}
        local index=1
        for i,page in ipairs(M.pages) do if page.id==M.active then index=i end end
        local group=math.ceil(index/4)
        for i=(group-1)*4+1,math.min(group*4,#M.pages) do
            local page=M.pages[i]
            local selected = page
            tabs[#tabs + 1] = {
                label = O.text.get(selected.label), chosen = M.active == selected.id,
                tab_definition_function = function()
                    M.active = selected.id
                    if not O.config.enabled and selected.id~='settings' and selected.id~='undo' then
                        return O.ui.page({O.ui.message('oracle_disabled')})
                    end
                    local ok, result = pcall(selected.build)
                    if ok then return result end
                    if sendWarnMessage then sendWarnMessage(tostring(result), 'Oracle') end
                    return O.ui.page({O.ui.message('oracle_ui_unavailable', G.C.ORANGE)})
                end,
            }
        end
        return create_UIBox_generic_options({back_func = 'exit_overlay_menu', contents = {
            O.ui.row({O.ui.text(O.text.get('oracle_title'), 0.6, G.C.ORANGE)}),
            create_option_cycle({options=M.group_labels(),current_option=group,opt_callback='oracle_tab_group',
                w=4.7,scale=0.45,no_pips=true}),
            create_tabs({tabs = tabs, snap_to_nav = true, tab_h = 4.8, tab_w = 8.2,scale=0.75,text_scale=0.35}),
            O.ui.row({UIBox_button({button = 'oracle_refresh', label = {O.text.get('oracle_refresh')},
                minw = 2.5, minh = 0.55, scale = 0.35}),
                UIBox_button({button='oracle_export_logs',label={O.text.get('oracle_export_logs')},minw=2.5,minh=0.55,scale=0.35})}),
            {n=G.UIT.R,config={id='oracle_watch',func='oracle_watch',align='cm'},nodes={}},
        }})
    end
    function M.group_labels()
        local out={}
        for first=1,#M.pages,4 do
            local last=math.min(first+3,#M.pages)
            out[#out+1]=O.text.get(M.pages[first].label)..(first==last and '' or (' / '..O.text.get(M.pages[last].label)))
        end
        return out
    end
    function M.install()
        G.FUNCS.oracle_tab_group=function(args)
            local page=M.pages[(args.to_key-1)*4+1]
            if page then M.active=page.id; G.FUNCS.oracle_refresh() end
        end
        M.watch=function(e)
            if O.config.auto_refresh==false then return end
            local revision=O.controller.revision
            if e.config.oracle_revision==nil then e.config.oracle_revision=revision; return end
            if e.config.oracle_revision==revision or e.config.oracle_queued then return end
            e.config.oracle_queued=true
            local overlay=G.OVERLAY_MENU
            G.E_MANAGER:add_event(Event({trigger='after',delay=0.15,timer='REAL',pause_force=true,
                blocking=false,blockable=false,func=function()
                    if G.OVERLAY_MENU==overlay and O.config.auto_refresh~=false then G.FUNCS.oracle_refresh() end
                    return true
                end}))
        end
        G.FUNCS.oracle_watch=M.watch
        local ok, lovely = pcall(require, 'lovely')
        O.status = O.compatibility.inspect(G, SMODS, ok and lovely or nil)
        if not O.status.ui_ready or type(create_UIBox_options) ~= 'function' then return end
        G.FUNCS.oracle_refresh = function()
            if not G.FUNCS.overlay_menu then return end
            local ok_lovely, current_lovely = pcall(require, 'lovely')
            O.status = O.compatibility.inspect(G, SMODS, ok_lovely and current_lovely or nil)
            -- DynaText chooses its timer at construction. HUD/F8 must enter the
            -- native paused menu lifecycle before creating any tab contents.
            local was_paused=G.SETTINGS.paused
            G.SETTINGS.paused=true
            local ok_build, tree = pcall(M.definition)
            if not ok_build then
                G.SETTINGS.paused=was_paused
                if sendWarnMessage then sendWarnMessage(tostring(tree), 'Oracle') end
                return
            end
            G.FUNCS.overlay_menu({definition = tree})
        end
        G.FUNCS.oracle_open = function()
            M.active = 'overview'
            return G.FUNCS.oracle_refresh()
        end
    end
    return M
end
