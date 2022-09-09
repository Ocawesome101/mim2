-- Minecraft-in-Minecraft 2
-- A spiritual successor to Casper7526's "mim" from a decade ago.
-- Hopefully written significantly better.

-- Supports Recrafted!
local term = rawget(_G, "term") or require("term")
local window = rawget(_G, "window") or require("window")

local pullEvent, sleep
if not rawget(os, "pullEvent") then
  local rc = require("rc")
  pullEvent, sleep = rc.pullEventRaw, rc.sleep
else
  pullEvent, sleep = rawget(os, "pullEventRaw"), rawget(os, "sleep")
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
    physics = p_air,      -- physics type
    transparent = true,   -- lets light through?
  },
  [1] = {
    name = "bedrock",
    tex = 0x61,
    physics = p_solid,
    transparent = false,
  },
  [2] = {
    name = "stone",
    tex = 0x62,
    physics = p_solid,
    transparent = false
  }
}

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

local function getBlockStrip(y, x1, x2)
  local chunk1, chunk2 = math.floor(x1 / 256), math.floor(x2 / 256)
  local offset1, offset2 = x1 - (chunk1 * 256), x2 - (chunk2 * 256)

  if chunk1 == chunk2 then
    return map[chunk1][y]:sub(offset1, offset2)

  else
    local diff = chunk2 - chunk1
    local begin, _end =
      map[chunk1][y]:sub(offset1),
      map[chunk2][y]:sub(1, offset2)

    local middle = ""

    if diff > 1 then
      for i=chunk1+1, chunk2-1 do
        middle = middle .. map[i][y]
      end
    end

    return begin .. middle .. _end
  end
end

local function getLightMap(_, x1, x2)
  return ("f"):rep(x2 - x1 + 1)
end

------ Terrain Generation ------
local function populateChunk(id)
  local air = string.char(blocks[0].tex):rep(256)
  local bedrock = string.char(blocks[1].tex):rep(256)
  for i=1, 253, 1 do
    map[id][i] = air
  end
  for i=254, 156 do
    map[id][i] = bedrock
  end
end

------ Graphics functions ------
local player = {
  x = 64, y = 8
}

--local oldTerm = term.current()
--local win = window.create(oldTerm, 1, 1, oldTerm.getSize())

local function draw()
--  win.reposition(1, 1, oldTerm.getSize())
  --term.redirect(win)

--  win.setVisible(false)

  local w, h = term.getSize()
  local halfW, halfH = math.floor(w/2), math.ceil(h/2)

  for y = player.y - halfH, player.y + halfH, 1 do
    if y > 0 and y <= 256 then
      local block = getBlockStrip(y, player.x - halfW, player.x + halfW)
      local light = getLightMap(y, player.x - halfW, player.x + halfW)

      --print(h - (y - player.y + halfH))
      term.setCursorPos(1, h - (y - player.y + halfH))
      term.blit(block, light, light)
    end
  end

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

draw()
