local Customs = {}

local TOKEN_LENGTH = 32
local TOKEN_CHARSET = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"
local TOKEN_PATTERN = "^[%w_%-%]+$"

function Customs.generateToken(length)
    length = length or TOKEN_LENGTH
    local tokenChars = {}

    for i = 1, length do
        local index = math.random(1, #TOKEN_CHARSET)
        tokenChars[i] = TOKEN_CHARSET:sub(index, index)
    end

    return table.concat(tokenChars)
end

function Customs.isValidToken(token)
    if typeof(token) ~= "string" then
        return false
    end

    if #token ~= TOKEN_LENGTH then
        return false
    end

    return token:match(TOKEN_PATTERN) ~= nil
end

function Customs.testToken(token)
    if typeof(token) ~= "string" then
        return false, "Token must be a string"
    end

    if token == "" then
        return false, "Token is empty"
    end

    if token:match(TOKEN_PATTERN) == nil then
        return false, "Token contains invalid characters"
    end

    return true, "Token format is valid"
end

return Customs
