local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

local env = (getgenv and getgenv()) or _G
if not env.TerraformWhitelist and env.TerraformHelper and env.TerraformHelper.ConfigSnapshot then
    local ok, previous = pcall(env.TerraformHelper.ConfigSnapshot)
    if ok and type(previous) == "table" and type(previous.whitelist) == "table" then
        env.TerraformWhitelist = {}
        for _, name in ipairs(previous.whitelist) do
            if type(name) == "string" then env.TerraformWhitelist[string.lower(name)] = true end
        end
    end
end
if env.TerraformHelper and env.TerraformHelper.Stop then
    env.TerraformHelper.Stop()
end

local alive = true
local connections = {}
local visuals = {}
local ores = {}
local animals = {}
local oreLocations = {}
local oreMarkers = {}
local originalCollisions = {}
local currentHumanoid = nil
local normalWalkSpeed = nil
local normalJumpPower = nil
local normalJumpHeight = nil
local normalUseJumpPower = nil
local window = nil

local settings = {
    playerEsp = false,
    animalEsp = false,
    diamondXray = false,
    ironXray = false,
    coalXray = false,
    goldXray = false,
    oreDistance = 250,
    killAura = false,
    auraRange = 12,
    faceTarget = true,
    animalAura = false,
    animalAuraRange = 12,
    friendProtection = true,
    noFall = false,
    noDrown = false,
    fastBreak = false,
    playerNames = false,
    animalNames = false,
    playerNameDistance = 150,
    animalNameDistance = 150,
    playerNameSize = 14,
    animalNameSize = 14,
    playerNameTransparency = 0,
    animalNameTransparency = 0,
    playerNameColor = Color3.fromRGB(255, 100, 100),
    animalNameColor = Color3.fromRGB(110, 255, 140),
    displayNames = false,
    hideLocalName = true,
    showDistance = true,
    theme = "Dark",
    speed = false,
    walkSpeed = 32,
    jump = false,
    jumpPower = 85,
    infiniteJump = false,
    noclip = false,
}
local defaultSettings = table.clone(settings)
local hasSavedWhitelist = type(env.TerraformWhitelist) == "table"
local whitelist = hasSavedWhitelist and env.TerraformWhitelist or {}
env.TerraformWhitelist = whitelist
local automaticFriends = {}

local function isFriend(player)
    local name = string.lower(player.Name)
    return whitelist[name] or automaticFriends[name] or false
end

local indicatorFeatures = {
    {"killAura", "Player aura"},
    {"animalAura", "Animal aura"},
    {"playerEsp", "Player ESP"},
    {"animalEsp", "Animal ESP"},
    {"playerNames", "Player names"},
    {"animalNames", "Animal names"},
    {"diamondXray", "Diamond X-ray"},
    {"ironXray", "Iron X-ray"},
    {"coalXray", "Coal X-ray"},
    {"goldXray", "Gold X-ray"},
    {"noFall", "No fall damage"},
    {"noDrown", "No drowning"},
    {"fastBreak", "Insta Break"},
    {"speed", "Speed"},
    {"jump", "Jump boost"},
    {"infiniteJump", "Infinite jump"},
    {"noclip", "Phase"},
}
local indicatorKeys = {}
for _, feature in ipairs(indicatorFeatures) do indicatorKeys[feature[1]] = true end

local activeList

local function updateActiveList()
    if not activeList then return end
    local active = {}
    for _, feature in ipairs(indicatorFeatures) do
        if settings[feature[1]] then table.insert(active, feature[2]) end
    end
    local text = #active > 0 and (#active .. " enabled\n\n" .. table.concat(active, "\n")) or "Nothing active"
    activeList:Set(text)
end

local animalWords = {
    "animal", "cow", "pig", "sheep", "chicken", "wolf", "bear", "deer",
    "rabbit", "horse", "goat", "fox", "duck", "boar", "fish", "zombie", "turkey",
}

local oreColors = {
    diamond = Color3.fromRGB(45, 240, 255),
    iron = Color3.fromRGB(255, 169, 93),
    coal = Color3.fromRGB(234, 234, 234),
    gold = Color3.fromRGB(255, 218, 68),
}
local friendHighlightColor = Color3.fromRGB(80, 245, 125)
local playerHighlightColor = Color3.fromRGB(255, 90, 90)

local function anyOreXray()
    return settings.diamondXray or settings.ironXray or settings.coalXray or settings.goldXray
end

-- Terraform identifies voxels by numeric block IDs, including underground
-- blocks that have no Workspace part yet. Read the game's own registry.
local oreIds = {}
local ChunksSystem, Coordinates, BlockState, BlocksSystem
local ActionsSystem, HotbarState, InventoryState, ItemsData
pcall(function()
    local data = require(ReplicatedStorage.Systems.BlocksSystem.Configuration.BlocksData)
    for id, block in pairs(data) do
        if type(block) == "table" then
            if block.name == "diamond_ore" then oreIds[id] = "diamond" end
            if block.name == "iron_ore" then oreIds[id] = "iron" end
            if block.name == "coal_ore" then oreIds[id] = "coal" end
            local blockName = string.lower(tostring(block.name or ""))
            if string.find(blockName, "gold", 1, true) and string.find(blockName, "ore", 1, true) then oreIds[id] = "gold" end
        end
    end
    ChunksSystem = require(ReplicatedStorage.Systems.ChunksSystem)
    Coordinates = require(ReplicatedStorage.Libs.Coordinates)
    BlockState = require(ReplicatedStorage.Libs.BlockState)
    BlocksSystem = require(ReplicatedStorage.Systems.BlocksSystem)
end)
pcall(function()
    ActionsSystem = require(ReplicatedStorage.Systems.ActionsSystem)
    HotbarState = require(ReplicatedStorage.Client.States.HotbarState)
    InventoryState = require(ReplicatedStorage.Client.States.InventoryState)
    ItemsData = require(ReplicatedStorage.Systems.ItemsSystem.Configuration.ItemsData)
end)

local function track(connection)
    table.insert(connections, connection)
    return connection
end

local function getRoot()
    local character = LocalPlayer.Character
    return character and character:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid()
    local character = LocalPlayer.Character
    return character and character:FindFirstChildOfClass("Humanoid")
end

local function isLiving(model)
    local humanoid = model and model:FindFirstChildOfClass("Humanoid")
    return humanoid and humanoid.Health > 0
end

local function oreKind(part)
    if not part:IsA("BasePart") then return nil end
    local encoded = part:GetAttribute("b")
    if not encoded and part.Parent then encoded = part.Parent:GetAttribute("b") end
    if encoded then
        local id = tonumber(string.match(tostring(encoded), "^(%d+)") or "")
        if id then return oreIds[id] end
    end
    local name = string.lower(part.Name)
    local parent = part.Parent
    if parent and parent:IsA("Model") then
        name = name .. " " .. string.lower(parent.Name)
    end
    if string.find(name, "diamond", 1, true) then return "diamond" end
    if string.find(name, "iron", 1, true) then return "iron" end
    if string.find(name, "coal", 1, true) then return "coal" end
    if string.find(name, "gold", 1, true) then return "gold" end
    return nil
end

local function liveOreKind(position)
    if not (BlocksSystem and BlockState) then return nil, false end
    local ok, state = pcall(BlocksSystem.getBlockState, position / 4)
    if not ok then return nil, false end
    if state == nil then return nil, true end
    local decoded, id = pcall(BlockState.getBlockId, state)
    if not decoded then return nil, false end
    return oreIds[id], true
end

local function refreshOreLocations()
    if not ChunksSystem or not Coordinates or not BlockState then return end
    local map = Workspace:FindFirstChild("Map")
    if not map then return end
    local found = {}
    for _, folder in ipairs(map:GetChildren()) do
        if not alive then return end
        local region, chunk = ChunksSystem.getNamesFromFolder(folder)
        if region then
            local data = ChunksSystem.readChunkData(region, chunk)
            local states = data.blockStates or {}
            local seen = {}
            local function addBlock(key, id)
                local kind = oreIds[id]
                if not kind then return end
                local ok, position = pcall(Coordinates.coordinatesFromNames, region, chunk, tostring(key))
                if ok and typeof(position) == "Vector3" then
                    -- Coordinates are block-grid units; each voxel is 4 studs.
                    table.insert(found, {position = position * 4, kind = kind})
                end
            end
            for key, id in pairs(data.blocks or {}) do
                seen[key] = true
                local state = states[key]
                if state then id = BlockState.getBlockId(state) end
                addBlock(key, id)
            end
            for key, state in pairs(states) do
                if not seen[key] then addBlock(key, BlockState.getBlockId(state)) end
            end
        end
        task.wait()
    end
    if alive then oreLocations = found end
end

local function ensureOreMarker(index)
    local marker = oreMarkers[index]
    if marker then return marker end
    local part = Instance.new("Part")
    part.Name = "TerraformOreMarker"
    part.Size = Vector3.new(4, 4, 4)
    part.Anchored = true
    part.CanCollide = false
    part.CanTouch = false
    part.CanQuery = false
    part.Transparency = 1
    part.Parent = Workspace

    local outline = Instance.new("BoxHandleAdornment")
    outline.Name = "OreOutline"
    outline.Adornee = part
    outline.AlwaysOnTop = true
    outline.Size = Vector3.new(4, 4, 4)
    outline.Transparency = 0.25
    outline.ZIndex = 10
    outline.Parent = part

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "OreLabel"
    billboard.Adornee = part
    billboard.AlwaysOnTop = true
    billboard.Size = UDim2.fromOffset(110, 24)
    billboard.StudsOffset = Vector3.new(0, 3, 0)
    billboard.Parent = part

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.fromScale(1, 1)
    label.Font = Enum.Font.GothamBold
    label.TextSize = 13
    label.TextStrokeTransparency = 0.2
    label.Parent = billboard

    marker = {part = part, outline = outline, label = label}
    oreMarkers[index] = marker
    return marker
end

local function updateOreMarkers()
    if not anyOreXray() then
        for index, marker in pairs(oreMarkers) do marker.part:Destroy(); oreMarkers[index] = nil end
        return
    end
    local root = getRoot()
    local nearby = {}
    if root then
        local maxDistanceSquared = settings.oreDistance * settings.oreDistance
        for _, ore in ipairs(oreLocations) do
            if settings[ore.kind .. "Xray"] then
                local delta = ore.position - root.Position
                local distanceSquared = delta:Dot(delta)
                if distanceSquared <= maxDistanceSquared then
                    table.insert(nearby, {ore = ore, distanceSquared = distanceSquared})
                end
            end
        end
    end
    table.sort(nearby, function(a, b) return a.distanceSquared < b.distanceSquared end)
    local count = 0
    local stale = {}
    for _, entry in ipairs(nearby) do
        local kind, checked = liveOreKind(entry.ore.position)
        local present = not checked or kind == entry.ore.kind
        if present then
            count += 1
            local marker = ensureOreMarker(count)
            local color = oreColors[entry.ore.kind]
            marker.part.Position = entry.ore.position
            marker.outline.Color3 = color
            marker.label.TextColor3 = color
            marker.label.Text = string.upper(entry.ore.kind) .. " " .. math.floor(math.sqrt(entry.distanceSquared))
            if count == 20 then break end
        else
            stale[entry.ore] = true
        end
    end
    if next(stale) then
        for index = #oreLocations, 1, -1 do
            if stale[oreLocations[index]] then table.remove(oreLocations, index) end
        end
    end
    for index = count + 1, #oreMarkers do
        oreMarkers[index].part:Destroy()
        oreMarkers[index] = nil
    end
end

local function isAnimal(model)
    if not model:IsA("Model") or model == LocalPlayer.Character then return false end
    if Players:GetPlayerFromCharacter(model) then return false end
    for _, player in ipairs(Players:GetPlayers()) do
        if model.Name == player.Name then return false end
        if player.Character and model:IsDescendantOf(player.Character) then return false end
    end
    local entities = Workspace:FindFirstChild("Entities")
    if not entities or not model:IsDescendantOf(entities) then return false end
    local name = string.lower(model.Name)
    for _, word in ipairs(animalWords) do
        if name == word or string.find(name, "^" .. word .. "[%s_%-%d]") then return true end
    end
    return false
end

local function getModelPosition(model)
    local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
    return part and part.Position
end

local function removeVisual(key)
    local highlight = visuals[key]
    if highlight then
        visuals[key] = nil
        highlight:Destroy()
    end
end

local function showVisual(key, target, color)
    local highlight = visuals[key]
    if highlight and highlight.Parent and highlight.Adornee == target then
        highlight.FillColor = color
        highlight.OutlineColor = color
        return
    end
    removeVisual(key)
    highlight = Instance.new("Highlight")
    highlight.Name = "TerraformHelperESP"
    highlight.Adornee = target
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillColor = color
    highlight.OutlineColor = color
    highlight.FillTransparency = 0.72
    highlight.OutlineTransparency = 0
    highlight.Parent = target
    visuals[key] = highlight
end

local function updateEsp()
    local wanted = {}
    if settings.playerEsp then
        for _, player in ipairs(Players:GetPlayers()) do
            local character = player.Character
            if player ~= LocalPlayer and character and isLiving(character) then
                wanted[character] = isFriend(player) and friendHighlightColor or playerHighlightColor
            end
        end
    end
    if settings.animalEsp then
        for model in pairs(animals) do
            local humanoid = model:FindFirstChildOfClass("Humanoid")
            if model.Parent and not Players:GetPlayerFromCharacter(model)
                and (not humanoid or humanoid.Health > 0) and getModelPosition(model) then
                wanted[model] = Color3.fromRGB(104, 255, 135)
            end
        end
    end

    local root = getRoot()
    if root and anyOreXray() then
        local nearby = {}
        for part, kind in pairs(ores) do
            if part.Parent and settings[kind .. "Xray"] and oreKind(part) == kind then
                local distance = (part.Position - root.Position).Magnitude
                if distance <= settings.oreDistance then
                    local liveKind, checked = liveOreKind(part.Position)
                    if not checked or liveKind == kind then
                        table.insert(nearby, {part = part, kind = kind, distance = distance})
                    end
                end
            end
        end
        table.sort(nearby, function(a, b) return a.distance < b.distance end)
        local entityCount = 0
        for _ in pairs(wanted) do entityCount += 1 end
        local oreLimit = math.max(0, 31 - entityCount)
        for i = 1, math.min(20, oreLimit, #nearby) do
            local ore = nearby[i]
            wanted[ore.part] = oreColors[ore.kind]
        end
    end

    for key in pairs(visuals) do
        if not wanted[key] then removeVisual(key) end
    end
    for key, color in pairs(wanted) do
        showVisual(key, key, color)
    end
    updateOreMarkers()
end

local function indexObject(object)
    if object:IsA("BasePart") then
        local kind = oreKind(object)
        if kind then ores[object] = kind end
    elseif object:IsA("Model") and isAnimal(object) then
        animals[object] = true
    end
end

track(Workspace.DescendantAdded:Connect(function(object)
    if alive then indexObject(object) end
end))
track(Workspace.DescendantRemoving:Connect(function(object)
    ores[object] = nil
    animals[object] = nil
    removeVisual(object)
end))

task.spawn(function()
    local descendants = Workspace:GetDescendants()
    for index, object in ipairs(descendants) do
        if not alive then return end
        indexObject(object)
        if index % 500 == 0 then task.wait() end
    end
end)

task.spawn(function()
    while alive do
        if anyOreXray() then refreshOreLocations() end
        task.wait(8)
    end
end)

local function applyMovement()
    local humanoid = getHumanoid()
    if not humanoid then return end
    if humanoid ~= currentHumanoid then
        currentHumanoid = humanoid
        normalWalkSpeed = humanoid.WalkSpeed
        normalJumpPower = humanoid.JumpPower
        normalJumpHeight = humanoid.JumpHeight
        normalUseJumpPower = humanoid.UseJumpPower
    end
    if settings.speed then
        humanoid.WalkSpeed = settings.walkSpeed
    end
    if settings.jump then
        humanoid.UseJumpPower = true
        humanoid.JumpPower = settings.jumpPower
    end
end

local function restoreMovement()
    if currentHumanoid and currentHumanoid.Parent then
        if normalWalkSpeed then currentHumanoid.WalkSpeed = normalWalkSpeed end
        if normalJumpPower then currentHumanoid.JumpPower = normalJumpPower end
        if normalJumpHeight then currentHumanoid.JumpHeight = normalJumpHeight end
        if normalUseJumpPower ~= nil then currentHumanoid.UseJumpPower = normalUseJumpPower end
    end
end

local function restoreCollision()
    for part, original in pairs(originalCollisions) do
        if part.Parent then part.CanCollide = original end
        originalCollisions[part] = nil
    end
end

track(RunService.Stepped:Connect(function()
    if not alive or not settings.noclip then return end
    local character = LocalPlayer.Character
    if not character then return end
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") then
            if originalCollisions[part] == nil then
                originalCollisions[part] = part.CanCollide
            end
            part.CanCollide = false
        end
    end
end))

track(UserInputService.JumpRequest:Connect(function()
    if settings.infiniteJump then
        local humanoid = getHumanoid()
        if humanoid then humanoid:ChangeState(Enum.HumanoidStateType.Jumping) end
    end
end))

local function selectWeapon()
    if ActionsSystem and HotbarState and InventoryState and ItemsData then
        local heldId = HotbarState.getCurrentlyHeldItemId()
        local heldData = heldId and ItemsData[heldId]
        local heldName = heldData and string.lower(tostring(heldData.name or "")) or ""
        if string.find(heldName, "sword", 1, true) then return nil end
        local state = InventoryState.getState()
        local slots = state and state.predictedInventories and state.predictedInventories.Player
        if slots then
            local bestSlot, bestRank = nil, -1
            for slot = 1, 9 do
                local itemId = slots[tostring(slot)]
                if type(itemId) == "table" then itemId = itemId.id end
                local item = itemId and ItemsData[itemId]
                local name = item and string.lower(tostring(item.name or "")) or ""
                if string.find(name, "sword", 1, true) then
                    local rank = 1
                    if string.find(name, "diamond", 1, true) then rank = 4 end
                    if string.find(name, "mythril", 1, true) then rank = 5 end
                    if string.find(name, "netherite", 1, true) then rank = 6 end
                    if rank > bestRank then bestSlot, bestRank = slot, rank end
                end
            end
            if bestSlot then HotbarState.setCurrentHotbarSlot(bestSlot) end
        end
        return nil
    end
    local character = LocalPlayer.Character
    local humanoid = getHumanoid()
    if not character or not humanoid then return nil end
    local equipped = character:FindFirstChildOfClass("Tool")
    if equipped then return equipped end
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    if not backpack then return nil end
    for _, tool in ipairs(backpack:GetChildren()) do
        if tool:IsA("Tool") then
            local name = string.lower(tool.Name)
            if string.find(name, "sword", 1, true)
                or string.find(name, "blade", 1, true)
                or string.find(name, "axe", 1, true) then
                humanoid:EquipTool(tool)
                return tool
            end
        end
    end
    return nil
end

local nameLabels = {}
local controls = {}
local bindings = {
    {id = "toggleUi", label = "Open menu", group = "Menu", default = "RightControl"},
    {id = "playerAura", label = "Player aura", group = "Combat", flag = "killAura"},
    {id = "animalAura", label = "Animal aura", group = "Combat", flag = "animalAura"},
    {id = "playerNames", label = "Player names", group = "ESP", flag = "playerNames"},
    {id = "animalNames", label = "Animal names", group = "ESP", flag = "animalNames"},
    {id = "diamondXray", label = "Diamond X-ray", group = "Ores", flag = "diamondXray"},
    {id = "ironXray", label = "Iron X-ray", group = "Ores", flag = "ironXray"},
    {id = "coalXray", label = "Coal X-ray", group = "Ores", flag = "coalXray"},
    {id = "goldXray", label = "Gold X-ray", group = "Ores", flag = "goldXray"},
    {id = "noFall", label = "No fall damage", group = "Movement", flag = "noFall"},
    {id = "noDrown", label = "No drowning", group = "Movement", flag = "noDrown"},
    {id = "fastBreak", label = "Insta Break", group = "Movement", flag = "fastBreak"},
    {id = "speed", label = "Speed", group = "Movement", flag = "speed"},
    {id = "jump", label = "Jump boost", group = "Movement", flag = "jump"},
    {id = "infiniteJump", label = "Infinite jump", group = "Movement", flag = "infiniteJump"},
    {id = "phase", label = "Phase", group = "Movement", flag = "noclip"},
}
local keybinds = {}
local bindingById = {}
for _, binding in ipairs(bindings) do
    keybinds[binding.id] = binding.default or "None"
    bindingById[binding.id] = binding
end
local defaultKeybinds = table.clone(keybinds)
local refreshKeybindInfo
local activeConfig = nil
local autoloadConfig = nil
local configInput, configSearch, whitelistInput, whitelistSearch = "", "", "", ""
local newConfigName, importJson = "", ""
local pendingDelete = nil
local configFolder = "TerraformHelper/configs"
local metaFile = "TerraformHelper/meta.json"
local canPersist = type(readfile) == "function" and type(writefile) == "function" and type(listfiles) == "function" and type(makefolder) == "function"

local function notify(message, title)
    if window then window:Notify({title = title or "Strata", content = message, duration = 4}) end
end

local function updateFriend(player)
    if player == LocalPlayer then return end
    task.spawn(function()
        for attempt = 1, 3 do
            if not alive or player.Parent ~= Players then return end
            local ok, friend = pcall(function() return LocalPlayer:IsFriendsWith(player.UserId) end)
            if not alive or player.Parent ~= Players then return end
            if ok then
                automaticFriends[string.lower(player.Name)] = friend == true
                return
            end
            if attempt < 3 then task.wait(1) end
        end
    end)
end
for _, player in ipairs(Players:GetPlayers()) do updateFriend(player) end
track(Players.PlayerAdded:Connect(updateFriend))
track(Players.PlayerRemoving:Connect(function(player)
    automaticFriends[string.lower(player.Name)] = nil
    if player.Character and nameLabels[player.Character] then nameLabels[player.Character]:Destroy(); nameLabels[player.Character] = nil end
end))

local function protected(player)
    if not settings.friendProtection then return false end
    local name = string.lower(player.Name)
    return whitelist[name] or automaticFriends[name] or false
end

local function removeName(model)
    if nameLabels[model] then nameLabels[model]:Destroy(); nameLabels[model] = nil end
end

local function updateNames()
    local root = getRoot()
    local wanted = {}
    if root then
        if settings.playerNames then
            for _, player in ipairs(Players:GetPlayers()) do
                if (player ~= LocalPlayer or not settings.hideLocalName) and player.Character and isLiving(player.Character) then
                    wanted[player.Character] = {
                        kind = "player",
                        name = settings.displayNames and player.DisplayName or player.Name,
                        friend = isFriend(player),
                    }
                end
            end
        end
        if settings.animalNames then
            for model in pairs(animals) do
                if model.Parent and isLiving(model) and not Players:GetPlayerFromCharacter(model) then
                    wanted[model] = {kind = "animal", name = model.Name}
                end
            end
        end
    end
    for model in pairs(nameLabels) do if not wanted[model] then removeName(model) end end
    for model, info in pairs(wanted) do
        local part = model:FindFirstChild("Head") or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
        local distance = part and (part.Position - root.Position).Magnitude or math.huge
        local prefix = info.kind == "player" and "playerName" or "animalName"
        if not part or distance > settings[prefix .. "Distance"] then
            removeName(model)
        else
            local gui = nameLabels[model]
            if not gui or gui.Adornee ~= part then
                removeName(model)
                gui = Instance.new("BillboardGui")
                gui.Name = "TerraformNameESP"
                gui.Adornee = part
                gui.Size = UDim2.fromOffset(180, 32)
                gui.StudsOffset = Vector3.new(0, 2.7, 0)
                gui.ResetOnSpawn = false
                local label = Instance.new("TextLabel")
                label.Name = "Name"
                label.Size = UDim2.fromScale(1, 1)
                label.BackgroundTransparency = 1
                label.Font = Enum.Font.GothamBold
                label.TextStrokeTransparency = 0.25
                label.Parent = gui
                gui.Parent = part
                nameLabels[model] = gui
            end
            gui.AlwaysOnTop = true
            local label = gui:FindFirstChild("Name")
            label.Text = info.name .. (settings.showDistance and string.format(" [%dm]", math.floor(distance / 4 + 0.5)) or "")
            label.TextSize = settings[prefix .. "Size"]
            label.TextColor3 = info.friend and friendHighlightColor or settings[prefix .. "Color"]
            label.TextTransparency = settings[prefix .. "Transparency"]
        end
    end
end

local playerCharacterConnections = {}

local function refreshCharacterEsp(player, character)
    task.spawn(function()
        local humanoid = character:WaitForChild("Humanoid", 10)
        if not humanoid then return end
        for _ = 1, 20 do
            if not alive or player.Parent ~= Players or player.Character ~= character then return end
            if character.Parent and humanoid.Health > 0 then
                updateEsp()
                if settings.playerNames then updateNames() end
                return
            end
            task.wait(0.1)
        end
    end)
end

local function watchPlayerCharacter(player)
    if player == LocalPlayer or playerCharacterConnections[player] then return end
    playerCharacterConnections[player] = {
        player.CharacterAdded:Connect(function(character)
            refreshCharacterEsp(player, character)
        end),
        player.CharacterRemoving:Connect(function(character)
            removeVisual(character)
            removeName(character)
            animals[character] = nil
        end),
    }
    if player.Character then refreshCharacterEsp(player, player.Character) end
end

track(Players.PlayerAdded:Connect(watchPlayerCharacter))
track(Players.PlayerRemoving:Connect(function(player)
    local playerConnections = playerCharacterConnections[player]
    if playerConnections then
        for _, connection in ipairs(playerConnections) do connection:Disconnect() end
        playerCharacterConnections[player] = nil
    end
    if player.Character then
        removeVisual(player.Character)
        removeName(player.Character)
        animals[player.Character] = nil
    end
end))
for _, player in ipairs(Players:GetPlayers()) do watchPlayerCharacter(player) end

local damageHook = env.TerraformDamageHook
local asClosure = type(newcclosure) == "function" and newcclosure or function(callback) return callback end
if not damageHook and type(hookmetamethod) == "function" and type(getnamecallmethod) == "function" then
    local state = {noFall = false, noDrown = false}
    local fallRemote = ReplicatedStorage.Systems.CombatSystem.Network.FallDamage
    local drownRemote = ReplicatedStorage.Systems.CombatSystem.Network.DrownDamage
    local original
    original = hookmetamethod(game, "__namecall", asClosure(function(self, ...)
        if getnamecallmethod() == "FireServer" and ((self == fallRemote and state.noFall) or (self == drownRemote and state.noDrown)) then return nil end
        return original(self, ...)
    end))
    damageHook = state
    env.TerraformDamageHook = state
end

local breakHook = env.TerraformBreakHook
if not breakHook and type(hookfunction) == "function" then
    local ok, originalFunction = pcall(require, ReplicatedStorage.Systems.ItemsSystem.Libs.GetBreakingTime)
    if ok and type(originalFunction) == "function" then
        local state = {enabled = false, value = 0}
        local original
        original = hookfunction(originalFunction, asClosure(function(...)
            local duration, harvest = original(...)
            if state.enabled and type(duration) == "number" and duration < math.huge then
                return 0, harvest
            end
            return duration, harvest
        end))
        breakHook = state
        env.TerraformBreakHook = state
    end
end

local function syncHooks()
    if damageHook then damageHook.noFall = settings.noFall; damageHook.noDrown = settings.noDrown end
    if breakHook then
        breakHook.value = 0 -- Older loaded hooks still read this value.
        breakHook.enabled = settings.fastBreak
    end
end

local whitelistFile = "TerraformHelper/whitelist.json"

local function saveWhitelist()
    env.TerraformWhitelist = whitelist
    if not canPersist then return false end
    local names = {}
    for name in pairs(whitelist) do table.insert(names, name) end
    table.sort(names)
    pcall(makefolder, "TerraformHelper")
    local ok = pcall(writefile, whitelistFile, HttpService:JSONEncode(names))
    if ok then hasSavedWhitelist = true end
    return ok
end

local function setWhitelisted(name, enabled)
    local username = string.lower(string.match(tostring(name or ""), "^%s*(.-)%s*$") or "")
    if username == "" then return false end
    whitelist[username] = enabled and true or nil
    if not saveWhitelist() then
        notify("Whitelist kept for reloads in this session; saving to disk failed.", "Whitelist")
    end
    return true
end

local function configPath(name)
    return configFolder .. "/" .. name .. ".json"
end
local function validName(value): string?
    local name = string.match(tostring(value or ""), "^%s*(.-)%s*$") or ""
    if name == "" or #name > 40 or string.find(name, "[^%w _%-]") then return nil end
    return name
end
local function listConfigs()
    if not canPersist then return {} end
    local ok, files = pcall(listfiles, configFolder)
    if not ok then return {} end
    local names = {}
    for _, path in ipairs(files) do
        local name = string.match(path, "([^/\\]+)%.json$")
        if name then table.insert(names, name) end
    end
    table.sort(names)
    return names
end
local function snapshot()
    local data = {version = 2, settings = {}, whitelist = {}, keybinds = table.clone(keybinds)}
    for key, value in pairs(settings) do
        if typeof(value) == "Color3" then data.settings[key] = {math.floor(value.R * 255 + 0.5), math.floor(value.G * 255 + 0.5), math.floor(value.B * 255 + 0.5)}
        else data.settings[key] = value end
    end
    for name in pairs(whitelist) do table.insert(data.whitelist, name) end
    table.sort(data.whitelist)
    return data
end
local function writeMeta()
    if not canPersist then return end
    pcall(writefile, metaFile, HttpService:JSONEncode({autoload = autoloadConfig}))
end
if canPersist then
    pcall(makefolder, "TerraformHelper")
    pcall(makefolder, configFolder)
    local whitelistOk, whitelistRaw = pcall(readfile, whitelistFile)
    if whitelistOk then
        local decoded, names = pcall(HttpService.JSONDecode, HttpService, whitelistRaw)
        if decoded and type(names) == "table" then
            table.clear(whitelist)
            for _, name in ipairs(names) do
                if type(name) == "string" and name ~= "" then whitelist[string.lower(name)] = true end
            end
            hasSavedWhitelist = true
        end
    end
    local ok, raw = pcall(readfile, metaFile)
    if ok then
        local decodedOk, meta = pcall(HttpService.JSONDecode, HttpService, raw)
        if decodedOk and type(meta) == "table" and validName(meta.autoload) then autoloadConfig = meta.autoload end
    end
end

local function setFlag(key, value, fromUi)
    if value and (key == "noFall" or key == "noDrown") and not damageHook then notify("Damage interception unsupported", "Protection"); return end
    if value and key == "fastBreak" and not breakHook then notify("Function hooking unsupported", "Mining"); return end
    if key == "oreDistance" or key == "playerNameDistance" then
        local minimum = key == "oreDistance" and 50 or 25
        value = math.clamp(tonumber(value) or minimum, minimum, 800)
    end
    if settings[key] == value then return end
    settings[key] = value
    if controls[key] and not fromUi then pcall(function() controls[key]:Set(value) end) end
    if key == "noclip" and not value then restoreCollision() end
    if key == "speed" and not value and currentHumanoid and normalWalkSpeed then currentHumanoid.WalkSpeed = normalWalkSpeed end
    if key == "jump" and not value then restoreMovement() end
    if (key == "playerNames" or key == "animalNames") and not value then
        for model in pairs(nameLabels) do
            if (Players:GetPlayerFromCharacter(model) ~= nil) == (key == "playerNames") then removeName(model) end
        end
    end
    if key == "theme" and window then window:ChangeTheme(value == "Light" and "frost" or "default") end
    if value and (key == "diamondXray" or key == "ironXray" or key == "coalXray" or key == "goldXray") then task.spawn(refreshOreLocations) end
    syncHooks()
    if indicatorKeys[key] then updateActiveList() end
end

local function loadConfig(name)
    if not canPersist then notify("File persistence is unavailable", "Configs"); return false end
    local ok, raw = pcall(readfile, configPath(name))
    if not ok then notify("Configuration not found: " .. name, "Configs"); return false end
    local decodedOk, data = pcall(HttpService.JSONDecode, HttpService, raw)
    if not decodedOk or type(data) ~= "table" then notify("Configuration JSON is invalid", "Configs"); return false end
    local values = type(data.settings) == "table" and data.settings or data
    for key, current in pairs(settings) do
        local value = values[key]
        if value ~= nil then
            if typeof(current) == "Color3" and type(value) == "table" and #value == 3 then
                value = Color3.fromRGB(tonumber(value[1]) or 255, tonumber(value[2]) or 255, tonumber(value[3]) or 255)
            end
            if typeof(value) == typeof(current) then setFlag(key, value) end
        end
    end
    if not hasSavedWhitelist and type(data.whitelist) == "table" then
        for _, nameValue in ipairs(data.whitelist) do if type(nameValue) == "string" then whitelist[string.lower(nameValue)] = true end end
        saveWhitelist()
    end
    if type(data.keybinds) == "table" then
        for id, code in pairs(defaultKeybinds) do keybinds[id] = code end
        local used = {RightControl = "Open menu"}
        for _, binding in ipairs(bindings) do
            local code = data.keybinds[binding.id]
            local validKey = type(code) == "string" and (code == "None" or Enum.KeyCode[code])
            local menuKeepsKey = binding.id ~= "toggleUi" or code ~= "None"
            local available = code == "None" or (code == "RightControl" and binding.id == "toggleUi") or not used[code]
            if validKey and menuKeepsKey and available then
                keybinds[binding.id] = code
                if code ~= "None" then used[code] = binding.label end
            end
        end
    end
    activeConfig = name
    if refreshKeybindInfo then refreshKeybindInfo() end
    notify("Loaded " .. name, "Configs")
    return true
end

if autoloadConfig then loadConfig(autoloadConfig) end
saveWhitelist()

local function saveConfig(requestedName, overwrite)
    local name = validName(requestedName)
    if not name then notify("Use 1-40 letters, numbers, spaces, _ or -", "Configs"); return false end
    if not canPersist then notify("File persistence is unavailable", "Configs"); return false end
    if not overwrite then
        for _, existing in ipairs(listConfigs()) do
            if string.lower(existing) == string.lower(name) then notify("Configuration already exists", "Configs"); return false end
        end
    end
    local ok, err = pcall(writefile, configPath(name), HttpService:JSONEncode(snapshot()))
    if not ok then notify("Save failed: " .. tostring(err), "Configs"); return false end
    activeConfig = name
    notify("Saved " .. name, "Configs")
    return true
end

local function removeConfig(name)
    if not canPersist or type(delfile) ~= "function" then notify("Delete is unavailable", "Configs"); return false end
    local ok = pcall(delfile, configPath(name))
    if not ok then notify("Delete failed", "Configs"); return false end
    if activeConfig == name then activeConfig = nil end
    if autoloadConfig == name then autoloadConfig = nil; writeMeta() end
    notify("Deleted " .. name, "Configs")
    return true
end

local function configNamesText(search)
    local matches = {}
    for _, name in ipairs(listConfigs()) do
        if string.find(string.lower(name), string.lower(search or ""), 1, true) then
            table.insert(matches, name .. (name == activeConfig and " [loaded]" or "") .. (name == autoloadConfig and " [autoload]" or ""))
        end
    end
    return #matches > 0 and table.concat(matches, "\n") or "No matching configurations"
end

local function whitelistText(search)
    local matches = {}
    for name in pairs(whitelist) do if string.find(name, string.lower(search or ""), 1, true) then table.insert(matches, name) end end
    table.sort(matches)
    return #matches > 0 and table.concat(matches, "\n") or "No matching names"
end

local function updateKeybind(name, code)
    local binding = bindingById[name]
    if not binding or (code ~= "None" and not Enum.KeyCode[code]) then
        notify("Unknown key", "Keybinds")
        return false
    end
    if name == "toggleUi" and code == "None" then
        notify("The menu key cannot be cleared", "Keybinds")
        return false
    end
    if name ~= "toggleUi" and code == "RightControl" then
        notify("RightControl always opens the menu", "Keybinds")
        return false
    end
    for other, existing in pairs(keybinds) do
        if other ~= name and code ~= "None" and existing == code then
            notify(code .. " is already used by " .. bindingById[other].label, "Keybinds")
            return false
        end
    end
    keybinds[name] = code
    notify(binding.label .. ": " .. (code == "None" and "unbound" or code), "Keybinds")
    return true
end

local function findAuraTarget(kind, root, radius)
    local nearestRoot, nearestCharacter, nearestDistance = nil, nil, radius
    if kind == "player" then
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and not protected(player) and player.Character and isLiving(player.Character) then
                local targetRoot = player.Character:FindFirstChild("HumanoidRootPart")
                if targetRoot then
                    local distance = (targetRoot.Position - root.Position).Magnitude
                    if distance < nearestDistance then nearestRoot, nearestCharacter, nearestDistance = targetRoot, player.Character, distance end
                end
            end
        end
    else
        for model in pairs(animals) do
            if model.Parent and isAnimal(model) and isLiving(model) then
                local part = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart") or model:FindFirstChildWhichIsA("BasePart", true)
                if part then
                    local distance = (part.Position - root.Position).Magnitude
                    if distance < nearestDistance then nearestRoot, nearestCharacter, nearestDistance = part, model, distance end
                end
            end
        end
    end
    return nearestRoot, nearestCharacter, nearestDistance
end

local attackAttempts = {player = 0, animal = 0}
local function auraTick(kind)
    if kind == "player" then
        if not settings.killAura then return end
    elseif kind == "animal" then
        if not settings.animalAura or not ActionsSystem or type(ActionsSystem.client_attackEntity) ~= "function" then return end
    else
        return
    end
    local root = getRoot()
    if not root then return end
    local nearestRoot, nearestCharacter = findAuraTarget(kind, root, kind == "player" and settings.auraRange or settings.animalAuraRange)
    if not nearestRoot then return end
    if kind == "animal" and not isAnimal(nearestCharacter) then return end
    if settings.faceTarget then
        local target = Vector3.new(nearestRoot.Position.X, root.Position.Y, nearestRoot.Position.Z)
        if (target - root.Position).Magnitude > 0.1 then
            root.CFrame = CFrame.lookAt(root.Position, target)
        end
    end
    local weapon = selectWeapon()
    if kind == "animal" and (not isAnimal(nearestCharacter) or not isLiving(nearestCharacter)) then return end
    if ActionsSystem then
        attackAttempts[kind] += 1
        pcall(ActionsSystem.client_attackEntity, nearestCharacter)
    elseif kind == "player" and weapon then
        weapon:Activate()
    end
end

local function stop()
    if not alive then return end
    saveWhitelist()
    alive = false
    for _, connection in ipairs(connections) do connection:Disconnect() end
    for player, playerConnections in pairs(playerCharacterConnections) do
        for _, connection in ipairs(playerConnections) do connection:Disconnect() end
        playerCharacterConnections[player] = nil
    end
    for key in pairs(visuals) do removeVisual(key) end
    for model in pairs(nameLabels) do removeName(model) end
    settings.noFall = false
    settings.noDrown = false
    settings.fastBreak = false
    syncHooks()
    for index, marker in pairs(oreMarkers) do
        marker.part:Destroy()
        oreMarkers[index] = nil
    end
    restoreMovement()
    restoreCollision()
    if window and not window.unloaded then window:Unload() end
    if env.TerraformHelper and env.TerraformHelper.Stop == stop then
        env.TerraformHelper = nil
    end
end

env.TerraformHelper = {
    Stop = stop,
    Status = function()
        local nearest = {diamond = math.huge, iron = math.huge, coal = math.huge, gold = math.huge}
        local root = getRoot()
        if root then
            for _, ore in ipairs(oreLocations) do
                local distance = (ore.position - root.Position).Magnitude
                if distance < nearest[ore.kind] then nearest[ore.kind] = distance end
            end
        end
        return {
            indexedOres = #oreLocations,
            activeMarkers = #oreMarkers,
            activeHighlights = (function()
                local count = 0
                for _ in pairs(visuals) do count += 1 end
                return count
            end)(),
            nearestOre = nearest,
            diamondXray = settings.diamondXray,
            ironXray = settings.ironXray,
            coalXray = settings.coalXray,
            goldXray = settings.goldXray,
            oreDistance = settings.oreDistance,
            playerEsp = settings.playerEsp,
            animalEsp = settings.animalEsp,
            playerNames = settings.playerNames,
            animalNames = settings.animalNames,
            activeNames = (function()
                local n = 0
                for _ in pairs(nameLabels) do n += 1 end
                return n
            end)(),
            playerAura = settings.killAura,
            animalAura = settings.animalAura,
            attackAttempts = table.clone(attackAttempts),
            protectedPlayers = (function()
                local n = 0
                for _, player in ipairs(Players:GetPlayers()) do
                    if protected(player) then n += 1 end
                end
                return n
            end)(),
            noFall = settings.noFall,
            noDrown = settings.noDrown,
            fastBreak = settings.fastBreak,
            activeConfig = activeConfig,
        }
    end,
    SetFlag = function(flag, value)
        if window then window:Set(flag, value) end
    end,
    Set = setFlag,
    AddFriend = function(name) return setWhitelisted(name, true) end,
    RemoveFriend = function(name) return setWhitelisted(name, false) end,
    IsProtected = protected,
    ConfigSnapshot = snapshot,
    LoadConfig = loadConfig,
    SaveConfig = saveConfig,
    ListConfigs = listConfigs,
    PreviewTarget = function(kind, radius)
        local root = getRoot()
        if not root or (kind ~= "player" and kind ~= "animal") then return nil end
        local _, model, distance = findAuraTarget(kind, root, radius or (kind == "player" and settings.auraRange or settings.animalAuraRange))
        return model and model.Name or nil, distance
    end,
}

task.spawn(function()
    while alive do
        updateEsp()
        if settings.playerNames or settings.animalNames then updateNames() end
        applyMovement()
        task.wait(anyOreXray() and 0.25 or 0.5)
    end
end)

task.spawn(function()
    while alive do
        auraTick("player")
        auraTick("animal")
        task.wait(0.18)
    end
end)

local Rayfield = loadstring(game:HttpGet("https://sirius.menu/gen2"))()
window = Rayfield:CreateWindow({
    name = "Strata",
    subtitle = "Terraform utility",
    sidebarLayout = true,
    theme = settings.theme == "Light" and "frost" or "default",
})

local function toggle(tab, name, key, description)
    controls[key] = tab:CreateToggle({name = name, description = description, flag = key, value = settings[key], callback = function(value) setFlag(key, value, true) end})
end
local function slider(tab, name, key, minimum, maximum, step, suffix)
    controls[key] = tab:CreateSlider({name = name, flag = key, range = {minimum, maximum}, increment = step, value = settings[key], suffix = suffix, callback = function(value) setFlag(key, value, true) end})
end
local function color(tab, name, key)
    controls[key] = tab:CreateColorPicker({name = name, flag = key, color = settings[key], callback = function(value) settings[key] = value end})
end

local activeTab = window:CreateTab({name = "Active"})
activeList = activeTab:CreateText({name = "Enabled features", text = "Nothing active"})
updateActiveList()

local visualTab = window:CreateTab({name = "X-ray"})
visualTab:CreateSection({name = "Ore X-ray"})
toggle(visualTab, "Diamond X-ray", "diamondXray")
toggle(visualTab, "Iron X-ray", "ironXray")
toggle(visualTab, "Coal X-ray", "coalXray")
toggle(visualTab, "Gold X-ray", "goldXray")
slider(visualTab, "Ore range", "oreDistance", 50, 800, 25, " studs")
visualTab:CreateText({name = "Ore detection", text = "Scans up to 800 studs and marks the 20 nearest matching voxels from loaded Terraform chunks."})

local combatTab = window:CreateTab({name = "Combat"})
combatTab:CreateSection({name = "Player aura"})
toggle(combatTab, "Player kill aura", "killAura")
slider(combatTab, "Player radius", "auraRange", 4, 28, 1, " studs")
toggle(combatTab, "Face target", "faceTarget")
toggle(combatTab, "Friend protection", "friendProtection", "Protect Roblox friends and saved whitelist usernames.")
combatTab:CreateText({name = "Whitelist saving", text = "Usernames save automatically across reloads. Config loading keeps your current whitelist."})
combatTab:CreateInput({name = "Username", placeholder = "Exact Roblox username", callback = function(value) whitelistInput = value end})
local whitelistList
combatTab:CreateButton({name = "Add username to whitelist", callback = function()
    local name = string.lower(string.match(whitelistInput, "^%s*(.-)%s*$") or "")
    if name == "" then notify("Enter a username", "Whitelist"); return end
    setWhitelisted(name, true)
    notify("Protected " .. name, "Whitelist")
    whitelistList:Set(whitelistText(whitelistSearch))
end})
combatTab:CreateButton({name = "Remove username from whitelist", callback = function()
    setWhitelisted(whitelistInput, false)
    notify("Removed " .. whitelistInput, "Whitelist")
    whitelistList:Set(whitelistText(whitelistSearch))
end})
whitelistList = combatTab:CreateText({name = "Whitelisted usernames", text = whitelistText("")})
combatTab:CreateInput({name = "Search whitelist", placeholder = "Filter saved names", callback = function(value)
    whitelistSearch = value
    whitelistList:Set(whitelistText(value))
end})
combatTab:CreateSection({name = "Animal aura"})
toggle(combatTab, "Animal kill aura", "animalAura")
slider(combatTab, "Animal radius", "animalAuraRange", 4, 28, 1, " studs")
combatTab:CreateText({name = "Target rules", text = "Player aura skips protected users. Animal aura only attacks living non-player models. Server hit checks still apply."})

local espTab = window:CreateTab({name = "ESP"})
espTab:CreateSection({name = "Player names"})
toggle(espTab, "Player Name ESP", "playerNames", "Roblox friends and whitelisted usernames appear green.")
toggle(espTab, "Player highlight", "playerEsp", "Friends and whitelisted players are green; others are red.")
toggle(espTab, "Use display names", "displayNames")
toggle(espTab, "Hide local name", "hideLocalName")
slider(espTab, "Player render distance", "playerNameDistance", 25, 800, 25, " studs")
slider(espTab, "Player text size", "playerNameSize", 10, 28, 1)
slider(espTab, "Player transparency", "playerNameTransparency", 0, 1, 0.05)
color(espTab, "Player label color", "playerNameColor")
espTab:CreateSection({name = "Animal names"})
toggle(espTab, "Animal Name ESP", "animalNames")
toggle(espTab, "Animal highlight", "animalEsp")
slider(espTab, "Animal render distance", "animalNameDistance", 25, 500, 5, " studs")
slider(espTab, "Animal text size", "animalNameSize", 10, 28, 1)
slider(espTab, "Animal transparency", "animalNameTransparency", 0, 1, 0.05)
color(espTab, "Animal label color", "animalNameColor")
espTab:CreateSection({name = "Shared"})
toggle(espTab, "Show distance", "showDistance")

local movementTab = window:CreateTab({name = "Movement"})
movementTab:CreateSection({name = "Protection"})
toggle(movementTab, "No fall damage", "noFall", damageHook and "Blocks Terraform's fall damage remote." or "Unsupported by this executor")
toggle(movementTab, "No drowning damage", "noDrown", damageHook and "Blocks Terraform's drowning damage remote." or "Unsupported by this executor")
movementTab:CreateSection({name = "Mining"})
toggle(movementTab, "Insta Break", "fastBreak", breakHook and "Breaks blocks instantly." or "Unsupported by this executor")
movementTab:CreateSection({name = "Movement"})
toggle(movementTab, "Speed", "speed")
slider(movementTab, "Walk speed", "walkSpeed", 16, 80, 1)
toggle(movementTab, "Jump boost", "jump")
slider(movementTab, "Jump power", "jumpPower", 50, 150, 5)
toggle(movementTab, "Infinite jump", "infiniteJump")
toggle(movementTab, "Phase", "noclip")

local configsTab = window:CreateTab({name = "Configs"})
configsTab:CreateText({name = "Storage", text = canPersist and "Saved in the Strata configuration folder" or "Executor file functions unavailable; configs cannot persist."})
local configList = configsTab:CreateText({name = "Saved configurations", text = configNamesText("")})
local function refreshLists()
    configList:Set(configNamesText(configSearch))
    whitelistList:Set(whitelistText(whitelistSearch))
end
configsTab:CreateInput({name = "Search configs", placeholder = "Filter names", callback = function(value) configSearch = value; refreshLists() end})
configsTab:CreateInput({name = "Config name", placeholder = "Type a name to create or select", callback = function(value) configInput = value end})
configsTab:CreateButton({name = "Create", callback = function() if saveConfig(configInput, false) then refreshLists() end end})
configsTab:CreateButton({name = "Save / overwrite selected", callback = function() if saveConfig(configInput ~= "" and configInput or activeConfig, true) then refreshLists() end end})
configsTab:CreateButton({name = "Load", callback = function() if loadConfig(configInput) then refreshLists() end end})
configsTab:CreateButton({name = "Set autoload", callback = function()
    if validName(configInput) and pcall(readfile, configPath(configInput)) then autoloadConfig = configInput; writeMeta(); refreshLists(); notify("Autoload set to " .. configInput, "Configs")
    else notify("Select an existing configuration", "Configs") end
end})
configsTab:CreateButton({name = "Disable autoload", callback = function() autoloadConfig = nil; writeMeta(); refreshLists(); notify("Autoload disabled", "Configs") end})
configsTab:CreateInput({name = "New name", placeholder = "For rename or duplicate", callback = function(value) newConfigName = value end})
configsTab:CreateButton({name = "Duplicate", callback = function()
    local newName = validName(newConfigName)
    if not newName or not canPersist then notify("Enter a valid new name", "Configs"); return end
    local ok, raw = pcall(readfile, configPath(configInput))
    if not ok then notify("Source config missing", "Configs"); return end
    for _, name in ipairs(listConfigs()) do if string.lower(name) == string.lower(newName) then notify("Name exists", "Configs"); return end end
    if pcall(writefile, configPath(newName), raw) then refreshLists(); notify("Duplicated to " .. newName, "Configs") end
end})
configsTab:CreateButton({name = "Rename", callback = function()
    local newName = validName(newConfigName)
    if not newName or not canPersist then notify("Enter a valid new name", "Configs"); return end
    local ok, raw = pcall(readfile, configPath(configInput))
    if not ok then notify("Source config missing", "Configs"); return end
    for _, name in ipairs(listConfigs()) do if string.lower(name) == string.lower(newName) then notify("Name exists", "Configs"); return end end
    local wasActive, wasAutoload = activeConfig == configInput, autoloadConfig == configInput
    if pcall(writefile, configPath(newName), raw) and removeConfig(configInput) then
        if wasActive then activeConfig = newName end
        if wasAutoload then autoloadConfig = newName; writeMeta() end
        configInput = newName; refreshLists()
    end
end})
configsTab:CreateButton({name = "Delete (click twice to confirm)", callback = function()
    if pendingDelete == configInput and configInput ~= "" then removeConfig(configInput); pendingDelete = nil; refreshLists()
    else pendingDelete = configInput; notify("Click Delete again to remove " .. configInput, "Configs") end
end})
configsTab:CreateButton({name = "Export JSON to clipboard", callback = function()
    if type(setclipboard) == "function" then setclipboard(HttpService:JSONEncode(snapshot())); notify("Current settings copied as JSON", "Configs")
    else notify("Clipboard unavailable", "Configs") end
end})
configsTab:CreateInput({name = "Import JSON", placeholder = "Paste JSON, then create with Config name", callback = function(value) importJson = value end})
configsTab:CreateButton({name = "Import as new config", callback = function()
    local ok, data = pcall(HttpService.JSONDecode, HttpService, importJson)
    if not ok or type(data) ~= "table" or type(data.settings) ~= "table" then notify("Invalid configuration JSON", "Configs"); return end
    local name = validName(configInput)
    if not name or not canPersist then notify("Enter a valid config name", "Configs"); return end
    for _, existing in ipairs(listConfigs()) do if string.lower(existing) == string.lower(name) then notify("Name exists", "Configs"); return end end
    if pcall(writefile, configPath(name), HttpService:JSONEncode(data)) then refreshLists(); notify("Imported " .. name, "Configs") end
end})

local keybindsTab = window:CreateTab({name = "Keybinds"})
local captureBind = nil
local capturePrompt = keybindsTab:CreateText({
    name = "Set a shortcut",
    text = "Click a feature, then press a key. Escape cancels; Backspace or Delete clears it.",
})
local keybindInfo = keybindsTab:CreateText({name = "Current shortcuts", text = ""})
refreshKeybindInfo = function()
    local lines = {}
    for _, binding in ipairs(bindings) do
        local key = keybinds[binding.id]
        table.insert(lines, binding.label .. ": " .. (key == "None" and "—" or key))
    end
    keybindInfo:Set(table.concat(lines, "\n"))
end
for _, group in ipairs({"Menu", "Combat", "ESP", "Ores", "Movement"}) do
    keybindsTab:CreateSection({name = group})
    for _, binding in ipairs(bindings) do
        if binding.group == group then
            local target = binding
            keybindsTab:CreateButton({name = "Bind " .. target.label, callback = function()
                captureBind = target.id
                capturePrompt:Set("Press a key for " .. target.label .. ". Escape cancels; Backspace clears.")
            end})
        end
    end
end
keybindsTab:CreateButton({name = "Reset all shortcuts", callback = function()
    for id, key in pairs(defaultKeybinds) do keybinds[id] = key end
    captureBind = nil
    capturePrompt:Set("Shortcuts reset. RightControl opens the menu.")
    refreshKeybindInfo()
end})

local aboutTab = window:CreateTab({name = "About"})
aboutTab:CreateText({name = "Credits", text = "Creator: ReSqop\nRScripts: https://rscripts.net/@ReSqop"})

local settingsTab = window:CreateTab({name = "Settings"})
settingsTab:CreateButton({name = "Stop helper and restore", callback = stop})
local searchableFeatures = {
    {"Diamond X-ray", "X-ray"}, {"Iron X-ray", "X-ray"}, {"Coal X-ray", "X-ray"}, {"Gold X-ray", "X-ray"},
    {"Player kill aura", "Combat"}, {"Animal kill aura", "Combat"}, {"Whitelist", "Combat"},
    {"Player Name ESP", "ESP"}, {"Animal Name ESP", "ESP"}, {"Player highlight", "ESP"}, {"Animal highlight", "ESP"},
    {"No fall damage", "Movement"}, {"No drowning damage", "Movement"}, {"Insta Break", "Movement"},
    {"Speed", "Movement"}, {"Jump boost", "Movement"}, {"Phase", "Movement"},
    {"Configurations", "Configs"}, {"Keybinds", "Keybinds"}, {"Active features", "Active"},
}
local firstMatch = nil
local featureMatches = settingsTab:CreateText({name = "Feature search", text = "Type a feature name below"})
settingsTab:CreateInput({name = "Search features", placeholder = "Name or category", callback = function(query)
    local lines = {}
    firstMatch = nil
    for _, item in ipairs(searchableFeatures) do
        if string.find(string.lower(item[1] .. " " .. item[2]), string.lower(query), 1, true) then
            if not firstMatch then firstMatch = item[2] end
            table.insert(lines, item[1] .. " — " .. item[2])
        end
    end
    featureMatches:Set(#lines > 0 and table.concat(lines, "\n") or "No matches")
end})
settingsTab:CreateButton({name = "Open first search result", callback = function()
    if firstMatch then window:Navigate(firstMatch) else notify("Search for a feature first", "Search") end
end})
controls.theme = settingsTab:CreateDropdown({name = "Theme", options = {"Dark", "Light"}, value = settings.theme, callback = function(value)
    setFlag("theme", value)
end})
settingsTab:CreateButton({name = "Reset feature defaults", callback = function()
    for key, value in pairs(defaultSettings) do setFlag(key, value) end
    for key, value in pairs(defaultKeybinds) do keybinds[key] = value end
    captureBind = nil
    capturePrompt:Set("Click a feature, then press a key. Escape cancels; Backspace or Delete clears it.")
    refreshLists(); refreshKeybindInfo(); notify("Defaults restored", "Settings")
end})

track(UserInputService.InputBegan:Connect(function(input, processed)
    if not alive or input.UserInputType ~= Enum.UserInputType.Keyboard then return end
    local key = input.KeyCode.Name
    if captureBind then
        if key == "Escape" then
            captureBind = nil
            capturePrompt:Set("Cancelled. Click a feature to set a shortcut.")
            return
        end
        if key == "Unknown" then return end
        local code = (key == "Backspace" or key == "Delete") and "None" or key
        if updateKeybind(captureBind, code) then
            captureBind = nil
            capturePrompt:Set(code == "None" and "Shortcut cleared." or "Shortcut saved. Click another feature to change its key.")
            refreshKeybindInfo()
        end
        return
    end
    if processed then return end
    if key == keybinds.toggleUi or key == "RightControl" then window:ToggleHide(); return end
    for _, binding in ipairs(bindings) do
        if binding.flag and keybinds[binding.id] == key then
            setFlag(binding.flag, not settings[binding.flag])
            return
        end
    end
end))

refreshLists()
refreshKeybindInfo()
window:Notify({title = "Strata", content = "Ready. RightControl reopens the GUI.", duration = 4})

