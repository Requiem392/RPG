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
    

    
    -- 2. Identifica Arma (Estado via Atributo - Fonte da verdade)
    local weaponName = attackerChar:GetAttribute("EquippedWeapon")
    
    if not weaponName or weaponName == "" then return end
    
    local itemInfo = ItemData.Get(weaponName)
    if not itemInfo then return end

    -- 3. Resolve Defesa (DefenseHandler Pure)
    local defHandler = DefenseHandler.Registry[targetEntity]
    
    -- Default Result
    local result = { Status = "Hit", Multiplier = 1, StunDuration = 0, DamageReturn = 0, PostureDamage = 0 }
    
    if defHandler then
        -- ResolveHit retorna tabela
        result = defHandler:ResolveHit(attackerPlayer, {
            Weapon = itemInfo, 
            Position = hitPosition
        })
    end
    
    -- 4. Aplica Resultado (Orchestration)
    
    -- === PARRY ===
    if result.Status == "Parry" then
        print("⚔️ PARRY!", targetChar.Name)
        
        -- Efeito no atacante (Orchestrated)
        -- 1. Dano de Retorno
        local attackerHumanoid = attackerChar:FindFirstChild("Humanoid")
        if attackerHumanoid and result.DamageReturn > 0 then
             attackerHumanoid:TakeDamage(result.DamageReturn)
             -- VFX Dano Parry?
        end
        
        -- 2. Stun no Atacante
        local attackerDef = DefenseHandler.Registry[attackerPlayer]
        if attackerDef and result.StunDuration > 0 then
             attackerDef:Stun(result.StunDuration)
        end
        
        -- 3. VFX/Sound Parry
        -- TODO: Adicionar som de Parry aqui
        return
    end
    
    -- === BLOCK ===
    if result.Status == "Block" then
        print("🛡️ BLOCK!", targetChar.Name)
        
        -- 1. VFX/Sound Block
        local blockSoundId = ItemData.GetCategorySound(itemInfo.WeaponCategory, "Block")
        if blockSoundId then
            local sound = Instance.new("Sound")
            sound.SoundId = blockSoundId
            sound.Volume = 0.8
            sound.Parent = targetChar:FindFirstChild("HumanoidRootPart") or targetChar.PrimaryPart
            sound:Play()
            Debris:AddItem(sound, 2)
        end
        
        -- 2. Posture Damage
        local posHandler = PostureHandler.Registry[targetEntity]
        if posHandler then
             -- Calculamos dano de postura aqui ou Stats?
             -- Vamos usar um valor base da arma por enquanto
            local postureDmg = 15 -- Valor base 
            -- Se Block tiver multiplier de postura, podemos usar.
            posHandler:Damage(postureDmg)
        end
        return
    end
    
    -- === HIT ===
    if result.Status == "Hit" then
        -- 1. Calcula Dano (StatsHandler)
        local attackerStats = StatsHandler.Registry[attackerPlayer]
        local targetStats = StatsHandler.Registry[targetEntity]
        
        local hitData = {Damage = 10, IsCritical = false}
        if attackerStats then
            hitData = attackerStats:CalculateHit(targetStats, weaponName)
        end
        
        -- 2. Aplica HP
        targetHumanoid:TakeDamage(hitData.Damage)
        
        -- 3. VFX
        if VFXEvent then
            VFXEvent:FireAllClients("Sangue", hitPosition, Vector3.new(0,1,0))
        end
        
        -- 4. Som
        local hitSoundId = ItemData.GetCategorySound(itemInfo.WeaponCategory, "Hit")
        if hitSoundId then
            local sound = Instance.new("Sound")
            sound.SoundId = hitSoundId
            sound.Volume = 0.7
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
