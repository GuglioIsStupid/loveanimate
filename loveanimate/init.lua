local la = { _VERSION = "0.1.0" }
print("Loaded LoveAnimate v" .. la._VERSION)


---
--- @return love.AnimateAtlas
---
function la.newAtlas()
end

---
--- @param  atlas  love.AnimateAtlas
---
function la.drawAtlas(atlas)
    -- we can use love.graphics.draw here
    -- since it should only get set AFTER
    -- the rest of LoveAnimate gets initialized
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