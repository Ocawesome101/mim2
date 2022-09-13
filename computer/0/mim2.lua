-- Minecraft-in-Minecraft 2
-- A spiritual successor to Casper7526's "mim" from a decade ago.
-- Hopefully written significantly better.

-- Supports Recrafted!
local term = rawget(_G, "term") or require("term")
local keys = rawget(_G, "keys") or require("keys")
local fs = rawget(_G, "fs") or require("fs")
local settings = rawget(_G, "settings") or require("settings")
local window = rawget(_G, "window") or require("window")
local strings = require("cc.strings")

local NO_LIGHT = settings.get("mim2.no_lighting")
local TICK_TIME = (rawget(_G, "jit") or NO_LIGHT) and 0.1 or 0.2
local BEGIN, END = 256*-128, 256*128

local pullEvent, startTimer, epoch, sleep
if not rawget(os, "pullEvent") then
  local rc = require("rc")
  pullEvent, startTimer, epoch, sleep = rc.pullEventRaw, rc.startTimer,
    rc.epoch, rc.sleep
else
  pullEvent, startTimer, epoch, sleep = rawget(os, "pullEventRaw"),
    rawget(os, "startTimer"), rawget(os, "epoch"), rawget(os, "sleep")
end

print([[Please ensure that the necessary custom font is installed.
If it is, then the following text will appear as a row of blocks:]])
for i=0x80, 0x8F do
  io.write(string.char(i))
end
print([[

If it does not appear as a row of blocks, install the font or game graphics will be garbled.  Font installation instructions are in the Minecraft-in-Minecraft 2 README file.

]])
print([[
If the font IS present, press Enter to continue.
Otherwise, hold Ctrl-T to stop the program.]])

do local _ = io.read() end

print([[
Controls:
  WASD - move
     R - remove block
     F - place block
     Q - pause/quit
Arrows - move block selection
1 to 9 - select block slot

Press Enter to continue.
]])

do local _ = io.read() end

-- create these here
local oldTerm = term.current()
local win = window.create(oldTerm, 1, 1, oldTerm.getSize())

------ Block registration ------

-- physics types are tables for comparison efficiency
local p_air, p_solid, p_liquid = {}, {}, {}

local blocks = {
  [0] = {
    name = "air",         -- block name
    tex = 0x60,           -- block texture (character)
    physics = p_air,      -- physics type (default p_solid)
    transparent = true,   -- lets light through? (default false)
  },
  {
    name = "bedrock",
    tex = 0x61,
  },
  {
    name = "stone",
    tex = 0x62,
  },
  {
    name = "cobblestone",
    tex = 0x63,
  },
  {
    name = "coal_ore",
    tex = 0x64,
  },
  {
    name = "iron_ore",
    tex = 0x65,
  },
  {
    name = "diamond_ore",
    tex = 0x66,
  },
  {
    name = "redstone_ore",
    tex = 0x67,
  },
  {
    name = "gold_ore",
    tex = 0x68,
  },
  {
    name = "nice_stone",
    tex = 0x69,
  },
  {
    name = "dirt",
    tex = 0x6A
  },
  {
    name = "grass",
    tex = 0x6B
  },
  {
    name = "log",
    tex = 0x6C
  },
  {
    name = "leaves",
    tex = 0x6D
  },
  {
    name = "ladder",
    tex = 0x6E,
    physics = p_liquid,
    transparent = true
  },
  {
    name = "torch",
    tex = 0x6F,
    physics = p_air,
    transparent = true
  }
}

local function getBlockIDByName(name)
  for i=0, #blocks, 1 do
    if blocks[i].name == name then
      return i
    end
  end
end

for i=0, #blocks, 1 do
  blocks[i].physics = blocks[i].physics or p_solid
end

------ Player data ------
local player = {
  x = 64, y = 180,
  motion = {
    x = 0, y = 0
  },
  -- Where you're looking, relative to the player
  look = {
    x = 2, y = 0,
  },
  selected = 1,
  -- first 9 slots are hotbar
  inventory = {
    [1] = {getBlockIDByName("torch"), 64}
  }
}

local function offsetChar(c)
  return string.char(math.max(0, c:byte() - 32))
end

local function drawButton(x, y, text)
  text = text:gsub(".", offsetChar)
  local bg = string.char(getBlockIDByName("stone")+0x60):rep(#text + 4)

  for i=1, 3 do
    term.setCursorPos(x, y+i-1)
    term.blit(bg, ("f"):rep(#bg), ("f"):rep(#bg))
  end

  term.setCursorPos(x+1, y+1)
  term.blit(text, ("f"):rep(#text), ("8"):rep(#text))
end

local function drawInput(x, y, text)
  text = text:gsub(".", offsetChar)
  local bg = string.char(getBlockIDByName("stone")+0x60):rep(#text + 4)

  for i=1, 3 do
    term.setCursorPos(x, y+i-1)
    term.blit(bg, ("0"):rep(#bg), ("0"):rep(#bg))
  end

  term.setCursorPos(x+1, y+1)
  term.blit(text, ("f"):rep(#text), ("0"):rep(#text))
end

local function drawTitle(title)
  local w = term.getSize()
  local x = math.floor(w/2 - #title/2)
  title = ((" "):rep(x) .. title .. (" "):rep(w - x + #title)):sub(1, w)

  term.setCursorPos(1, 1)
  term.blit(title:gsub(".", offsetChar), ("f"):rep(w), ("8"):rep(w))
end

local function genProgress(id, from, msg, title)
  term.redirect(win)
  win.setVisible(false)
  local w, h = term.getSize()
  term.setCursorBlink(false)
  local progress = math.ceil(w/2 * (id/from))
  local bg = string.char(getBlockIDByName("stone")+0x60):rep(w)
  local bar = string.char(getBlockIDByName("leaves")+0x60):rep(progress)

  for i=1, h do
    term.setCursorPos(1, i)
    term.blit(bg, ("f"):rep(w), ("f"):rep(w))
  end

  term.setCursorPos(math.floor(w*0.25), math.floor(h/2))
  term.blit(bar, ("f"):rep(#bar), ("f"):rep(#bar))
  term.setCursorPos(1, h)

  local fmsg = string.format("%s %d/%d", msg or "Generating Chunk", id, from)
  term.setCursorPos(math.floor(w*0.5 - (#fmsg/2)), math.floor(h/2)-1)
  term.blit(fmsg:gsub(".", offsetChar), ("f"):rep(#fmsg), ("8"):rep(#fmsg))

  if title then drawTitle(title) end

  term.setCursorPos(1, 4)
  win.setVisible(true)
  term.redirect(oldTerm)

  term.setCursorPos(1, 4)
end

local lastYield = epoch("utc")
local function ensureTimeSafety()
  if epoch("utc") - lastYield > 4000 then
    sleep(0)
    lastYield = epoch("utc")
  end
end

------ Map functions ------
-- map[chunkID][rowID] = "256 char string"
-- map storage format:
-- header '\xFF' "MIMMAP" '\xFF' -- 8 bytes
-- version (number) -- 1 byte; the version the map was saved on
-- playerx (number) -- 2 bytes; the player's X coordinate
-- playery (number) -- 1 byte; the player's Y coordinate
-- seed (number) -- 8 bytes; the map seed
-- nchunk (number) -- 1 byte; the number of chunks stored in the file
-- heightmap -- 256^2 bytes; the heightmap used in world generation
-- for each chunk:
--    x -- 1 byte; signed chunk ID
--    256x Row
--    each Row is a RLE byte sequence totaling 256 bytes when uncompressed.
local map = {}
local seed = 0
local heightmap = {}

local HEADER = "\xFFMIMMAP\xFF"
local VERSION = 1

local function loadMap(path)
  local handle = assert(io.open(path, "rb"))

  if handle:read(#HEADER) ~= HEADER then
    error("invalid map header; not " .. HEADER, 0)
  end

  if handle:read(1):byte() ~= VERSION then
    error("invalid map version; not " .. VERSION, 0)
  end

  player.x = string.unpack("<i2", handle:read(2))
  player.y = handle:read(1):byte()

  -- map seed
  seed = string.unpack("<I8", handle:read(8))

  local title = "Loading " .. path

  for i=BEGIN, END do
    if i%256==0 then
      genProgress(i+END, 65536, "Reading Heightmap", title)
    end

    heightmap[i] = handle:read(1):byte()
  end

  local nchunk = handle:read(1):byte() + 1

  map = {}
  for ri=1, nchunk do
    ensureTimeSafety()
    if ri%8==0 then
      genProgress(ri, 256, "Loading Chunks", title)
    end

    local rawid = handle:read(1)
    if not rawid then break end

    local id = string.unpack("b", rawid)
    map[id] = {}

    for i=1, 256 do
      local row = {}

      repeat
        local count = (handle:read(1) or ""):byte()
        if not count then break end
        local tile = handle:read(1):byte()
        for _=1, count + 1 do
          row[#row+1] = tile
        end
      until #row >= 256

      if #row ~= 256 then
        error(id .. ',' .. i .. ',' .. #row)
      end

      map[id][i] = row
    end
  end
end

local function saveMap(path)
  local handle = assert(io.open(path, "wb"))
  handle:write(HEADER ..
    string.pack("<I1i2I1I8", VERSION, player.x, player.y, seed))

  local title = "Saving " .. path

  for i=BEGIN, END do
    if i%256==0 then
      genProgress(i+END, 65536, "Writing Heightmap", title)
    end

    handle:write(string.char(heightmap[i]))
  end

  local nchunk = -1
  for id=-128, 127 do
    if map[id] then
      nchunk = nchunk + 1
    end
  end

  handle:write(string.char(nchunk))

  for id=-128, 127 do
    ensureTimeSafety()

    if id%8==0 then
      genProgress(id+129, 256, "Saving Chunks", title)
    end

    if map[id] then
      handle:write(string.pack("b", id))

      for r=1, 256, 1 do
        local row = map[id][r]

        while #row > 0 do
          local char = row[1]
          local i = 1

          while row[i] == char do
            i = i + 1
          end

          row = {table.unpack(row, i)}

          handle:write(string.pack("BB", i-2, char))
        end
      end
    end
  end

  handle:close()
end

local function getStrip(t, y, x1, x2)
  local chunk1, chunk2 = math.ceil(x1 / 256), math.ceil(x2 / 256)
  local offset1, offset2 = x1 - (chunk1 * 256) - 1, x2 - (chunk2 * 256) - 1

  if offset1 < 0 then
    offset1 = 256 + offset1
  end

  if offset2 < 0 then
    offset2 = 256 + offset2
  end

  local strip = {}

  local diff = chunk2 - chunk1
  for i=offset1, 256 do
    strip[#strip+1] = t[chunk1][y][i]
  end

  if diff > 1 then
    for i=chunk1+1, chunk2-1 do
      for j=1, 256 do
        strip[#strip+1] = t[i][y][j]
      end
    end
  end

  for i=1, 256 + offset2 do
    strip[#strip+1] = t[chunk2][y][i]
  end

  return strip
end

local function setItem(t, x, y, thing)
  x = x - 1
  if x < BEGIN or x > END-256 then return end
  if y < 2 or y > 256 then return end

  local chunk = math.ceil(x / 256)
  local diff = x - (chunk * 256)
  local layer = t[chunk][y]

  if diff < 0 then diff = diff + 256 end

  layer[diff] = thing
--[[
  if diff == -256 then
    layer[1] = thing
--    t[chunk][y] = thing .. layer:sub(2)
  elseif diff == 0 then
    layer[#layer] = thing
--    t[chunk][y] = layer:sub(0, diff - 2) .. thing
  else
    layer[diff-1] = thing
--    t[chunk][y] = (layer:sub(0, diff - 2) .. thing .. layer:sub(diff))
  end--]]

  if #t[chunk][y] ~= 256 then
    error(diff)
  end
end

local function getBlockStrip(y, x1, x2)
  return getStrip(map, y, x1, x2)
end

local function getBlock(x, y)
  return getStrip(map, y, x, x)[1]
end

local function getBlockInfo(x, y)
  return blocks[getBlock(x, y)]
end

local function setBlock(x, y, id)
  return setItem(map, x, y, getBlockIDByName(id))
end

------ Lighting ------
-- this is similar to the map, but stores light levels and is not stored.
local lightmap = {}

local function getLightStrip(y, x1, x2)
  return getStrip(lightmap, y, x1, x2)
end

local function initializeLightMap()
  for chunk=-128, 127 do
    lightmap[chunk] = lightmap[chunk] or {}
    for y=1, 256 do
      local row = {}
      for x=1, 256 do
        row[x] = "f"
      end

      lightmap[chunk][y] = row
    end
  end
end

local levels = {}
for i=0, 15 do
  levels[i] = string.format("%x", i)
end

local function updateLightMap(xe, ye, xr, yr)
  if NO_LIGHT then return end

  -- only processes subsections of the map for efficiency reasons.
  local w, h = term.getSize()
  local RADIUS = math.ceil(w / 2) + 15
  local YRADIUS = math.ceil(h / 2) + 15

  local XBASE, YBASE = player.x, player.y

  if xe and ye and xr and yr then
    XBASE, YBASE, RADIUS, YRADIUS = xe, ye, xr, yr
  end

  local torch = getBlockIDByName("torch")
  local sources = {}
  local cache = {}

  -- find torches
  for y=math.max(1, YBASE - YRADIUS), 256 do
    sources[y] = {}
    local blockstrip = getBlockStrip(y, XBASE - RADIUS, XBASE + RADIUS)
    cache[y] = blockstrip
    for i=1, #blockstrip do
      if blockstrip[i] == torch then
        sources[y][XBASE - RADIUS + i - 1] = {XBASE - RADIUS + i - 1, y}
      end
    end
  end

  -- find skylight
  for x=1, RADIUS + RADIUS + 1 do
    for y=256, math.max(1, YBASE - YRADIUS), -1 do
      local id = cache[y][x]
      if not blocks[id].transparent then
        break
      else
        sources[y][XBASE - RADIUS + x - 1] = {XBASE - RADIUS + x - 1, y}
      end
    end
  end

  local pcache = {}

  -- propagate light: stage 1
  for y=math.min(256, YBASE + YRADIUS),
      math.max(1, YBASE - YRADIUS), -1 do
    pcache[y] = {}
    local py = pcache[y]
    local pp = pcache[y+1]

    for x=XBASE - RADIUS, XBASE + RADIUS do
      if sources[y] and sources[y][x] then
        setItem(lightmap, x, y, levels[15])
        py[x] = 15

      else
        if py and py[x-1] then
          py[x] = math.max(py[x] or 0, py[x-1] - 1)
          setItem(lightmap, x, y, levels[py[x]] or "0")
        end

        if pp and pp[x] then
          py[x] = math.max(py[x] or 0, pp[x] - 1)
          setItem(lightmap, x, y, levels[py[x]] or "0")
        end
      end
    end
  end

  -- propagate light: stage 2
  for y=math.max(1, YBASE - YRADIUS), math.min(256, YBASE + YRADIUS), 1 do
    local py = pcache[y]
    local pm = pcache[y-1]

    for x=XBASE + RADIUS, XBASE - RADIUS, -1 do
      if pm and pm[x] then
        py[x] = math.max(py[x] or -1, pm[x] - 1)
        setItem(lightmap, x, y, levels[py[x]] or "0")
      end

      if py and py[x+1] then
        py[x] = math.max(py[x] or -1, py[x+1] - 1)
        setItem(lightmap, x, y, levels[py[x]] or "0")
      end
    end
  end
end

------ Terrain Generation ------

local function smooth(tab, passes, radius, min, max)
  min = min or BEGIN
  max = max or END
  for _=1, passes do
    for i=min, max do
      local heightSum, heightCount = 0, 0

      for n=i-radius, i + radius + 1 do
        if tab[n] then
          local neighborHeight = tab[n]
          heightSum = heightSum + neighborHeight
          heightCount = heightCount + 1
        end
      end

      local heightAverage = heightSum / heightCount
      tab[i] = math.floor(heightAverage + 0.5)
    end
  end

  return tab
end

-- heightmap, ported from https://www.codementor.io's heightmap tutorial
local function genHeightmap(hm, minY, maxY)
  local SCAN_RADIUS = 5
  local SMOOTH_PASSES = 3

  hm = hm or {}

  for i=BEGIN, END do
    hm[i] = math.random(minY or 50, maxY or 150)
  end

  smooth(hm, SMOOTH_PASSES, SCAN_RADIUS)

  return hm
end

local function populateChunk(id)
  ensureTimeSafety()

  if id % 8 == 0 then
    genProgress(id+129, 256, "Populating Chunks", "Generating World")
  end

  local air = getBlockIDByName("air")
  local bedrock = getBlockIDByName("bedrock")
  local stone = getBlockIDByName("stone")
  local dirt = getBlockIDByName("dirt")
  local grass = getBlockIDByName("grass")

  local offset = id * 256
  local DIRT_DEPTH = 5

  for i=1, 256 do
    map[id][i] = {}
  end

  for col=1, 256 do
    local height = heightmap[offset + col]

    for i=1, height - DIRT_DEPTH do
      map[id][i][col] = stone
    end

    for i=height - (DIRT_DEPTH - 1), height - 1 do
      map[id][i][col] = dirt
    end

    map[id][height][col] = grass

    for i=height+1, 256, 1 do
      map[id][i][col] = air
    end
  end

  for i=1, 256 do
    map[id][1][i] = bedrock
  end
end

local function populateCaves(id)
  ensureTimeSafety()

  if id % 8 == 0 then
    genProgress(id+129, 256, "Carving Caves", "Generating World")
  end

  local ncave = math.random(1, 40)
  local offset = id * 256

  for _=1, ncave do
    local cx, cy = math.random(1, 256), math.random(10, 150)
    local height = math.random(10, 20)
    local widths = {}

    for _=1, 3 do
      widths[#widths+1] = 0
    end

    for _=1, height-6 do
      widths[#widths+1] = math.random(8, 48)
    end

    for _=1, 3 do
      widths[#widths+1] = 0
    end

    term.setCursorPos(1, 4)
    smooth(widths, 4, 1, 1, #widths)

    for i=1, #widths - 4 do
      local w = widths[i]
      local half = math.floor(w/2)
      local xp, yp = cx - half, cy + i
      for xo=1, w, 1 do
        setBlock(offset+xp+xo-1, yp, "air")
      end
    end
  end
end

local function placeOres(id)
  ensureTimeSafety()

  if id % 8 == 0 then
    genProgress(id+129, 256, "Placing Ores", "Generating World")
  end

  local stone = getBlockIDByName("stone")

  local info = {
    coal = {
      -- maximum level at which this can generate
      max = 256,
      -- minimum level ^^^
      min = 40,
      -- optimum level
      optimum = 80,
      -- rate% of stone is replaced with this ore at the optimum level
      rate = 1,
      -- the tile
      tile = getBlockIDByName("coal_ore")
  },

    iron = {
      max = 256,
      min = 32,
      optimum = 60,
      rate = 0.5,
      tile = getBlockIDByName("iron_ore")
    },

    diamond = {
      max = 32,
      min = 2,
      optimum = 11,
      rate = 0.2,
      tile = getBlockIDByName("diamond_ore")
    },

    redstone = {
      max = 36,
      min = 2,
      optimum = 14,
      rate = 0.4,
      tile = getBlockIDByName("redstone_ore")
    },

    gold = {
      max = 46,
      min = 4,
      optimum = 25,
      rate = 0.3,
      tile = getBlockIDByName("gold_ore")
    }
  }

  -- Ore distribution dropoff is linear for now, but this may change
  -- in the future.
  for _, v in pairs(info) do
    for y=1, 256, 1 do
      if y > v.min and y < v.max then
        local diff = math.abs(y - v.optimum)
        local distUp, distDown = v.max - v.optimum, v.optimum - v.min

        local percent
        if y > v.optimum then
          percent = diff/distUp * (v.rate/10)
        else
          percent = diff/distDown * (v.rate/10)
        end

        local layer = map[id][y]

        local chance = percent
        local multiplier = 1
        repeat
          multiplier = multiplier * 10
          chance = chance * 10
        until math.floor(chance) == chance or multiplier > 10000

        for i=1, #layer do
          if layer[i] == stone then
            if math.random(1, multiplier) <= chance then
              layer[i] = v.tile
            end
          end
        end
      end
    end
  end
end

------ Physics ------
local function tryMovePartial(x, y)
  local moved

  local newX, newY = player.x + x, player.y + y

  local nxHead, nxFoot = getBlockInfo(newX, player.y + 1).physics,
    getBlockInfo(newX, player.y).physics

  if nxHead ~= p_solid and nxFoot ~= p_solid then
    player.x = newX
    moved = true
  end

  local nyHead, nyFoot = getBlockInfo(newX, newY + 1).physics,
    getBlockInfo(newX, newY).physics

  if nyHead ~= p_solid and nyFoot ~= p_solid then
    player.y = newY
    moved = true
  end

  return moved
end

local function tryMove()
  local moved = false
  local physicsType = getBlockInfo(player.x, player.y - 1).physics

  if physicsType == p_air then
    player.motion.y = math.max(-2, player.motion.y - 1)
  elseif physicsType == p_liquid then
    player.motion.y = math.max(-1, player.motion.y - 1)
  elseif physicsType == p_solid then
    player.motion.y = math.max(0, player.motion.y)
  end

  local mx, my = player.motion.x, player.motion.y

  for _=1, math.abs(mx) do
    local m = tryMovePartial(mx/math.abs(mx), 0)
    moved = moved or m
  end

  for _=1, math.abs(my) do
    local m = tryMovePartial(0, my/math.abs(my))
    moved = moved or m
  end

  if moved then
    updateLightMap()
  end
end

------ Graphics ------
local function draw()
  win.reposition(1, 1, oldTerm.getSize())
  term.redirect(win)

  win.setVisible(false)

  term.setCursorBlink(false)

  local w, h = term.getSize()
  local halfW, halfH = math.floor(w/2), math.floor(h/2)

  for y = player.y - halfH, player.y + halfH, 1 do
    if y > 0 and y <= 256 then
      local _block = getBlockStrip(y, player.x - halfW, player.x + halfW)
      local light = table.concat(
        getLightStrip(y, player.x - halfW, player.x + halfW))

      local block = ""

      for i=1, #_block do
        block = block .. string.char(blocks[_block[i]].tex)
      end

      term.setCursorPos(1, h - (y - player.y + halfH))
      if #block ~= #light then
        print(#block, #light)
      end
      term.blit(block, light, light)

    else
      term.setCursorPos(1, h - (y - player.y + halfH))
      local col = string.format("%x", math.max(0, y + 12))
      term.blit(string.char(blocks[0].tex):rep(w), (col):rep(w), (col):rep(w))
    end
  end

  term.setCursorPos(halfW + 1, halfH + 1)
  local lightTop, lightBot = getStrip(lightmap, player.y + 1, player.x,
    player.x), getStrip(lightmap, player.y, player.x, player.x)
  term.blit("\xFE", lightTop[1], "F")
  term.setCursorPos(halfW + 1, halfH)
  term.blit("\xFD", lightBot[1], "F")

  -- [=[
  for i=1, #player.inventory do
    term.setCursorPos(1, i)
    local slot = player.inventory[i]

    win.blit(string.char(slot[1]+0x60), "F", "F")

    if player.selected == i then
      term.setBackgroundColor(2^15)
    else
      term.setBackgroundColor(2^10)
    end

    term.write((" "..blocks[slot[1]].name.." x"..slot[2]):gsub(".", offsetChar))
  end--]=]

  term.setCursorPos(halfW + player.look.x + 1, halfH - player.look.y)
  term.setCursorBlink(true)

  win.setVisible(true)

  term.redirect(oldTerm)
end

local oldPalette = {}

for i=0, 15 do
  oldPalette[i] = {term.getPaletteColor(2^i)}
  win.setPaletteColor(2^i, i/15, i/15, i/15)
  term.setPaletteColor(2^i, i/15, i/15, i/15)
end

local function generateMap(mapName, caves)
  math.randomseed(seed)

  genHeightmap(heightmap)

  for i=-128, 127 do
    map[i] = {}
    populateChunk(i)
  end

  for i=-128, 127 do
    placeOres(i)
  end

  if caves then
    for i=-128, 127 do
      populateCaves(i)
    end
  end

  player.y = heightmap[player.x] + 50
  saveMap(mapName)
end

local function menu(opts, title)
  local w, h
  local dirt = string.char(getBlockIDByName("dirt")+0x60)
  local focused = 0
  local scroll = 0

  while true do
    w, h = term.getSize()
    win.reposition(1, 1, w, h)
    term.redirect(win)
    win.setVisible(false)

    for i=1, h do
      term.setCursorPos(1, i)
      term.blit(dirt:rep(w), ("f"):rep(w), ("f"):rep(w))
    end

    local watching = {}

    for i=1, #opts, 1 do
      local pos = math.floor(w/4)
      if opts[i].button then
        drawButton(pos, i*4+scroll, strings.ensure_width(opts[i].text,
          math.floor(w/2)))
      elseif opts[i].input then
        if not opts[focused] then focused = i end

        drawInput(pos, i*4+scroll, strings.ensure_width(
          opts[i].text .. (focused == i and "_" or ""),
          math.floor(w/2)))
      end
      watching[i] = {pos, i*4+scroll-1}
    end

    drawTitle(title)

    win.setVisible(true)
    term.redirect(oldTerm)

    local event = table.pack(pullEvent())
    if event[1] == "char" then
      if opts[focused] then
        opts[focused].text = opts[focused].text .. event[2]
      end

    elseif event[1] == "key" then
      if event[2] == keys.backspace then
        if opts[focused] and #opts[focused].text > 0 then
          opts[focused].text = opts[focused].text:sub(1, -2)
        end
      end

    elseif event[1] == "mouse_click" then
      for i=1, #watching do
        local b = watching[i]
        if event[3] > b[1] and event[3] <= b[1] + math.floor(w/2)
            and event[4] > b[2] and event[4] <= b[2] + 3 then
          if opts[i].button then
            if opts[i].action(opts[i], opts) then return end

          else
            focused = i
          end
        end
      end

    elseif event[1] == "mouse_scroll" then
      scroll = math.min(0, scroll - event[2])
    end
  end
end


local function beginGame(mapName)
  if fs.exists(mapName) then
    term.clear()
    term.setCursorPos(1, 1)
    print("Loading World")
    loadMap(mapName)

  else
    seed = epoch("utc")
    generateMap(mapName)
  end

  local id = startTimer(TICK_TIME)
  local lastUpdate = 0

  initializeLightMap()
  updateLightMap()

  while true do
    local evt = table.pack(pullEvent())

    if evt[1] == "timer" and evt[2] == id then
      id = startTimer(TICK_TIME)

    elseif evt[1] == "key" then
      if evt[2] == keys.w then
        local pAbove = getBlockInfo(player.x, player.y + 2).physics
        local pBelow = getBlockInfo(player.x, player.y - 1).physics

        if pBelow ~= p_air then
          if pAbove == p_air then
            player.motion.y = 2

          elseif pAbove == p_liquid then
            player.motion.y = 1
          end
        end

      elseif evt[2] == keys.s and not evt[3] then
        player.motion.y = -1

      elseif evt[2] == keys.a and not evt[3] then
        player.motion.x = -1

      elseif evt[2] == keys.d and not evt[3] then
        player.motion.x = 1

      elseif evt[2] == keys.up then
        player.look.y = math.min(3, player.look.y + 1)

      elseif evt[2] == keys.down then
        player.look.y = math.max(-3, player.look.y - 1)

      elseif evt[2] == keys.right then
        player.look.x = math.min(3, player.look.x + 1)

      elseif evt[2] == keys.left then
        player.look.x = math.max(-3, player.look.x - 1)

      elseif evt[2] == keys.r then
        local bx, by = player.x + player.look.x,
          player.y + player.look.y + 1
        local bid = getBlock(bx, by)

        if bid > 0 then
          for i=1, #player.inventory, 1 do
            local slot = player.inventory[i]

            if slot[1] == bid then
              slot[2] = slot[2] + 1
              break
            end

            if i == #player.inventory then
              player.inventory[#player.inventory+1] = {bid, 1}
            end
          end
        end

        setBlock(bx, by, "air")
        updateLightMap()

      elseif evt[2] == keys.f then
        local bx, by = player.x + player.look.x,
          player.y + player.look.y + 1

        if getBlock(bx, by) == 0 then
          local slot = player.inventory[player.selected]
          slot[2] = slot[2] - 1
          setBlock(bx, by, blocks[slot[1]].name)
          if slot[2] == 0 then
            table.remove(player.inventory, player.selected)
            player.selected = math.max(#player.inventory, player.selected)
          end
        end

        updateLightMap()

      elseif evt[2] == keys.q then
        local quit = false
        local options = {
          {text = "Resume", button = true, action = function()
            return true
          end},
          {text = "Save and Quit", button = true, action = function()
            quit = true
            return true
          end}
        }

        menu(options, "Paused")
        if quit then
          break
        end
      end

    elseif evt[1] == "char" then
      if tonumber(evt[2]) then
        local n = tonumber(evt[2])
        if player.inventory[n] then
          player.selected = n
        end
      end

    elseif evt[1] == "key_up" then
      if evt[2] == keys.a or evt[2] == keys.d then
        player.motion.x = 0
      end
    end

    if epoch("utc") - lastUpdate >= 1000*TICK_TIME then
      draw()
      tryMove()
      lastUpdate = epoch("utc")
    end
  end

  term.clear()
  term.setCursorPos(1,1)
  print("Saving World")
  saveMap(mapName)
end

local maps = ".mim2"
fs.makeDir(maps)

local function createMap()
  local caves = true
  local opts = {
    {text = "", input = true},
    {text = "", input = true},
    {text = "Generate Caves: Yes", button = true, action = function(self)
      caves = not caves
      self.text = "Generate Caves: " .. (caves and "Yes" or "No")
    end},
    {text = "Done", button = true, action = function(_, opt)
      if not tonumber(opt[2].text) then
        opt[2].text = tostring(epoch("utc"))
      end
      return #opt[1].text > 0 and tonumber(opt[2].text)
    end},
    {text = "Cancel", button = true, action = function() return true end}
  }

  menu(opts, "Create World")

  local name
  name, seed = opts[1].text, tonumber(opts[2].text)
  if not seed then return end
  generateMap(maps.."/"..name, caves)
  beginGame(maps.."/"..name)
end

local mainMenu = {
  {text = "Play", button = true, action = function()
    local files = fs.list(maps)

    if #files == 0 then
      createMap()
      files = fs.list(maps)
    end

    local run = true
    while run do
      local options = {}
      term.clear()
      term.setCursorPos(1, 1)

      files = fs.list(maps)
      table.sort(files)
      for i=1, #files, 1 do
        options[i] = { text = files[i], button = true, action = function(self)
          local opts = {
            {text = "Begin Game", button = true, action = function()
              beginGame(files[i])
              return true
            end},

            {text = "Delete Map", button = true, action = function()
              menu({
                {text = "Yes", button = true, action = function()
                  fs.delete(files[i])
                  return true
                end},

                {text = "No", button = true, action = function()
                  return true
                end},
              }, "Really Delete " .. self.text .. "?")

              return true
            end},

            {text = "Back", button = true, action = function()
              return true
            end}
          }

          menu(opts, self.text)
          return true
        end }
        files[i] = maps.."/"..files[i]
      end

      options[#options+1] = {
        text = "Create",
        button = true,
        action = function()
          createMap()
          return true
        end
      }

      options[#options+1] = {
        text = "Back", button = true, action = function()
          run = false
          return true
        end
      }

      menu(options, "Select World")
    end
  end},

  {text = "Lighting: " .. (NO_LIGHT and "Off" or "On"),
    button = true, action = function(self)
      NO_LIGHT = not NO_LIGHT
      settings.set("mim2.no_lighting", NO_LIGHT)
      self.text = "Lighting: " .. (NO_LIGHT and "Off" or "On")
    end
  },

  {text = "Quit", button = true, action = function()
    return true
  end}
}

menu(mainMenu, "Minecraft-in-Minecraft 2")

term.clear()
term.setCursorPos(1, 1)

for i=0, 15 do
  term.setPaletteColor(2^i, table.unpack(oldPalette[i]))
end
