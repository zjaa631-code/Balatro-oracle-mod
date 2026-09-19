return function(O)
    local M = {}
    function M.text(value, scale, colour)
        return {n = G.UIT.T, config = {text = tostring(value or O.text.get('oracle_unknown')),
            scale = scale or 0.35, colour = colour or G.C.UI.TEXT_LIGHT, shadow = true}}
    end
    function M.row(nodes, padding)
        return {n = G.UIT.R, config = {align = 'cm', padding = padding or 0.08}, nodes = nodes}
    end
    function M.fitted(value,width,scale)
        return {n=G.UIT.C,config={align='cm',minw=width},nodes={{n=G.UIT.O,config={object=DynaText({
            string={tostring(value)},colours={G.C.UI.TEXT_LIGHT},maxw=width-0.15,scale=scale or 0.3,shadow=true,silent=true})}}}}
    end
    function M.message(key, colour)
        return M.row({M.text(O.text.get(key), 0.3, colour)})
    end
    function M.page(nodes)
        return {n = G.UIT.ROOT, config = {align = 'cm', padding = 0.1,
            colour = G.C.CLEAR, minw = 8.2, minh = 4.8}, nodes = nodes}
    end
    function M.field(label, value, width, colour, scale)
        -- Native DynaText maxw handles long translated or modded names.
        return {n = G.UIT.C, config = {align = 'cm', padding = 0.12, r = 0.1,
            colour = G.C.BLACK, emboss = 0.05, minw = width, minh = 1.05}, nodes = {
            M.row({M.text(O.text.get(label), 0.28, G.C.UI.TEXT_INACTIVE)}, 0.02),
            M.row({{n = G.UIT.O, config = {object = DynaText({
                string = {tostring(value or O.text.get('oracle_unknown'))},
                colours = {colour or G.C.UI.TEXT_LIGHT}, scale = scale or 0.42,
                maxw = width - 0.25, shadow = true, silent = true,
            })}}}, 0.04),
        }}
    end
    return M
end
