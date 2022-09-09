-- Minecraft-in-Minecraft 2
-- A spiritual successor to Casper7526's "mim" from a decade ago.
-- Hopefully written significantly better.

-- Supports Recrafted!
local term = rawget(_G, "term") or require("term")
local keys = rawget(_G, "keys") or require("keys")
local window = rawget(_G, "window") or require("window")

local pullEvent, startTimer, cancelTimer
if not rawget(os, "pullEvent") then
  local rc = require("rc")
  pullEvent, startTimer, cancelTimer = rc.pullEventRaw, rc.startTimer,
    rc.cancelTimer
else
  pullEvent, startTimer, cancelTimer = rawget(os, "pullEventRaw"),
    rawget(os, "startTimer"), rawget(os, "cancelTimer")
end

print("Please ensure that the necessary custom font is installed.")
print("If it is, then the following text will appear as a row of blocks:")
for i=0x80, 0x8F do
  io.write(string.char(i))
end
print("\nIf it does not appear as a row of blocks, install the font or game graphics will be garbled.  Font installation instructions are in the Minecraft-in-Minecraft 2 README file.\n")
print("If the font IS present, press Enter to continue.")
print("Otherwise, hold Ctrl-T to stop the program.")

do local _ = io.read() end

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
  }
}

local function getBlockIDByName(name)
  for i=0, #blocks, 1 do
    if blocks[i].name == name then
      return i
    end
  end
end


------ Map functions ------
-- map[chunkID][rowID] = "256 char string"
-- map storage format:
-- header '\xFF' "MIMMAP" '\xFF' -- 8 bytes
-- version (number) -- 1 byte; the version the map was saved on
-- nchunk (number) -- 1 byte; the number of chunks stored in the file
-- for each chunk:
--    x -- 1 byte; signed chunk ID
--    256x Row
--    each Row is a RLE byte sequence totaling 256 bytes when uncompressed.
local map = {}

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

  local nchunk = handle:read(1):byte()

  map = {}
  for _=1, nchunk do
    local id = string.unpack("b", handle:read(1))
    map[id] = {}

    for i=1, 256 do
      local row = ""
      local length = 0

      repeat
        local count = handle:read(1):byte()
        local tile = handle:read(1):byte()
        row = row .. string.char(tile):rep(count)
      until length >= 256

      map[id][i] = row
    end
  end
end

local function saveMap(path)
  local handle = assert(io.open(path, "wb"))
  handle:write(HEADER .. string.char(VERSION))

  for id=-128, 127 do
    if map[id] then
      handle:write(string.pack("b", id))
      for r=1, 256, 1 do
        local row = map[id][r]
        while #row > 0 do
          local char = row:sub(1, 1)
          local tiles = row:match("%"..char.."+")
          row = row:sub(#tiles + 1)
          handle:write(string.pack("BB", #tiles, char:byte()))
        end
      end
    end
  end

  handle:close()
end

local function getStrip(t, y, x1, x2)
  local chunk1, chunk2 = math.floor(x1 / 256), math.floor(x2 / 256)
  local offset1, offset2 = x1 - (chunk1 * 256), x2 - (chunk2 * 256)

  if chunk1 == chunk2 then
    return t[chunk1][y]:sub(offset1, offset2)

  else
    local diff = chunk2 - chunk1
    local begin, _end =
      t[chunk1][y]:sub(offset1),
      t[chunk2][y]:sub(1, offset2)

    local middle = ""

    if diff > 1 then
      for i=chunk1+1, chunk2-1 do
        middle = middle .. t[i][y]
      end
    end

    return begin .. middle .. _end
  end

end

local function getBlockStrip(y, x1, x2)
  return getStrip(map, y, x1, x2)
end

local function getBlock(x, y)
  return getStrip(map, y, x, x):byte()
end

local function getBlockName(x, y)
  return blocks[getBlock(x, y)].name
end

------ Lighting ------
-- this is similar to the map, but stores light levels and is not stored.
local lightmap = {}

local function getLightStrip(y, x1, x2)
  return getStrip(lightmap, y, x1, x2)
end

local function updateLightMap()
  for chunk=-128, 127, 1 do
    if map[chunk] then
      lightmap[chunk] = lightmap[chunk] or {}
      for y=1, 256, 1 do
        lightmap[chunk][y] = ("f"):rep(256)
      end
    end
  end
end

------ Terrain Generation ------
local function populateChunk(id)
  local air = string.char(getBlockIDByName("air")):rep(256)
  local bedrock = string.char(getBlockIDByName("bedrock")):rep(256)
  local stone = string.char(getBlockIDByName("stone")):rep(256)
  local dirt = string.char(getBlockIDByName("dirt")):rep(256)
  local grass = string.char(getBlockIDByName("grass")):rep(256)
  for i=1, 55, 1 do
    map[id][i] = stone
  end
  for i=56, 64, 1 do
    map[id][i] = dirt
  end
  map[id][64] = grass
  for i=65, 256, 1 do
    map[id][i] = air
  end
  map[id][1] = bedrock
end

------ Physics ------
local player = {
  x = 64, y = 66,
  motion = {
    x = 0, y = 0
  }
}

local function tryMove()
  local newX, newY = player.x + player.motion.x, player.y + player.motion.y
  local newBlockHead = getBlockName(newX, newY + 1)
  local newBlockFoot = getBlockName(newX, newY)

  if getBlockName(player.x, player.y - 1) == "air" then
    player.motion.y = math.max(-2, player.motion.y - 1)
  else
    player.motion.y = 0
  end

  if newBlockHead == "air" and newBlockFoot == "air" then
    player.x, player.y = newX, newY
  end
end

------ Graphics ------
--local oldTerm = term.current()
--local win = window.create(oldTerm, 1, 1, oldTerm.getSize())

local function draw()
--  win.reposition(1, 1, oldTerm.getSize())
  --term.redirect(win)

--  win.setVisible(false)

  updateLightMap()

  local w, h = term.getSize()
  local halfW, halfH = math.floor(w/2), math.floor(h/2)

  for y = player.y - halfH, player.y + halfH, 1 do
    if y > 0 and y <= 256 then
      local block = getBlockStrip(y, player.x - halfW, player.x + halfW)
      local light = getLightStrip(y, player.x - halfW, player.x + halfW)


      block = block:gsub(".", function(c)
        return string.char(blocks[string.byte(c)].tex)
      end)

      --print(h - (y - player.y + halfH))
      term.setCursorPos(1, h - (y - player.y + halfH))
      term.blit(block, light, light)
    else
      term.setCursorPos(1, h - (y - player.y + halfH))
      local col = string.format("%x", math.max(0, y + 12))
      term.blit(string.char(blocks[0].tex):rep(w), (col):rep(w), (col):rep(w))
    end
  end

  term.setCursorPos(halfW, halfH)
  term.blit("\xFE", "F", "F")
  term.setCursorPos(halfW, halfH - 1)
  term.blit("\xFD", "F", "F")

  --win.setVisible(true)

--  term.redirect(oldTerm)
end

for i=0, 15 do
  term.setPaletteColor(2^i, i/15, i/15, i/15)
end

for i=-128, 127 do
  map[i] = {}
  populateChunk(i)
end

while true do
  draw()

  local id = startTimer(0.1)
  local evt = table.pack(pullEvent())

  if evt[1] ~= "timer" then
    cancelTimer(id)
  end

  if evt[1] == "key" then
    if evt[2] == keys.w and not evt[3] then
      player.motion.y = 2

    elseif evt[2] == keys.s and not evt[3] then
      player.motion.y = -1

    elseif evt[2] == keys.a then
      player.motion.x = -1

    elseif evt[2] == keys.d then
      player.motion.x = 1
    end

  elseif evt[1] == "key_up" then
    if evt[2] == keys.a or evt[2] == keys.d then
      player.motion.x = 0
    end
  end

  tryMove()
end

term.clear()
term.setCursorPos(1,1)
