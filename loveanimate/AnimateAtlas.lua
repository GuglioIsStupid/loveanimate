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
    self.libraries = {}
    for _, item in ipairs(love.filesystem.getDirectoryItems(folder .. "/LIBRARY")) do
        if string.endsWith(item, ".json") then
            local data = json.decode(love.filesystem.read("string", folder .. "/LIBRARY/" .. item))
            self.libraries[string.sub(item, 1, #item - 5)] = data
        end
    end
    if #self.spritemaps < 1 then
        error("Couldn't find any spritemaps for folder path '" .. folder .. "'")
        return
    end
    self.timeline = {}
    self.timeline.data = json.decode(love.filesystem.read("string", folder .. "/" .. "Animation.json"))
    self.timeline.optimized = self.timeline.data.AN ~= nil

    self.framerate = json.decode(love.filesystem.read("string", folder .. "/" .. "metadata.json"))[self.timeline.optimized and "FRT" or "framerate"]
    print("Loaded at " .. self.framerate .. " frames per second")


    -- parse skibidi toilet
    -- make sure u add the duplicate frames in layers
    -- because funny
    -- then ur good
    -- https://github.com/what-is-a-git/gdanimate
end

function AnimateAtlas:getTimelineLength(timeline)
    local longest = 0
    local timelineLayers = timeline.LAYERS
    for i = #timelineLayers, 1, -1 do
        local layer = timelineLayers[i]
        local keyframe = layer.Frames[#layer.Frames]
        if keyframe ~= nil then
            local length = keyframe.index + keyframe.duration
            if length > longest then
                longest = length
            end
        end
    end

    return longest
end

function AnimateAtlas:getLength()
    return self:getTimelineLength(self.timeline.data.ANIMATION.TIMELINE)
end

---
--- @param  timeline  table
--- @param  frame     integer
--- @param  matrix    love.Transform
---
function AnimateAtlas:drawTimeline(timeline, frame, matrix)
    local timelineLayers = timeline.LAYERS
    for i = #timelineLayers, 1, -1 do
        local layer = timelineLayers[i]
        local keyframes = layer.Frames

        for j = 1, #keyframes do
            local keyframe = keyframes[j]

            local index = keyframe.index
            local duration = keyframe.duration
        
            if frame >= index and frame < index + duration then
                local elements = keyframe.elements
                for k = 1, #elements do
                    local element = elements[k]
                    if element.SYMBOL_Instance then
                        local symbol = element.SYMBOL_Instance
                        local symbolName = symbol.SYMBOL_name

                        local firstFrame = symbol.firstFrame
                        firstFrame = firstFrame + (frame - index)

                        local loopMode = symbol.loop
                        local symbolTimeline = self.libraries[symbolName]
                        local length = self:getTimelineLength(symbolTimeline)
                        if loopMode == "loop" then
                            if firstFrame < 0 then
                                firstFrame = length + firstFrame
                            end
                            
                            firstFrame = firstFrame % length
                        elseif loopMode == "playonce" then
                            if firstFrame < 0 then
                                firstFrame = 0
                            end

                            if firstFrame > length - 1 then
                                firstFrame = length - 1
                            end
                        end

                        local symbolMatrixRaw = symbol.Matrix
                        local symbolMatrix = love.math.newTransform()
                        symbolMatrix:setMatrix(
                            symbolMatrixRaw[1], symbolMatrixRaw[3], symbolMatrixRaw[5], 0,
                            symbolMatrixRaw[2], symbolMatrixRaw[4], symbolMatrixRaw[6], 0,
                            0, 0, 1, 0,
                            0, 0, 0, 1
                        )
                        self:drawTimeline(symbolTimeline, firstFrame, matrix:clone():apply(symbolMatrix))
                    
                    elseif element.ATLAS_SPRITE_instance then
                        local atlasSprite = element.ATLAS_SPRITE_instance
                        local name = atlasSprite.name
                        
                        local spriteMatrixRaw = atlasSprite.Matrix
                        local spriteMatrix = love.math.newTransform()
                        spriteMatrix:setMatrix(
                            spriteMatrixRaw[1], spriteMatrixRaw[3], spriteMatrixRaw[5], 0,
                            spriteMatrixRaw[2], spriteMatrixRaw[4], spriteMatrixRaw[6], 0,
                            0, 0, 1, 0,
                            0, 0, 0, 1
                        )

                        local spritemaps = self.spritemaps
                        for l = 1, #spritemaps do
                            local spritemap = spritemaps[l]
                            local sprites = spritemap.data.ATLAS.SPRITES
                            for z = 1, #sprites do
                                local sprite = sprites[z].SPRITE
                                if sprite.name == name then
                                    local quad = love.graphics.newQuad(sprite.x, sprite.y, sprite.w, sprite.h, spritemap.texture:getWidth(), spritemap.texture:getHeight())
                                    local drawMatrix = matrix:clone():apply(spriteMatrix)
                                    if sprite.rotated then
                                        drawMatrix:rotate(-90)
                                        drawMatrix:translate(0, sprite.w)
                                    end
                                    love.graphics.draw(spritemap.texture, quad, drawMatrix)
                                    break
                                end
                            end
                        end
                    end
                end

                break
            end
        end
    end
end

function AnimateAtlas:draw(x, y)
    local identity = love.math.newTransform()
    identity:translate(x, y)
    self:drawTimeline(self.timeline.data.ANIMATION.TIMELINE, self.frame, identity)
end

return AnimateAtlas