-- --!strict
-- -- RigBuilder.lua (R6)
-- -- Builds a chibi "mini player" minion rig using Roblox's native avatar
-- -- assembly (Players:CreateHumanoidModelFromUserId). We never touch
-- -- accessory Handles, Meshes, Welds, or Attachments manually — Roblox's
-- -- own avatar pipeline guarantees those are correct. We only scale the
-- -- result and then prune/strip on top of an already-correct rig.

-- local Players = game:GetService("Players")

-- export type RigBuildOptions = {
-- 	UniformScale: number?, -- default 0.55: shrinks the whole rig
-- 	KeepFace: boolean?, -- default false: replace with the game's own mascot face
-- 	MascotFaceDecalId: string?, -- asset id (rbxassetid://...) for the branded face
-- 	KeepHair: boolean?, -- default false
-- 	MaxAccessories: number?, -- default 1: caps how many non-hair accessories survive
-- 	StripAnimateScript: boolean?, -- default false: keep the stock Animate script
-- }

-- local DEFAULTS: RigBuildOptions = {
-- 	UniformScale = 0.55,
-- 	KeepFace = false,
-- 	MascotFaceDecalId = nil,
-- 	KeepHair = false,
-- 	MaxAccessories = 1,
-- 	StripAnimateScript = false,
-- }

-- local RigBuilder = {}

-- --[[
-- 	Removes the face Decal, optionally replacing it with a mascot decal.
-- 	Only touches the Decal — never accessories, welds, or attachments.
-- ]]
-- local function stripFace(model: Model, options: RigBuildOptions)
-- 	if options.KeepFace then
-- 		return
-- 	end

-- 	local head = model:FindFirstChild("Head") :: BasePart?
-- 	if not head then
-- 		return
-- 	end

-- 	local existingFace = head:FindFirstChildOfClass("Decal")
-- 	if existingFace then
-- 		existingFace:Destroy()
-- 	end

-- 	if options.MascotFaceDecalId then
-- 		local face = Instance.new("Decal")
-- 		face.Name = "face"
-- 		face.Texture = options.MascotFaceDecalId :: string
-- 		face.Face = Enum.NormalId.Front
-- 		face.Parent = head
-- 	end
-- end

-- --[[
-- 	Removes whole Accessory instances (hair / hats / etc) by count and
-- 	category. We only ever Destroy the top-level Accessory — Roblox already
-- 	built its Handle, Mesh, Weld, and AccessoryWeld correctly, and scaling
-- 	already happened via Model:ScaleTo, so there is nothing left to fix up.
-- ]]
-- local function pruneAccessories(model: Model, options: RigBuildOptions)
-- 	local accessories = {}
-- 	for _, child in ipairs(model:GetChildren()) do
-- 		if child:IsA("Accessory") then
-- 			table.insert(accessories, child)
-- 		end
-- 	end

-- 	local kept = 0
-- 	for _, accessory in ipairs(accessories) do
-- 		local isHair = accessory.Name:lower():find("hair") ~= nil

-- 		if isHair and not options.KeepHair then
-- 			accessory:Destroy()
-- 			continue
-- 		end

-- 		if not isHair then
-- 			kept += 1
-- 			if kept > (options.MaxAccessories or 1) then
-- 				accessory:Destroy()
-- 			end
-- 		end
-- 	end
-- end

-- local function stripAnimateScript(model: Model, options: RigBuildOptions)
-- 	if not options.StripAnimateScript then
-- 		return
-- 	end
-- 	local animate = model:FindFirstChild("Animate")
-- 	if animate then
-- 		animate:Destroy()
-- 	end
-- end

-- local function addFutureProofAttachments(model: Model)
-- 	local head = model:FindFirstChild("Head") :: BasePart?
-- 	local torso = model:FindFirstChild("Torso") :: BasePart?

-- 	local function addAttachment(part: BasePart?, name: string, position: Vector3)
-- 		if not part then
-- 			return
-- 		end
-- 		if part:FindFirstChild(name) then
-- 			return
-- 		end
-- 		local attachment = Instance.new("Attachment")
-- 		attachment.Name = name
-- 		attachment.Position = position
-- 		attachment.Parent = part
-- 	end

-- 	addAttachment(head, "HatAttachment", Vector3.new(0, 0.6, 0))
-- 	addAttachment(head, "AuraAttachment", Vector3.new(0, 0.8, 0))
-- 	addAttachment(head, "FaceFrontAttachment", Vector3.new(0, 0, -0.5))

-- 	addAttachment(torso, "BackAttachment", Vector3.new(0, 0.3, 0.5))
-- 	addAttachment(torso, "WeaponAttachment", Vector3.new(0.6, 0, 0))
-- 	addAttachment(torso, "ChestAttachment", Vector3.new(0, 0.3, -0.5))
-- 	addAttachment(torso, "SaddleAttachment", Vector3.new(0, 0.6, 0.2))
-- 	addAttachment(torso, "TrailAttachment", Vector3.new(0, -0.8, 0.3))
-- 	addAttachment(torso, "GroundAttachment", Vector3.new(0, -1.2, 0))
-- 	addAttachment(torso, "OverheadAttachment", Vector3.new(0, 1.4, 0)) -- GUI anchor, see OverheadGuiComponent
-- end

-- local function setPhysicsFlags(model: Model)
-- 	for _, descendant in ipairs(model:GetDescendants()) do
-- 		if descendant:IsA("BasePart") then
-- 			descendant.CastShadow = false
-- 			if descendant.Name ~= "Torso" and descendant.Name ~= "HumanoidRootPart" then
-- 				descendant.CanCollide = false
-- 			end
-- 			descendant.CanQuery = descendant.Name == "Head" or descendant.Name == "HumanoidRootPart"
-- 		end
-- 	end

-- 	local humanoid = model:FindFirstChildOfClass("Humanoid")
-- 	if humanoid then
-- 		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
-- 		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
-- 		humanoid.RequiresNeck = false
-- 		humanoid.BreakJointsOnDeath = false
-- 	end
-- end

-- --[[
-- 	Runs every step that is safe to apply AFTER Roblox has already built a
-- 	correct, fully-welded avatar and we've scaled it. Order matters only in
-- 	that scaling must happen first (done by the caller) — everything below
-- 	is independent and never reaches into accessory internals.
-- ]]
-- local function applyCustomizations(model: Model, options: RigBuildOptions)
-- 	stripFace(model, options)
-- 	pruneAccessories(model, options)
-- 	stripAnimateScript(model, options)
-- 	addFutureProofAttachments(model)
-- 	setPhysicsFlags(model)
-- end

-- local function mergeOptions(options: RigBuildOptions?): RigBuildOptions
-- 	local merged: RigBuildOptions = table.clone(DEFAULTS)
-- 	if options then
-- 		for key, value in pairs(options) do
-- 			(merged :: any)[key] = value
-- 		end
-- 	end
-- 	return merged
-- end

-- --[[
-- 	Builds a chibi minion Model from `player`'s live avatar using Roblox's
-- 	native CreateHumanoidModelFromUserId — the same path Roblox itself uses
-- 	to assemble avatars, so accessories/welds/attachments are guaranteed
-- 	correct out of the box. We only scale and then customize on top.
-- ]]
-- function RigBuilder.BuildFromPlayer(player: Player, options: RigBuildOptions?): Model
-- 	local merged = mergeOptions(options)

-- 	local model = Players:CreateHumanoidModelFromUserId(player.UserId)
-- 	model.Name = player.Name .. "_Minion"

-- 	model:ScaleTo(merged.UniformScale or 0.55)
-- 	applyCustomizations(model, merged)

-- 	return model
-- end

-- return RigBuilder

--!strict
-- RigBuilder.lua (R6)
-- Builds a chibi "mini player" minion rig using Roblox's native avatar
-- assembly (Players:CreateHumanoidModelFromUserId). We never touch
-- accessory Handles, Meshes, Welds, or Attachments manually — Roblox's
-- own avatar pipeline guarantees those are correct. We only scale the
-- result and then prune/strip on top of an already-correct rig.

local Players = game:GetService("Players")

export type RigBuildOptions = {
	UniformScale: number?, -- default 0.55: shrinks the whole rig
	KeepFace: boolean?, -- default false: replace with the game's own mascot face
	MascotFaceDecalId: string?, -- asset id (rbxassetid://...) for the branded face
	KeepHair: boolean?, -- default false
	MaxAccessories: number?, -- default 1: caps how many non-hair accessories survive
	StripAnimateScript: boolean?, -- default false: keep the stock Animate script
}

local DEFAULTS: RigBuildOptions = {
	UniformScale = 0.55,
	KeepFace = false,
	MascotFaceDecalId = nil,
	KeepHair = false,
	MaxAccessories = 1,
	StripAnimateScript = false,
}

local RigBuilder = {}

--[[
	Removes the face Decal, optionally replacing it with a mascot decal.
	Only touches the Decal — never accessories, welds, or attachments.
]]
local function stripFace(model: Model, options: RigBuildOptions)
	if options.KeepFace then
		return
	end

	local head = model:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end

	local existingFace = head:FindFirstChildOfClass("Decal")
	if existingFace then
		existingFace:Destroy()
	end

	if options.MascotFaceDecalId then
		local face = Instance.new("Decal")
		face.Name = "face"
		face.Texture = options.MascotFaceDecalId :: string
		face.Face = Enum.NormalId.Front
		face.Parent = head
	end
end

--[[
	Removes whole Accessory instances (hair / hats / etc) by count and
	category. We only ever Destroy the top-level Accessory — Roblox already
	built its Handle, Mesh, Weld, and AccessoryWeld correctly, and scaling
	already happened via Model:ScaleTo, so there is nothing left to fix up.
]]
local function pruneAccessories(model: Model, options: RigBuildOptions)
	local accessories = {}
	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("Accessory") then
			table.insert(accessories, child)
		end
	end

	local kept = 0
	for _, accessory in ipairs(accessories) do
		local isHair = accessory.Name:lower():find("hair") ~= nil

		if isHair and not options.KeepHair then
			accessory:Destroy()
			continue
		end

		if not isHair then
			kept += 1
			if kept > (options.MaxAccessories or 1) then
				accessory:Destroy()
			end
		end
	end
end

local function stripAnimateScript(model: Model, options: RigBuildOptions)
	if not options.StripAnimateScript then
		return
	end
	local animate = model:FindFirstChild("Animate")
	if animate then
		animate:Destroy()
	end
end

local function addFutureProofAttachments(model: Model)
	local head = model:FindFirstChild("Head") :: BasePart?
	local torso = model:FindFirstChild("Torso") :: BasePart?

	local function addAttachment(part: BasePart?, name: string, position: Vector3)
		if not part then
			return
		end
		if part:FindFirstChild(name) then
			return
		end
		local attachment = Instance.new("Attachment")
		attachment.Name = name
		attachment.Position = position
		attachment.Parent = part
	end

	addAttachment(head, "HatAttachment", Vector3.new(0, 0.6, 0))
	addAttachment(head, "AuraAttachment", Vector3.new(0, 0.8, 0))
	addAttachment(head, "FaceFrontAttachment", Vector3.new(0, 0, -0.5))

	addAttachment(torso, "BackAttachment", Vector3.new(0, 0.3, 0.5))
	addAttachment(torso, "WeaponAttachment", Vector3.new(0.6, 0, 0))
	addAttachment(torso, "ChestAttachment", Vector3.new(0, 0.3, -0.5))
	addAttachment(torso, "SaddleAttachment", Vector3.new(0, 0.6, 0.2))
	addAttachment(torso, "TrailAttachment", Vector3.new(0, -0.8, 0.3))
	addAttachment(torso, "GroundAttachment", Vector3.new(0, -1.2, 0))
	addAttachment(torso, "OverheadAttachment", Vector3.new(0, 1.4, 0)) -- GUI anchor, see OverheadGuiComponent
end

local function setPhysicsFlags(model: Model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CastShadow = false
			if descendant.Name ~= "Torso" and descendant.Name ~= "HumanoidRootPart" then
				descendant.CanCollide = false
			end
			descendant.CanQuery = descendant.Name == "Head" or descendant.Name == "HumanoidRootPart"
		end
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.RequiresNeck = false
		humanoid.BreakJointsOnDeath = false
	end
end

--[[
	Runs every step that is safe to apply AFTER Roblox has already built a
	correct, fully-welded avatar and we've scaled it. Order matters only in
	that scaling must happen first (done by the caller) — everything below
	is independent and never reaches into accessory internals.
]]
local function applyCustomizations(model: Model, options: RigBuildOptions)
	stripFace(model, options)
	pruneAccessories(model, options)
	stripAnimateScript(model, options)
	addFutureProofAttachments(model)
	setPhysicsFlags(model)
end

local function mergeOptions(options: RigBuildOptions?): RigBuildOptions
	local merged: RigBuildOptions = table.clone(DEFAULTS)
	if options then
		for key, value in pairs(options) do
			(merged :: any)[key] = value
		end
	end
	return merged
end

--[[
	Roblox has no rig-type parameter on CreateHumanoidModelFromUserId — it
	always returns whatever rig the account is natively set to (commonly
	R15 nowadays), and there is no native "convert this live model to R6"
	API. The only reliable way to get an R6 skeleton is still through
	CreateHumanoidModelFromDescription(desc, R6).

	The bug in the old pipeline was never "using a HumanoidDescription" —
	it was fetching one over the network via GetHumanoidDescriptionFromUserId,
	an async call with no error handling that could return partial/stale
	data with missing accessories.

	This avoids that entirely: we first build the avatar the reliable way
	(CreateHumanoidModelFromUserId — correct accessories/welds/appearance,
	whatever rig type that yields), then read the description straight back
	off that live, already-correct model via Humanoid:GetAppliedDescription().
	That's a synchronous local read of data that's already proven correct,
	not a fetch — so there's no race condition and no partial-data risk.
	Only then do we feed it into CreateHumanoidModelFromDescription purely
	as a same-process rig-format conversion, never as the primary source.

	Caveat: R6 and R15 use different skeletons and accessory attachment
	points, so even a perfect description can yield slightly different
	accessory seating between rig types — that's an engine-level limitation
	of cross-rig conversion, not something fixable from script without
	manually rewriting welds (which we're explicitly avoiding).
]]
local function buildR6FromPlayer(player: Player): Model
	local sourceModel = Players:CreateHumanoidModelFromUserId(player.UserId)

	local sourceHumanoid = sourceModel:FindFirstChildOfClass("Humanoid")
	if not sourceHumanoid then
		sourceModel:Destroy()
		error("RigBuilder: CreateHumanoidModelFromUserId returned a model with no Humanoid", 3)
	end

	if sourceHumanoid.RigType == Enum.HumanoidRigType.R6 then
		-- Already R6 (player's account/avatar settings are R6) — no
		-- conversion needed, use it directly.
		return sourceModel
	end

	local description = sourceHumanoid:GetAppliedDescription()
	sourceModel:Destroy()

	return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R6)
end

--[[
	Builds a chibi minion Model from `player`'s live avatar. Avatar assembly
	always goes through Roblox's native CreateHumanoidModelFromUserId first
	so accessories/welds/attachments are guaranteed correct; R6 conversion
	(when needed) happens via a local description snapshot, never a
	network fetch. We only scale and then customize on top.
]]
-- RigBuilder.lua

-- Simply build the rig. Do not destroy the 'Animate' script.
-- Let the minion model be a perfect, functional replica of the player.
function RigBuilder.BuildFromPlayer(player: Player, options: RigBuildOptions?): Model
	local merged = mergeOptions(options)

	-- 1. Get a reliable R6 model
	local model = buildR6FromPlayer(player) 
	model.Name = player.Name .. "_Minion"

	-- 2. Ensure native Animation infrastructure is present
	-- If it doesn't exist, we add a generic one so components have something to hook into
	if not model:FindFirstChild("Animate") and player.Character then
		local animate = player.Character:FindFirstChild("Animate")
		if animate then animate:Clone().Parent = model end
	end

	-- 3. Finalize
	model:ScaleTo(merged.UniformScale or 0.55)
	applyCustomizations(model, merged)

	return model
end

return RigBuilder