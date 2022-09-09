local native = term.current()

local _w=native.write
local _b=native.blit

local function sub(c)
  return string.char(math.max(0, string.byte(c) - 32))
end

function native.write(t)
  return _w((t:gsub(".", sub)))
end
--[[
function native.blit(t, f, b)
  return _b(t:gsub(".", sub), f, b)
end]]
