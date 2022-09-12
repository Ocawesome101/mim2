-- Minecraft-in-Minecraft 2
-- A spiritual successor to Casper7526's "mim" from a decade ago.
-- Hopefully written significantly better.

-- Supports Recrafted!
local term = rawget(_G, "term") or require("term")
local keys = rawget(_G, "keys") or require("keys")
local fs = rawget(_G, "fs") or require("fs")
local settings = rawget(_G, "settings") or require("settings")
local window = rawget(_G, "window") or require("window")

local NO_LIGHT = settings.get("mim2.no_lighting")
local TICK_TIME = (rawget(_G, "jit") or NO_LIGHT) and 0.1 or 0.2

local pullEvent, startTimer, epoch
if not rawget(os, "pullEvent") then
  local rc = require("rc")
  pullEvent, startTimer, epoch = rc.pullEventRaw, rc.startTimer,
    rc.epoch
else
  pullEvent, startTimer, epoch = rawget(os, "pullEventRaw"),
    rawget(os, "startTimer"), rawget(os, "epoch")
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
  }
}

local function genProgress(id, from, msg)
  local w, h = term.getSize()
  local progress = math.ceil(w/2 * (id/from))
  local bg = string.char(getBlockIDByName("dirt")+0x60):rep(w)
  local bar = string.char(getBlockIDByName("leaves")+0x60):rep(progress)

  for i=1, h do
    term.setCursorPos(1, i)
    term.blit(bg, ("f"):rep(w), ("f"):rep(w))
  end

  term.setCursorPos(math.floor(w*0.25), math.floor(h/2))
  term.blit(bar, ("f"):rep(#bar), ("f"):rep(#bar))
  term.setCursorPos(1, h)
  term.write(string.format("%s %d/%d", msg or "Generating Chunk", id, from))
end

------ Map functions ------
-- map[chunkID][rowID] = "256 char string"
-- map storage format:
-- header '\xFF' "MIMMAP" '\xFF' -- 8 bytes
-- version (number) -- 1 byte; the version the map was saved on
-- playerx (number) -- 2 bytes; the player's X coordinate
-- playery (number) -- 1 byte; the player's Y coordinate
-- seed (number) -- 1 byte; the map seed
-- nchunk (number) -- 1 byte; the number of chunks stored in the file
-- heightmap -- 256^2 bytes; the heightmap used in world generation
-- for each chunk:
--    x -- 1 byte; signed chunk ID
--    256x Row
--    each Row is a RLE byte sequence totaling 256 bytes when uncompressed.
local map = {}
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
  local _ = handle:read(1)

  for i=256*-128, 256*128 do
    if i%256==0 then
      genProgress(i+32768, 65536, "Reading Heightmap")
    end
    heightmap[i] = handle:read(1):byte()
  end

  local nchunk = handle:read(1):byte()

  map = {}
  for ri=1, nchunk do
    if ri%8==0 then
      genProgress(ri+129, 256, "Loading Chunks")
    end
    local rawid = handle:read(1)
    if not rawid then break end

    local id = string.unpack("b", rawid)
    map[id] = {}

    for i=1, 256 do
      local row = ""
      local length = 0

      repeat
        local count = (handle:read(1) or ""):byte()
        if not count then break end
        local tile = handle:read(1):byte()
        row = row .. string.char(tile):rep(count + 1)
        length = length + count + 1
      until length >= 256

      map[id][i] = row
    end
  end
end

local function saveMap(path)
  local handle = assert(io.open(path, "wb"))
  handle:write(HEADER ..
    string.pack("<I1i2I1", VERSION, player.x, player.y, 0))

  for i=256*-128, 256*128 do
    if i%256==0 then
      genProgress(i+32768, 65536, "Writing Heightmap")
    end
    handle:write(string.char(heightmap[i]))
  end

  for id=-128, 127 do
    if id%8==0 then
      genProgress(id+129, 256, "Saving Chunks")
    end
    if map[id] then
      handle:write(string.pack("b", id))
      for r=1, 256, 1 do
        local row = map[id][r]
        while #row > 0 do
          local char = row:sub(1, 1)
          local i = 1
          while row:sub(i, i) == char do
            i = i + 1
          end
          local tiles = row:sub(1, i-1)
          row = row:sub(i)
          handle:write(string.pack("BB", #tiles - 1, char:byte()))
        end
      end
    end
  end

  handle:close()
end

local function getStrip(t, y, x1, x2)
  local chunk1, chunk2 = math.ceil(x1 / 256), math.ceil(x2 / 256)
  local offset1, offset2 = x1 - (chunk1 * 256) - 1, x2 - (chunk2 * 256) - 1

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

local function setItem(t, x, y, thing)
  x = x - 1
  local chunk = math.ceil(x / 256)
  local diff = x - (chunk * 256)
  local layer = t[chunk][y]
  if diff == -256 then
    t[chunk][y] = thing .. layer:sub(2)
  elseif diff == 0 then
    t[chunk][y] = layer:sub(0, diff - 2) .. thing
  else
    t[chunk][y] = (layer:sub(0, diff - 2) .. thing .. layer:sub(diff))
  end
  if #t[chunk][y] ~= 256 then
    error(diff)
  end
end

local function getBlockStrip(y, x1, x2)
  return getStrip(map, y, x1, x2)
end

local function getBlock(x, y)
  return getStrip(map, y, x, x):byte()
end

local function getBlockInfo(x, y)
  return blocks[getBlock(x, y)]
end

local function setBlock(x, y, id)
  return setItem(map, x, y, string.char(getBlockIDByName(id)))
end

------ Lighting ------
-- this is similar to the map, but stores light levels and is not stored.
local lightmap = {}

local function getLightStrip(y, x1, x2)
  return getStrip(lightmap, y, x1, x2)
end

local function initializeLightMap()
  for chunk=-128, 127, 1 do
    lightmap[chunk] = lightmap[chunk] or {}
    for y=1, 256, 1 do
      lightmap[chunk][y] = ("f"):rep(256)
    end
  end
end

local levels = {}
for i=0, 15 do
  levels[i] = string.format("%x", i)
end

local __something = 0
local function sfind(s, b)
  return s:find(b, __something)
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

  local torch = string.char(getBlockIDByName("torch"))
  local sources = {}
  local cache = {}

  -- find torches
  for y=math.max(1, YBASE - YRADIUS), math.min(256, YBASE + YRADIUS) do
    sources[y] = {}
    local blockstrip = getBlockStrip(y, XBASE - RADIUS, XBASE + RADIUS)
    cache[y] = blockstrip
    __something = 0
    for _torch in sfind, blockstrip, torch do
      __something = __something + _torch
      sources[y][XBASE - RADIUS + _torch] = {XBASE - RADIUS + _torch, y}
    end
  end

  -- find skylight
  for x=1, RADIUS + RADIUS + 1 do
    for y=math.min(256, YBASE + YRADIUS), math.max(1, YBASE - YRADIUS), -1 do
      local id = cache[y]:byte(x)
      if not blocks[id].transparent then
        break
      else
        sources[y][XBASE - RADIUS + x] = {XBASE - RADIUS + x, y}
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
--      if sources[y] and sources[y][x] then
--        setItem(lightmap, x, y, levels[15])
--        pcache[y][x] = 15

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

-- heightmap, ported from https://www.codementor.io's heightmap tutorial
local function genHeightmap()
  local SCAN_RADIUS = 5
  local SMOOTH_PASSES = 3
  local BEGIN, END = 256*-128, 256*128

  heightmap = {}

  for i=BEGIN, END do
    heightmap[i] = math.random(50, 150)
  end

  for _=1, SMOOTH_PASSES do
    for i=BEGIN, END do
      local heightSum, heightCount = 0, 0

      for n=i-SCAN_RADIUS, i + SCAN_RADIUS + 1 do
        if n > BEGIN and n <= END then
          local neighborHeight = heightmap[n]
          heightSum = heightSum + neighborHeight
          heightCount = heightCount + 1
        end
      end

      local heightAverage = heightSum / heightCount
      heightmap[i] = math.floor(heightAverage + 0.5)
    end
  end
end

local function populateChunk(id)
  genProgress(id+129, 256)
  local air = string.char(getBlockIDByName("air"))
  local bedrock = string.char(getBlockIDByName("bedrock"))
  local stone = string.char(getBlockIDByName("stone"))
  local dirt = string.char(getBlockIDByName("dirt"))
  local grass = string.char(getBlockIDByName("grass"))

  local DIRT_DEPTH = 5

  local offset = id * 256

  for col=1, 256 do
    local height = heightmap[offset + col]

    for i=1, height - DIRT_DEPTH do
      map[id][i] = (map[id][i] or "") .. stone
    end

    for i=height - (DIRT_DEPTH - 1), height - 1 do
      map[id][i] = (map[id][i] or "") .. dirt
    end

    map[id][height] = (map[id][height] or "") .. grass

    for i=height+1, 256, 1 do
      map[id][i] = (map[id][i] or "") .. air
    end
  end

  map[id][1] = bedrock:rep(256)
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
local oldTerm = term.current()
local win = window.create(oldTerm, 1, 1, oldTerm.getSize())

local function draw()
  win.reposition(1, 1, oldTerm.getSize())
  term.redirect(win)

  win.setVisible(false)

  term.setCursorBlink(false)

  local w, h = term.getSize()
  local halfW, halfH = math.floor(w/2), math.floor(h/2)

  for y = player.y - halfH, player.y + halfH, 1 do
    if y > 0 and y <= 256 then
      local block = getBlockStrip(y, player.x - halfW, player.x + halfW)
      local light = getLightStrip(y, player.x - halfW, player.x + halfW)

      block = block:gsub(".", function(c)
        return string.char(blocks[string.byte(c)].tex)
      end)

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
  term.blit("\xFE", "F", "F")
  term.setCursorPos(halfW + 1, halfH)
  term.blit("\xFD", "F", "F")

  term.setCursorPos(halfW + player.look.x + 1, halfH - player.look.y)
  term.setCursorBlink(true)

  win.setVisible(true)

  term.redirect(oldTerm)
end

for i=0, 15 do
  win.setPaletteColor(2^i, i/15, i/15, i/15)
  term.setPaletteColor(2^i, i/15, i/15, i/15)
end

local function generateMap(mapName, seed)
  math.randomseed(seed)

  genHeightmap()

  for i=-128, 127 do
    map[i] = {}
    populateChunk(i)
  end

  player.y = heightmap[player.x] + 50
  saveMap(mapName)
end

local function beginGame(mapName)
  if fs.exists(mapName) then
    term.clear()
    term.setCursorPos(1, 1)
    print("Loading World")
    loadMap(mapName)

  else
    generateMap(mapName, math.random(0, 255))
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
        setBlock(player.x + player.look.x + 1,
          player.y + player.look.y + 1, "air")
        updateLightMap()

      elseif evt[2] == keys.q then
        pullEvent("char")
        break
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
  print("<Creating Map>")
  local name
  repeat
    io.write("Name> ")
    name = io.read()
  until #name > 1

  local seed
  repeat
    io.write("Seed> ")
    seed = tonumber(io.read())
  until seed

  generateMap(maps.."/"..name, seed)
end

local files = fs.list(maps)

if #files == 0 then
  createMap()
  files = fs.list(maps)
end

while true do
  print("<Minecraft-in-Minecraft 2>")
  term.clear()
  term.setCursorPos(1, 1)

  files = fs.list(maps)
  table.sort(files)
  for i=1, #files, 1 do
    files[i] = maps.."/"..files[i]
    print(i, files[i])
  end

  print(#files+1, "[Create Map]")
  print(#files+2, "[Quit]")

  local num
  repeat
    io.write("MiM2> ")
    num = tonumber(io.read())
    if num == #files + 1 then
      createMap()
      break
    elseif num == #files + 2 then
      break
    end
  until num and files[num]

  if num and files[num] then
    beginGame(files[num])
  elseif num == #files + 2 then
    break
  end
end
