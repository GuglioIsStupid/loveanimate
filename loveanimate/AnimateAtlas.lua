local Classic = require("loveanimate.libs.Classic")

---
--- @class love.animate.AnimateAtlas
---
local AnimateAtlas = Classic:extend()
local json = require("loveanimate.libs.Json")
require("loveanimate.libs.StringUtil")

function AnimateAtlas:constructor()
    self.frame = 0
    self.symbol = ""
end

--- Load the atlas from folder UwU
--- @param folder string
---
function AnimateAtlas:load(folder)
    self.spritemaps = {}
    for _, item in ipairs(love.filesystem.getDirectoryItems(folder)) do
        if string.startsWith(item, "spritemap") and string.endsWith(item, ".json") then
            local data = json.decode(love.filesystem.read("string", folder .. "/" .. item))
            local texture = love.graphics.newImage(folder .. "/" .. string.sub(item, 1, #item - 5) .. ".png")
            table.insert(self.spritemaps, { data = data, texture = texture })
        end
    end

    if #self.spritemaps < 1 then
        error("Couldn't find any spritemaps for folder path '" .. folder .. "'")
        return
    end

    self.timeline = {}
    self.timeline.data = json.decode(love.filesystem.read("string", folder .. "/" .. "Animation.json"))
    self.timeline.optimized = self.timeline.data.AN ~= nil

    -- parse skibidi toilet
    -- make sure u add the duplicate frames in layers
    -- because funny
    -- then ur good
    -- https://github.com/what-is-a-git/gdanimate
end

function AnimateAtlas:draw()
    -- draw layers but Reversed uwU
    -- make sure you have a draw Timeline function
    -- for the other fucking uhh symbols
end

return AnimateAtlas