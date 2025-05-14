local Bit = require("loveanimate.libs.Bit")
local Classic = require("loveanimate.libs.Classic")

local prints = 0

local lprint = print
local function print(...)
    prints = prints + 1
    lprint("#" .. prints .. " - " .. ...)
end

local function intToRGB(int)
	return
		Bit.band(Bit.rshift(int, 16), 0xFF) / 255,
		Bit.band(Bit.rshift(int, 8), 0xFF) / 255,
		Bit.band(int, 0xFF) / 255,
		Bit.band(Bit.rshift(int, 24), 0xFF) / 255
end

---
--- @class love.animate.AnimateAtlas
---
local AnimateAtlas = Classic:extend()

local json = require("loveanimate.libs.Json")
require("loveanimate.libs.StringUtil")

function AnimateAtlas:constructor()
    self.frame = 0
    self.symbol = ""

    --- @protected
    self._colorTransformShader = love.graphics.newShader([[
        extern vec4 colorOffset;
        extern vec4 colorMultiplier;

        vec4 effect(vec4 color, Image tex, vec2 texCoords, vec2 screenCoords) {
            vec4 finalColor = Texel(tex, texCoords) * color;
            finalColor += colorOffset;
            return finalColor * colorMultiplier;
        }
    ]])
    self:setColorOffset(0, 0, 0, 0)
    self:setColorMultiplier(1, 1, 1, 1)
end

function AnimateAtlas:setColorOffset(r, g, b, a)
    self._colorTransformShader:send("colorOffset", {r, g, b, a})
end

function AnimateAtlas:setColorMultiplier(r, g, b, a)
    self._colorTransformShader:send("colorMultiplier", {r, g, b, a})
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
    if timeline.data then
        timeline = timeline.data.ANIMATION.TIMELINE
    end
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
function AnimateAtlas:drawTimeline(timeline, frame, matrix, colorTransform)
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

                        -- get the symbol's first frame
                        local firstFrame = symbol.firstFrame
                        if firstFrame == nil then
                            firstFrame = 0
                        end
                        -- get the frame index we want to possibly render
                        local frameIndex = firstFrame
                        frameIndex = frameIndex + (frame - index)

                        local symbolType = symbol.symbolType
                        if symbolType == "movieclip" or symbolType == "MC" then
                            -- movie clips can only display first frame
                            frameIndex = 0
                        end
                        local loopMode = symbol.loop
                        local symbolTimeline = self.libraries[symbolName]
                        local length = self:getTimelineLength(symbolTimeline)

                        if loopMode == "loop" or loopMode == "LP" then
                            -- wrap around back to 0
                            if frameIndex < 0 then
                                frameIndex = length - 1
                            end
                            if frameIndex > length - 1 then
                                frameIndex = 0
                            end
                        
                        elseif loopMode == "playonce" or loopMode == "PO" then
                            -- stop at last frame
                            if frameIndex < 0 then
                                frameIndex = 0
                            end
                            if frameIndex > length - 1 then
                                frameIndex = length - 1
                            end

                        elseif loopMode == "singleframe" or loopMode == "SF" then
                            -- stop at first frame
                            frameIndex = firstFrame
                        end

                        local symbolMatrixRaw = symbol.Matrix
                        local symbolMatrix = love.math.newTransform()
                        symbolMatrix:setMatrix(
                            "column", -- OKAY MAKE SURE THIS IS HERE LOL
                            symbolMatrixRaw[1], -- a
                            symbolMatrixRaw[2], -- b
                            0, 0,
                            symbolMatrixRaw[3], -- c
                            symbolMatrixRaw[4], -- d
                            0, 0, 0, 0, 1, 0,
                            symbolMatrixRaw[5], -- tx
                            symbolMatrixRaw[6], -- ty
                            0, 1
                        )
                        if not colorTransform then
                            colorTransform = symbol.color
                        end
                        if colorTransform then
                            for key, value in pairs(colorTransform) do
                                if type(value) == "number" then
                                    if string.endsWith(key, "Offset") then
                                        -- is offset
                                        colorTransform[key] = value + symbol.color[key]
                                    else
                                        -- assume multiplier
                                        colorTransform[key] = value * symbol.color[key]
                                    end
                                end
                            end
                        end
                        self:drawTimeline(symbolTimeline, frameIndex, matrix:clone():apply(symbolMatrix), colorTransform)
                    
                    elseif element.ATLAS_SPRITE_instance then
                        -- store thecolor transform mode somewhere
                        local colorTransformMode = colorTransform and colorTransform.mode or nil
                        if not colorTransformMode then
                            colorTransformMode = "none"
                        end
                        --- @type "brightness"|"tint"|"alpha"|"advanced"|"none"
                        colorTransformMode = colorTransformMode:lower()

                        local atlasSprite = element.ATLAS_SPRITE_instance
                        local name = atlasSprite.name
                        
                        local spriteMatrixRaw = atlasSprite.Matrix
                        local spriteMatrix = love.math.newTransform()
                        spriteMatrix:setMatrix(
                            "column", -- OKAY MAKE SURE THIS IS HERE LOL x2
                            spriteMatrixRaw[1], -- a
                            spriteMatrixRaw[2], -- b
                            0, 0,
                            spriteMatrixRaw[3], -- c
                            spriteMatrixRaw[4], -- d
                            0, 0, 0, 0, 1, 0,
                            spriteMatrixRaw[5], -- tx
                            spriteMatrixRaw[6], -- ty
                            0, 1
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
                                    local lastShader = love.graphics.getShader()
                                    love.graphics.setShader(self._colorTransformShader)

                                    self:setColorOffset(0, 0, 0, 0)
                                    self:setColorMultiplier(1, 1, 1, 1)

                                    if colorTransformMode == "brightness" then
                                        local brightness = colorTransform["brightness"]
                                        self:setColorOffset(brightness, brightness, brightness, 0)
                                        self:setColorMultiplier(
                                            1 - math.abs(brightness),
                                            1 - math.abs(brightness),
                                            1 - math.abs(brightness),
                                            1
                                        )

                                    elseif colorTransformMode == "tint" then
                                        local tintColor = tonumber("0xFF" + colorTransform["tintColor"]:sub(2))
                                        local tintR, tintG, tintB = intToRGB(tintColor)
                                        
                                        local multiplier = colorTransform["tintMultiplier"]
                                        self:setColorOffset(
                                            tintR * multiplier,
                                            tintG * multiplier,
                                            tintB * multiplier,
                                            0
                                        )
                                        self:setColorMultiplier(
                                            1 - multiplier,
                                            1 - multiplier,
                                            1 - multiplier,
                                            1
                                        )

                                    elseif colorTransformMode == "alpha" then
                                        local alphaMultiplier = colorTransform["alphaMultiplier"]
                                        self:setColorMultiplier(1, 1, 1, alphaMultiplier)
                                    
                                    elseif colorTransformMode == "advanced" then
                                        self:setColorOffset(
                                            colorTransform["redOffset"],
                                            colorTransform["greenOffset"],
                                            colorTransform["blueOffset"],
                                            colorTransform["AlphaOffset"]
                                        )
                                        self:setColorMultiplier(
                                            colorTransform["RedMultiplier"],
                                            colorTransform["greenMultiplier"],
                                            colorTransform["blueMultiplier"],
                                            colorTransform["alphaMultiplier"]
                                        )
                                    end
                                    love.graphics.draw(spritemap.texture, quad, drawMatrix)
                                    love.graphics.setShader(lastShader)
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

function AnimateAtlas:getSymbolTimeline(symbol)
    if not symbol then
        symbol = ""
    end
    local timeline = self.libraries[self.symbol]
    if not timeline then
        timeline = self.timeline
    end
    return timeline
end

function AnimateAtlas:draw(x, y)
    local identity = love.math.newTransform()
    identity:translate(x, y)

    local timeline = self:getSymbolTimeline(self.symbol)
    if timeline.data then
        timeline = timeline.data.ANIMATION.TIMELINE
    end
    self:drawTimeline(timeline, self.frame, identity, nil)
end

return AnimateAtlas