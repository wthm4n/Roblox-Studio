local RigBuilderConfig = {
    -- Humanoid Configuration
    Humanoid = {
        MaxHealth = 100,
        Health = 100,
        WalkSpeed = 16,
        JumpPower = 50,
        JumpHeight = 7.2,
        RequiredAccessory = false,
    },

    -- Character Scale
    Scale = {
        HeadScale = 1,
        TorsoScale = 1,
        ArmScale = 1,
        LegScale = 1,
    },

    -- Appearance Settings
    Appearance = {
        SkinColor = Color3.fromRGB(255, 204, 153),
        ShirtColor = Color3.fromRGB(255, 0, 0),
        PantsColor = Color3.fromRGB(0, 0, 255),
    },

    -- Body Parts Configuration
    BodyParts = {
        Head = { Size = Vector3.new(2, 1, 1), Color = Color3.fromRGB(255, 204, 153) },
        Torso = { Size = Vector3.new(2, 2, 1), Color = Color3.fromRGB(255, 0, 0) },
        LeftArm = { Size = Vector3.new(1, 2, 1), Color = Color3.fromRGB(255, 204, 153) },
        RightArm = { Size = Vector3.new(1, 2, 1), Color = Color3.fromRGB(255, 204, 153) },
        LeftLeg = { Size = Vector3.new(1, 2, 1), Color = Color3.fromRGB(0, 0, 255) },
        RightLeg = { Size = Vector3.new(1, 2, 1), Color = Color3.fromRGB(0, 0, 255) },
    },

    -- Animation Settings
    Animation = {
        WalkSpeed = 0.5,
        RunSpeed = 1,
        IdleSpeed = 0.5,
        Enabled = true,
    },

    -- Clothing & Accessories
    Accessories = {
        Hat = false,
        Shirt = false,
        Pants = false,
    },

    -- Collision Groups
    CollisionGroup = "NPC",
    CanCollide = true,

    -- AI Specific
    AI = {
        Enabled = true,
        Aggression = 0.5,
        DetectionRange = 50,
        Behavior = "Patrol", -- Patrol, Chase, Idle
    },
}

return RigBuilderConfig