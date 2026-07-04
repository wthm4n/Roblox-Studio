local junk = {}

for i = 1, 10 do
    junk[i] = tostring(i) .. "_" .. string.char(65 + (i % 26))
end

local function randomNoise(n)
    local s = ""
    for i = 1, n do
        s = s .. string.char(97 + ((i * 13) % 26))
    end
    return s
end

junk.noise = randomNoise(16)
junk.meta = { enabled = true, count = #junk }

return junk
