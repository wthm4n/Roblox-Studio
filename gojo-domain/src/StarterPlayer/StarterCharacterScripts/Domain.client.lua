--[[
    Gojo Domain Hemisphere - Roblox Luau Script
    
    Instructions:
    1. Place this LocalScript in StarterPlayer > StarterCharacterScripts
    2. Press E to activate the domain expansion
    3. The hemisphere will form around your character at ground level
    4. Can only use once every 10 seconds (cooldown)
--]]

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local character = script.Parent
local humanoidRootPart = character:WaitForChild("HumanoidRootPart")

local canActivate = true
local COOLDOWN = 10 -- seconds

-- Configuration
local SPHERE_RADIUS = 50
local TILE_SIZE = Vector3.new(10, 10, 0.1)
local SEGMENTS = 30 -- How many tiles around horizontally
local RINGS = 15 -- How many rings vertically (only upper half for hemisphere)

-- Colors for tiles
local TILE_COLORS = {
    Color3.fromRGB(74, 144, 226),   -- Blue
    Color3.fromRGB(80, 200, 120),   -- Green
    Color3.fromRGB(233, 75, 60),    -- Red
    Color3.fromRGB(243, 156, 18),   -- Orange
    Color3.fromRGB(155, 89, 182),   -- Purple
    Color3.fromRGB(26, 188, 156),   -- Teal
}

-- Create domain expansion
local function createDomainExpansion()
    if not canActivate then
        print("Domain expansion on cooldown!")
        return
    end
    
    canActivate = false
    
    -- Create main model to hold all tiles
    local domainModel = Instance.new("Model")
    domainModel.Name = "GojoDomain"
    domainModel.Parent = workspace
    
    -- Get player's ground position
    local centerPosition = Vector3.new(
        humanoidRootPart.Position.X,
        humanoidRootPart.Position.Y - 3, -- Slightly below player
        humanoidRootPart.Position.Z
    )
    
    print("Domain Expansion: Activating...")
    
    local tiles = generateHemisphere(centerPosition, domainModel)
    
    -- Animate all tiles
    for _, tileData in ipairs(tiles) do
        task.spawn(function()
            animateTile(
                tileData.tile,
                tileData.startPosition,
                tileData.targetPosition,
                tileData.targetCFrame,
                tileData.delay
            )
        end)
    end
    
    print("Domain Expansion: Complete! Total tiles:", #tiles)
    
    -- Start cooldown
    task.wait(COOLDOWN)
    canActivate = true
    print("Domain expansion ready!")
end

-- Function to create a single tile
local function createTile(targetPosition, targetCFrame, delay, centerPosition, domainModel)
    local tile = Instance.new("Part")
    tile.Size = TILE_SIZE
    tile.Material = Enum.Material.Neon
    tile.Color = TILE_COLORS[math.random(1, #TILE_COLORS)]
    tile.Anchored = true
    tile.CanCollide = false
    tile.CastShadow = false
    
    -- Start position (far left side, maintaining Y and Z)
    local startPosition = Vector3.new(centerPosition.X - 300, targetPosition.Y, targetPosition.Z)
    tile.Position = startPosition
    tile.Size = Vector3.new(0, 0, 0) -- Start with zero size
    
    tile.Parent = domainModel
    
    return tile, startPosition
end

-- Function to animate a tile
local function animateTile(tile, startPosition, targetPosition, targetCFrame, delay)
    task.wait(delay)
    
    -- Tween info for smooth animation
    local tweenInfo = TweenInfo.new(
        1.5, -- Duration
        Enum.EasingStyle.Cubic,
        Enum.EasingDirection.Out,
        0,
        false,
        0
    )
    
    -- Create tweens for position, size, and rotation
    local positionTween = TweenService:Create(tile, tweenInfo, {
        Position = targetPosition
    })
    
    local sizeTween = TweenService:Create(tile, tweenInfo, {
        Size = TILE_SIZE
    })
    
    local rotationTween = TweenService:Create(tile, tweenInfo, {
        CFrame = targetCFrame
    })
    
    -- Play all tweens simultaneously
    positionTween:Play()
    sizeTween:Play()
    rotationTween:Play()
    
    -- Wait for tweens to complete
    positionTween.Completed:Wait()
end

-- Generate hemisphere tiles
local function generateHemisphere(centerPosition, domainModel)
    local tiles = {}
    
    -- Create tiles only for upper hemisphere (phi from 0 to PI/2)
    for ring = 0, RINGS - 1 do
        local phi = (math.pi/2 * ring) / (RINGS - 1) -- 0 to PI/2 (upper hemisphere only)
        
        for segment = 0, SEGMENTS - 1 do
            local theta = (2 * math.pi * segment) / SEGMENTS -- 0 to 2PI (full circle)
            
            -- Calculate position on hemisphere using spherical coordinates
            local x = SPHERE_RADIUS * math.sin(phi) * math.cos(theta)
            local y = SPHERE_RADIUS * math.cos(phi) -- Height above ground
            local z = SPHERE_RADIUS * math.sin(phi) * math.sin(theta)
            
            local targetPosition = centerPosition + Vector3.new(x, y, z)
            
            -- Calculate CFrame to make tile face inward toward center
            local lookAtCenter = CFrame.lookAt(targetPosition, centerPosition)
            local targetCFrame = lookAtCenter
            
            -- Calculate delay based on angle from left (-PI/2) to right (PI/2)
            -- Normalize theta to go from -PI to PI, then map left side to start first
            local normalizedTheta = theta
            if normalizedTheta > math.pi then
                normalizedTheta = normalizedTheta - 2 * math.pi
            end
            
            -- Map from -PI to PI to 0 to 1 (left to right)
            local leftToRightProgress = (normalizedTheta + math.pi) / (2 * math.pi)
            local delay = leftToRightProgress * 3 -- Spread over 3 seconds
            
            -- Create tile
            local tile, startPos = createTile(targetPosition, targetCFrame, delay, centerPosition, domainModel)
            
            table.insert(tiles, {
                tile = tile,
                startPosition = startPos,
                targetPosition = targetPosition,
                targetCFrame = targetCFrame,
                delay = delay
            })
        end
    end
    
    return tiles
end

-- Listen for E key press
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end -- Ignore if typing in chat, etc.
    
    if input.KeyCode == Enum.KeyCode.E then
        createDomainExpansion()
    end
end)

print("Domain Expansion ready! Press E to activate.")