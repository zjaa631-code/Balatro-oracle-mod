-- Native Tag:apply_to_run rewards; only private, data-only generators run here.
return function(O)
    local D,M=O.data,{}
    M.packs={tag_standard='p_standard_mega_1',tag_charm='p_arcana_mega_1',
        tag_meteor='p_celestial_mega_1',tag_buffoon='p_buffoon_mega_1',tag_ethereal='p_spectral_normal_1'}
    function M.topup(s,rng,tag)
        local out={}
        local limit=s.tag.joker_limit
        for i=1,(tag.config.spawn_jokers or 2) do
            if s.tag.joker_count<limit then
                local c=O.shop_prediction.create(s,rng,'Joker','top',{area='owned',rarity=0})
                out[#out+1]=c; s.tag.joker_count=s.tag.joker_count+1
                s.shop.owned[c.key]=true
                if c.edition=='e_negative' then s.tag.joker_limit=s.tag.joker_limit+1 end
            end
        end
        -- The native callback checks the same rendered limit throughout its
        -- synchronous loop; new Negative slots apply to later tag callbacks.
        return out
    end
    function M.open(s,rng,tag)
        assert(not s.shop.pack_unsupported,'oracle_pack_unsupported')
        local key=assert(M.packs[tag.key],'oracle_tag_unsupported')
        local pack={key=key,set='Booster',variant_unknown=tag.key=='tag_charm' or tag.key=='tag_meteor'}
        local center=s.shop.centers[key]
        assert(center and not center.unsupported,'oracle_pack_unsupported')
        local cards={}
        local size=math.max(1,center.config.extra+(s.game.modifiers.booster_size_mod or 0))
        s.game.used_jokers[key]=true -- Native temporary Booster Card construction.
        O.pack_prediction.before_open(s,rng)
        for i=1,size do cards[i]=O.pack_prediction.candidate(s,rng,pack,i) end
        O.pack_prediction.settlement(s,rng,cards)
        return pack,cards
    end
    function M.has_pack(s)
        for _,tag in ipairs(s.tag.queue) do if not tag.done and M.packs[tag.key] then return true end end
    end
    function M.resolve_pack(s,rng,result)
        local opened=false
        for i,tag in ipairs(s.tag.queue) do
            if not tag.done and tag.key~='tag_double' then
                local e={instance=i,id=tag.id,tag=tag.key,target=tag.target,stage='new_blind_choice'}
                if M.packs[tag.key] and not opened then
                    e.type='pack'; e.pack,e.cards=M.open(s,rng,tag); tag.done=true; opened=true
                else
                    e.type='pending'; e.pending=true; e.reason='oracle_tag_after_pack'
                end
                result.effects[#result.effects+1]=e
            end
        end
        result.status='experimental'; result.choice_boundary=true
    end
    function M.plain(cards)
        local out=D.copy(cards or {}); for _,c in ipairs(out) do c.legendary=nil end; return out
    end
    return M
end
