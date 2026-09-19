local oldG,oldSMODS,oldLove=G,SMODS,love
local D=ORACLE.data
local files={['oracle-validation.log']='MISMATCH test_rng',
    ['Mods/lovely/log/lovely-2026.09.18.log']='latest log',
    ['Mods/lovely/log/lovely-2026.09.17.log']='old log'}
local fs={getInfo=function(p) return files[p] and {size=#files[p]} end,
    read=function(p) return files[p] end,write=function(p,t) files[p]=t; return true end,
    createDirectory=function() return true end,
    getDirectoryItems=function() return {'lovely-2026.09.17.log','lovely-2026.09.18.log','other-file'} end,
    getSaveDirectory=function() return 'C:/Test Save/Balatro' end}
G={VERSION='test',GAME={pseudorandom={seed='EXPORTSEED',halu4=0.123}},jokers={cards={}},consumeables={cards={}},
    FUNCS={},SETTINGS={},CONTROLLER={},C={ORANGE={}}}
SMODS={version='test',mod_list={{id='Oracle',version='test'}}}; love={filesystem=fs}
local O={version='test',data=D,status={issues={'version_test'}},prediction_fault=true,config={enabled=false},
    validator={records={{status='MISMATCH',expected='A',actual='B'}},counts={MISMATCH=1}},
    state_reader={read=function(g) return D.copy(g.GAME) end},
    pack_prediction={capture=function() return {reason='test',rng=D.copy(G.GAME.pseudorandom)} end},
    shop_snapshot={capture=function() error('snapshot unavailable') end},deck_prediction={read=function() return {} end}}
O.diagnostics=dofile(ORACLE_TEST_ROOT..'/debug/diagnostics.lua')(O)
local function test(n,f) ORACLE_TEST_CASE=n; f(); print('PASS '..n) end
test('diagnostic export survives unavailable predictors and preserves faults and RNG',function()
    local before=D.encode(G.GAME)
    math.randomseed(518); local first=math.random(); math.randomseed(518)
    for i=1,20 do O.diagnostics.note('hover','error'..i) end
    assert(#O.diagnostics.recent==16); O.diagnostics.note('hover','error20'); assert(#O.diagnostics.recent==16)
    local path=assert(O.diagnostics.export()); local text=files[path]
    assert(path:match('^oracle%-reports/Oracle%-.*%.txt$'))
    for _,value in ipairs({'EXPORTSEED','halu4','snapshot unavailable','latest log','MISMATCH','error20'}) do assert(text:find(value,1,true),value) end
    assert(not text:find('old log',1,true)); assert(O.prediction_fault)
    assert(before==D.encode(G.GAME) and first==math.random())
    local nextpath=assert(O.diagnostics.export()); assert(nextpath~=path,'report collision')
    local game=G.GAME; G.GAME=nil
    assert(O.diagnostics.export(),'no-run export'); G.GAME=game
end)
test('export catches write errors and bounds log tails without reading saves',function()
    local write=fs.write; fs.write=function() return nil end
    local path,err=O.diagnostics.export(); assert(not path and err)
    fs.write=write
    files['oracle-validation.log']=string.rep('x',600*1024)
    assert(O.diagnostics.build(fs):find('oversized log',1,true))
    fs.newFile=function(p)
        assert(p=='oracle-validation.log')
        local position=0
        return {open=function() return true end,seek=function(_,n) position=n; return true end,
            read=function(_,n) return files[p]:sub(position+1,position+n) end,close=function() return true end}
    end
    assert(O.diagnostics.build(fs):find('truncated to last 512 KiB',1,true))
end)
test('F10 and native export button stay available with predictions disabled',function()
    local binding,overlays,opened=nil,0,nil
    SMODS.Keybind=function(t) binding=t end
    O.text={get=function(k) return k end}
    O.ui={message=function(k) return k end,row=function(t) return t end,text=function(t) return t end}
    local oldButton,oldGeneric=UIBox_button,create_UIBox_generic_options
    UIBox_button=function(t) return t end; create_UIBox_generic_options=function(t) return t end
    G.FUNCS.overlay_menu=function() overlays=overlays+1 end
    love.system={openURL=function(url) opened=url; return true end}
    dofile(ORACLE_TEST_ROOT..'/ui/diagnostics.lua')(O).install()
    assert(binding.key_pressed=='f10'); binding.action(); assert(overlays==1 and G.SETTINGS.paused)
    G.CONTROLLER.text_input_hook=true; binding.action(); assert(overlays==1); G.CONTROLLER.text_input_hook=nil
    O.undo={restoring=true}; binding.action(); assert(overlays==1); O.undo=nil
    G.FUNCS.oracle_export_logs(); assert(overlays==2)
    G.FUNCS.oracle_report_folder(); assert(opened=='file:///C:/Test%20Save/Balatro/oracle-reports')
    UIBox_button,create_UIBox_generic_options=oldButton,oldGeneric
end)
G,SMODS,love=oldG,oldSMODS,oldLove
