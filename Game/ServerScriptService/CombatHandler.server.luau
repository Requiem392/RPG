local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")

-- Módulos
local ItemData = require(game.ReplicatedStorage:WaitForChild("Data"):WaitForChild("ItemData"))
local Modules = ServerScriptService:WaitForChild("Modules")

-- Handlers (Classes)
local DefenseHandler = require(Modules:WaitForChild("DefenseHandler"))
local PostureHandler = require(Modules:WaitForChild("PostureHandler"))
local StatsHandler = require(Modules:WaitForChild("StatsHandler"))

-- Eventos
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local CombatRemote = Remotes:WaitForChild("CombatAction")
local VFXEvent = Remotes:FindFirstChild("EventoVFX")

-- Anti-Spam (apenas validação temporal simples)
local PlayerHitCooldowns = {} 
local HIT_COOLDOWN = 0.08 
local MAX_HIT_DISTANCE = 15 

-- ============================================================================
-- VALIDAÇÃO (Pure)
-- ============================================================================

local function ValidateHit(player, targetChar, hitPosition)
	if not player.Character then return false end
	local rootPart = player.Character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return false end

	local distance = (rootPart.Position - hitPosition).Magnitude
	if distance > MAX_HIT_DISTANCE then return false end

	if not PlayerHitCooldowns[player] then PlayerHitCooldowns[player] = {} end
	local now = tick()
	local lastHit = PlayerHitCooldowns[player][targetChar]
	if lastHit and (now - lastHit) < HIT_COOLDOWN then return false end

	PlayerHitCooldowns[player][targetChar] = now
	return true
end

-- ============================================================================
-- APLICAÇÃO (Orquestrador)
-- ============================================================================

local function ProcessHit(attackerPlayer, targetChar, hitPosition)
    local attackerChar = attackerPlayer.Character
    if not attackerChar then return end

    -- 1. Identifica Alvo
    local targetHumanoid = targetChar:FindFirstChild("Humanoid")
    if not targetHumanoid or targetHumanoid.Health <= 0 then return end
    
    local targetEntity = Players:GetPlayerFromCharacter(targetChar) or targetChar -- Player ou Model
    
    -- 2. Identifica Arma (Estado via Atributo seria ideal, mas pegamos visual por segurança aqui)
    -- Ou melhor: InventoryHandler.Registry[attackerPlayer]:GetGear().Weapon?
    -- Vamos usar o que já funciona para pegar o nome da arma do modelo visual para garantir sync com animação.
    local weaponName = nil
	for _, child in pairs(attackerChar:GetChildren()) do
		if child:IsA("Model") and child:FindFirstChild("Hitbox") then
			weaponName = string.gsub(child.Name, "Equipped_", "")
			break
		end
	end
    if not weaponName then return end
    
    local itemInfo = ItemData.Get(weaponName)
    if not itemInfo then return end

    -- 3. Resolve Defesa (DefenseHandler)
    local defHandler = DefenseHandler.Registry[targetEntity]
    local result = "Hit"
    
    if defHandler then
        result = defHandler:ResolveHit(attackerPlayer, {
            Weapon = itemInfo, 
            Position = hitPosition
        })
    end
    
    -- 4. Aplica Resultado
    if result == "Parry" then
        print("⚔️ PARRY!", targetChar.Name)
        -- Efeito no atacante? Quem decide o stun é o DefenseHandler (interno) ou combat?
        -- Pelo request: CombatHandler aplica. Mas DefenseHandler já chamou OnParrySuccess internamente.
        -- Se DefenseHandler:ResolveHit retornou "Parry", significa que o sucesso já foi computado pro defensor.
        -- Falta punir o atacante.
        local attackerHumanoid = attackerChar:FindFirstChild("Humanoid")
        if attackerHumanoid then
             -- Dano de retorno fixo ou calculado?
             attackerHumanoid:TakeDamage(5) -- Exemplo dummy
             -- Stun?
             local attackerDef = DefenseHandler.Registry[attackerPlayer]
             if attackerDef then attackerDef:Stun(1.5) end
        end
        return
        
    elseif result == "Block" then
        print("🛡️ BLOCK!", targetChar.Name)
        -- VFX Block
        -- VFX Block
        local blockSoundId = ItemData.GetCategorySound(itemInfo.WeaponCategory, "Block")
        if blockSoundId then
            local sound = Instance.new("Sound")
            sound.SoundId = blockSoundId
            sound.Parent = targetChar:FindFirstChild("HumanoidRootPart") or targetChar.PrimaryPart
            sound:Play()
            Debris:AddItem(sound, 2)
        end
        
        -- Dano Postura
        -- Pede pro Stats ou Posture calcular o dano?
        -- Simplificado: Dano base na postura
        local posHandler = PostureHandler.Registry[targetEntity]
        if posHandler then
            posHandler:Damage(10) -- Valor fixo ou vindo do ItemData
        end
        return
    end
    
    -- 5. HIT Confirmado (Dano HP)
    if result == "Hit" then
        -- Calcula Dano (StatsHandler)
        local attackerStats = StatsHandler.Registry[attackerPlayer]
        local targetStats = StatsHandler.Registry[targetEntity]
        
        -- Se não tiver handler (ex: Mob simples sem stats), usa nil
        local hitData = {Damage = 10, IsCritical = false}
        
        if attackerStats then
            hitData = attackerStats:CalculateHit(targetStats, weaponName)
        end
        
        -- Aplica HP
        targetHumanoid:TakeDamage(hitData.Damage)
        
        -- VFX
        if VFXEvent then
            VFXEvent:FireAllClients("Sangue", hitPosition, Vector3.new(0,1,0))
        end
        
        -- Som
        -- Som
        local hitSoundId = ItemData.GetCategorySound(itemInfo.WeaponCategory, "Hit")
        if hitSoundId then
            local sound = Instance.new("Sound")
            sound.SoundId = hitSoundId
            sound.Parent = targetChar:FindFirstChild("HumanoidRootPart") or targetChar.PrimaryPart
            sound:Play()
            Debris:AddItem(sound, 2)
        end
        
        print("💥 Hit:", hitData.Damage, "Crit:", hitData.IsCritical)
    end
end

-- ============================================================================
-- EVENTOS
-- ============================================================================

CombatRemote.OnServerEvent:Connect(function(player, action, ...)
	if action == "RegisterHit" then
		local targetChar, hitPosition = ...
        if not targetChar or not hitPosition then return end
        
		if ValidateHit(player, targetChar, hitPosition) then
			ProcessHit(player, targetChar, hitPosition)
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	PlayerHitCooldowns[player] = nil
end)

print("✅ CombatHandler Orquestrador Iniciado")
