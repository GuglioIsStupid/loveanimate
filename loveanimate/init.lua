local la = { _VERSION = "0.1.0" }
print("Loaded LoveAnimate v" .. la._VERSION)

local AnimateAtlas = require("loveanimate.AnimateAtlas")

---
--- @return love.animate.AnimateAtlas
---
function la.newAtlas()
    return AnimateAtlas:new()
end

local loveGfxDraw = love.graphics.draw
love.graphics.draw = function(drawable, ...)
    if drawable._type == "AnimateAtlas" then
        la.drawAtlas(drawable)
        return
    end
    loveGfxDraw(drawable, ...)
end

love.animate = la