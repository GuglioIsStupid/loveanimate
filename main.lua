-- This is the main testing file!

require("loveanimate")

---
--- @type love.animate.AnimateAtlas
---
local darny

function love.load()
    darny = love.animate.newAtlas()
    darny:load("examples/darnell")
end

function love.draw()
    darny:draw()
end