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

--- Load the atlas from folder
--- @param folder string
---
function AnimateAtlas:load(folder)
    self.timeline = {}
    self.timeline.data = json.decode(love.filesystem.read("string", folder .. "/" .. "Animation.json"))
    self.timeline.optimized = self.timeline.data.AN ~= nil

    self.spritemaps = {}
    for _, item in ipairs(love.filesystem.getDirectoryItems(folder)) do
        if string.startsWith(item, "spritemap") and string.endsWith(item, ".json") then
            local data = json.decode(love.filesystem.read("string", folder .. "/" .. item))
            local texture = love.graphics.newImage(folder .. "/" .. string.sub(item, 1, #item - 5) .. ".png")
            table.insert(self.spritemaps, { data = data, texture = texture })
        end
    end
    self.libraries = {}
    if self.timeline.data.SD ~= nil or self.timeline.data.SYMBOL_DICTIONARY ~= nil then
        -- regular adobe format
        local optimized = self.timeline.data.SD ~= nil
        local symbolDictionary = self.timeline.data[optimized and "SD" or "SYMBOL_DICTIONARY"]
        
        local symbols = symbolDictionary[optimized and "S" or "Symbols"]
        for i = 1, #symbols do
            local symbol = symbols[i]
            
            local symbolName = symbol[optimized and "SN" or "SYMBOL_name"]
            local data = symbol[optimized and "TL" or "TIMELINE"]
            
            self.libraries[symbolName] = { data = data, optimized = data.L ~= nil }
        end
    else
        -- bta format
        for _, item in ipairs(love.filesystem.getDirectoryItems(folder .. "/LIBRARY")) do
            if string.endsWith(item, ".json") then
                local data = json.decode(love.filesystem.read("string", folder .. "/LIBRARY/" .. item))
                self.libraries[string.sub(item, 1, #item - 5)] = { data = data, optimized = data.L ~= nil }
            end
        end
    end
    if #self.spritemaps < 1 then
        error("Couldn't find any spritemaps for folder path '" .. folder .. "'")
        return
    end
    if love.filesystem.getInfo(folder .. "/metadata.json", "file") ~= nil then
        self.framerate = json.decode(love.filesystem.read("string", folder .. "/metadata.json"))[self.timeline.optimized and "FRT" or "framerate"]
    else
        local optimized = self.timeline.data.FRT ~= nil
        local hasFramerate = self.timeline.data.FRT ~= nil or self.timeline.data.framerate ~= nil
        self.framerate = hasFramerate and (optimized and self.timeline.data.FRT or self.timeline.data.framerate) or 0
        print(self.framerate)
    end
    print("Loaded at " .. self.framerate .. " frames per second")
end

function AnimateAtlas:getTimelineLength(timeline)
    local optimized = timeline.optimized == true or timeline.L ~= nil
    if timeline.data then
        timeline = timeline.data[optimized and "AN" or "ANIMATION"][optimized and "TL" or "TIMELINE"]
    end
    local longest = 0
    local timelineLayers = timeline[optimized and "L" or "LAYERS"]
    for i = #timelineLayers, 1, -1 do
        local layer = timelineLayers[i]
        local layerFrames = layer[optimized and "FR" or "Frames"]

        local keyframe = layerFrames[#layerFrames]
        if keyframe ~= nil then
            local length = keyframe[optimized and "I" or "index"] + keyframe[optimized and "DU" or "duration"]
            if length > longest then
                longest = length
            end
        end
    end
    
    return longest
end

function AnimateAtlas:getLength()
    local optimized = self.timeline.optimized == true or self.timeline.L ~= nil
    return self:getTimelineLength(self.timeline.data[optimized and "AN" or "ANIMATION"][optimized and "TL" or "TIMELINE"])
end

---
--- @param  timeline  table
--- @param  frame     integer
--- @param  matrix    love.Transform
---
function AnimateAtlas:drawTimeline(timeline, frame, matrix, colorTransform)
    local optimized = timeline.L ~= nil
    local timelineLayers = timeline[optimized and "L" or "LAYERS"]

    for i = #timelineLayers, 1, -1 do
        local layer = timelineLayers[i]
        local keyframes = layer[optimized and "FR" or "Frames"]

        for j = 1, #keyframes do
            local keyframe = keyframes[j]

            local index = keyframe[optimized and "I" or "index"]
            local duration = keyframe[optimized and "DU" or "duration"]
        
            if frame >= index and frame < index + duration then
                local elements = keyframe[optimized and "E" or "elements"]
                for k = 1, #elements do
                    local element = elements[k]
                    
                    local symbol = element[optimized and "SI" or "SYMBOL_Instance"]
                    local atlasSprite = element[optimized and "ASI" or "ATLAS_SPRITE_instance"]
                    
                    if symbol then
                        local symbolName = symbol[optimized and "SN" or "SYMBOL_name"]

                        -- get the symbol's first frame
                        local firstFrame = symbol[optimized and "FF" or "firstFrame"]
                        if firstFrame == nil then
                            firstFrame = 0
                        end
                        -- get the frame index we want to possibly render
                        local frameIndex = firstFrame
                        frameIndex = frameIndex + (frame - index)

                        local symbolType = symbol[optimized and "ST" or "symbolType"]
                        if symbolType == "movieclip" or symbolType == "MC" then
                            -- movie clips can only display first frame
                            frameIndex = 0
                        end
                        local loopMode = symbol[optimized and "LP" or "loop"]

                        local library = self.libraries[symbolName]
                        local symbolTimeline = library.data
                        
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

                        local is3DMatrix = symbol[optimized and "M3D" or "Matrix3D"] ~= nil
                        local symbolMatrix = love.math.newTransform()
                        
                        if is3DMatrix then
                            local symbolMatrixRaw = symbol[optimized and "M3D" or "Matrix3D"]
                            if optimized then
                                symbolMatrix:setMatrix(
                                    "column",
                                    symbolMatrixRaw[1], -- a
                                    symbolMatrixRaw[2], -- b
                                    symbolMatrixRaw[3], symbolMatrixRaw[4],
                                    symbolMatrixRaw[5], -- c
                                    symbolMatrixRaw[6], -- d
                                    symbolMatrixRaw[7], symbolMatrixRaw[8], symbolMatrixRaw[9], symbolMatrixRaw[10], symbolMatrixRaw[11], symbolMatrixRaw[12],
                                    symbolMatrixRaw[13], -- tx
                                    symbolMatrixRaw[14], -- ty
                                    symbolMatrixRaw[15], symbolMatrixRaw[16]
                                )
                            else
                                symbolMatrix:setMatrix(
                                    "column",
                                    symbolMatrixRaw["m00"],
                                    symbolMatrixRaw["m01"],
                                    symbolMatrixRaw["m02"],
                                    symbolMatrixRaw["m03"],
                                    symbolMatrixRaw["m10"],
                                    symbolMatrixRaw["m11"],
                                    symbolMatrixRaw["m12"],
                                    symbolMatrixRaw["m13"],
                                    symbolMatrixRaw["m20"],
                                    symbolMatrixRaw["m21"],
                                    symbolMatrixRaw["m22"],
                                    symbolMatrixRaw["m23"],
                                    symbolMatrixRaw["m30"],
                                    symbolMatrixRaw["m31"],
                                    symbolMatrixRaw["m32"],
                                    symbolMatrixRaw["m33"]
                                )
                            end
                        else
                            local symbolMatrixRaw = symbol[optimized and "MX" or "Matrix"]
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
                        end
                        -- TODO: is this shit even working correctly??
                        local symbolColor = symbol[optimized and "C" or "color"]
                        if symbolColor and not colorTransform then
                            colorTransform = symbolColor
                        end
                        if colorTransform and symbolColor then
                            for key, value in pairs(colorTransform) do
                                if type(value) == "number" then
                                    if string.endsWith(key, "Offset") then
                                        -- is offset
                                        colorTransform[key] = value + symbolColor[key]
                                    else
                                        -- assume multiplier
                                        colorTransform[key] = value * symbolColor[key]
                                    end
                                end
                            end
                        end
                        self:drawTimeline(symbolTimeline, frameIndex, matrix:clone():apply(symbolMatrix), colorTransform)
                    
                    elseif atlasSprite then
                        -- store thecolor transform mode somewhere
                        local colorTransformMode = colorTransform and colorTransform.mode or nil
                        if not colorTransformMode then
                            colorTransformMode = "none"
                        end
                        --- @type "brightness"|"tint"|"alpha"|"advanced"|"none"
                        colorTransformMode = colorTransformMode:lower()

                        local name = atlasSprite[optimized and "N" or "name"]
                        local is3DMatrix = atlasSprite[optimized and "M3D" or "Matrix3D"] ~= nil
                        
                        local spriteMatrix = love.math.newTransform()
                        if is3DMatrix then
                            local spriteMatrixRaw = atlasSprite[optimized and "M3D" or "Matrix3D"]
                            if optimized then
                                spriteMatrix:setMatrix(
                                    "column",
                                    spriteMatrixRaw[1], -- a
                                    spriteMatrixRaw[2], -- b
                                    spriteMatrixRaw[3], spriteMatrixRaw[4],
                                    spriteMatrixRaw[5], -- c
                                    spriteMatrixRaw[6], -- d
                                    spriteMatrixRaw[7], spriteMatrixRaw[8], spriteMatrixRaw[9], spriteMatrixRaw[10], spriteMatrixRaw[11], spriteMatrixRaw[12],
                                    spriteMatrixRaw[13], -- tx
                                    spriteMatrixRaw[14], -- ty
                                    spriteMatrixRaw[15], spriteMatrixRaw[16]
                                )
                            else
                                spriteMatrix:setMatrix(
                                    "column",
                                    spriteMatrixRaw["m00"],
                                    spriteMatrixRaw["m01"],
                                    spriteMatrixRaw["m02"],
                                    spriteMatrixRaw["m03"],
                                    spriteMatrixRaw["m10"],
                                    spriteMatrixRaw["m11"],
                                    spriteMatrixRaw["m12"],
                                    spriteMatrixRaw["m13"],
                                    spriteMatrixRaw["m20"],
                                    spriteMatrixRaw["m21"],
                                    spriteMatrixRaw["m22"],
                                    spriteMatrixRaw["m23"],
                                    spriteMatrixRaw["m30"],
                                    spriteMatrixRaw["m31"],
                                    spriteMatrixRaw["m32"],
                                    spriteMatrixRaw["m33"]
                                )
                            end
                        else
                            local spriteMatrixRaw = atlasSprite[optimized and "MX" or "Matrix"]
                            spriteMatrix:setMatrix(
                                "column", -- OKAY MAKE SURE THIS IS HERE LOL
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
                        end
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
    else
        timeline = timeline.data
    end
    return timeline
end

function AnimateAtlas:draw(x, y)
    local identity = love.math.newTransform()
    identity:translate(x, y)

    local timeline = self:getSymbolTimeline(self.symbol)
    if timeline.data then
        timeline = timeline.data[timeline.optimized and "AN" or "ANIMATION"][timeline.optimized and "TL" or "TIMELINE"]
    end
    self:drawTimeline(timeline, self.frame, identity, nil)
end

return AnimateAtlas