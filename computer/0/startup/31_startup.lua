local native = term.current()

local _w=native.write

local function sub(c)
  return string.char(math.max(0, string.byte(c) - 32))
end

function native.write(t)
  return _w((t:gsub(".", sub)))
end
