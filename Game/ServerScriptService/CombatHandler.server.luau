local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")

-- Módulos
local ItemData = require(game.ReplicatedStorage:WaitForChild("Data"):WaitForChild("ItemData"))
local Modules = ServerScriptService:WaitForChild("Modules")

-- Handlers (Novos Classes)
local DefenseHandler = require(Modules:WaitForChild("DefenseHandler"))
local PostureHandler = require(Modules:WaitForChild("PostureHandler"))
-- local StatsHandler = require(Modules:WaitForChild("StatsHandler")) -- Se precisar de dano base

-- Eventos
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local CombatRemote = Remotes:WaitForChild("CombatAction")
local VFXEvent = Remotes:FindFirstChild("EventoVFX")

-- Estado
local PlayerAttackCooldowns = {} -- Anti-cheat: {[Player] = lastAttackTime}
local PlayerHitCooldowns = {} -- Anti-spam: {[Player] = {[Target] = lastHitTime}}

-- === CONFIGURAÇÃO ANTI-CHEAT ===
local MAX_HIT_DISTANCE = 15 
local HIT_COOLDOWN = 0.08 
local ATTACK_RATE_LIMIT = 0.3 

-- === FUNÇÕES DE VALIDAÇÃO ===

local function ValidateHit(player, targetChar, hitPosition)
	local character = player.Character
	if not character then return false, "Sem personagem" end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return false, "Sem RootPart" end

	local distance = (rootPart.Position - hitPosition).Magnitude
	if distance > MAX_HIT_DISTANCE then
		warn("⚠️ [CombatHandler] Hit rejeitado - distância:", distance)
		return false, "Muito longe"
	end

	if not PlayerHitCooldowns[player] then
		PlayerHitCooldowns[player] = {}
	end

	local now = tick()
	local lastHit = PlayerHitCooldowns[player][targetChar]
	if lastHit and (now - lastHit) < HIT_COOLDOWN then
		return false, "Cooldown"
	end

	PlayerHitCooldowns[player][targetChar] = now
	return true
end

-- === APLICAÇÃO DE DANO ===

local function ApplyDamage(player, targetChar, hitPosition)
	local targetHumanoid = targetChar:FindFirstChild("Humanoid")
	if not targetHumanoid or targetHumanoid.Health <= 0 then 
		return 
	end

    -- Identifica Entidade Alvo (Player ou NPC)
	local targetPlayer = Players:GetPlayerFromCharacter(targetChar)
    local targetEntity = targetPlayer or targetChar

	-- Pega informações da arma do atacante
	local weapon = nil
	for _, child in pairs(player.Character:GetChildren()) do
		if child:IsA("Model") and child:FindFirstChild("Hitbox") then
			weapon = child
			break
		end
	end

	if not weapon then return end

	local weaponName = string.gsub(weapon.Name, "Equipped_", "")
	local itemInfo = ItemData.Get(weaponName)
	if not itemInfo then return end

    -- Obtém Handlers do Alvo (Registry Lookup)
    local defHandler = DefenseHandler.Registry[targetEntity]
    local posHandler = PostureHandler.Registry[targetEntity]

	-- Verifica Parry
	if defHandler and defHandler:IsParrying() then
        local defenderName = targetPlayer and targetPlayer.Name or targetChar.Name
		print("⚔️ PARRY BEM-SUCEDIDO!", defenderName, "contra-atacou!")

        -- Chama OnParrySuccess no defensor, passando o atacante (Player ou Character?)
        -- O método espera 'attacker' para aplicar stun. Passemos o Player atacante.
		local parryDamage = defHandler:OnParrySuccess(player)
		
        if parryDamage > 0 and player.Character then
			local attackerHumanoid = player.Character:FindFirstChild("Humanoid")
			if attackerHumanoid then
				attackerHumanoid:TakeDamage(parryDamage)
				print("💥 Dano de parry:", parryDamage)
			end
		end
		return
	end

	-- Verifica Block
    if defHandler and defHandler:IsBlocking() then
        local defenderName = targetPlayer and targetPlayer.Name or targetChar.Name
		print("🛡️ BLOQUEADO!", defenderName, "bloqueou o ataque")

		-- === DANO DE POSTURA ===
		local attackerWeaponName = itemInfo.Name
		local defenderWeapon = nil
		
		for _, child in pairs(targetChar:GetChildren()) do
			if child:IsA("Model") and child.Name:match("Equipped_") then
				local wName = child.Name:gsub("Equipped_", "")
				defenderWeapon = ItemData.Get(wName)
				break
			end
		end
		
		if defenderWeapon and defenderWeapon.WeaponCategory then
			local attackerCategory = ItemData.GetCategory(itemInfo.WeaponCategory)
			local defenderCategory = ItemData.GetCategory(defenderWeapon.WeaponCategory)
			
			if attackerCategory and attackerCategory.Stats and defenderCategory and defenderCategory.Stats then
				local postureDmg = attackerCategory.Stats.PostureDamage - defenderCategory.Stats.PostureNegate
				postureDmg = math.max(postureDmg, 5) 
				
                if posHandler then
				    posHandler:Damage(postureDmg)
                    print("⚖️ Dano de postura:", postureDmg)
                end
			end
		end

		if itemInfo.WeaponCategory then
			local blockSoundId = ItemData.GetCategorySound(itemInfo.WeaponCategory, "Block")
			if blockSoundId then
				local blockSound = Instance.new("Sound")
				blockSound.SoundId = blockSoundId
				blockSound.Volume = 0.7
				blockSound.Parent = targetChar:FindFirstChild("HumanoidRootPart") or targetChar.PrimaryPart
				blockSound:Play()
				Debris:AddItem(blockSound, 2)
			end
		end

		local DefenseEvent = Remotes:FindFirstChild("DefenseAction")
		if DefenseEvent and targetPlayer then
			DefenseEvent:FireClient(targetPlayer, "BlockSuccess")
		end

		return
	end

	-- === DANO DE POSTURA (se alvo está atacando e tomando hit) ===
    -- Verifica se o alvo está atacando (simulado via GetAttribute ou AnimationTrack check futuro)
    -- Por simplicidade mantemos GetAttribute("IsAttacking") que o sistema de combat setaria.
    local isTargetAttacking = targetChar:GetAttribute("IsAttacking")
    
    if isTargetAttacking and itemInfo.WeaponCategory then
        local attackerCategory = ItemData.GetCategory(itemInfo.WeaponCategory)
        if attackerCategory and attackerCategory.Stats then
            local postureDmg = math.floor(attackerCategory.Stats.PostureDamage * 0.5)
            postureDmg = math.max(postureDmg, 3) 
            
            if posHandler then
                posHandler:Damage(postureDmg)
                print("⚖️ Postura drenada (hit durante ataque):", postureDmg)
            end
        end
    end

	-- Aplica dano normal
	local damage = itemInfo.Damage or 10
	targetHumanoid:TakeDamage(damage)
	print("💥 Dano aplicado:", damage, "em", targetChar.Name)

	-- VFX de Sangue
	if VFXEvent then
		VFXEvent:FireAllClients("Sangue", hitPosition, Vector3.new(0,1,0))
	end

	if itemInfo.WeaponCategory then
		local hitSoundId = ItemData.GetCategorySound(itemInfo.WeaponCategory, "Hit")
		if hitSoundId then
			local hitSound = Instance.new("Sound")
			hitSound.SoundId = hitSoundId
			hitSound.Volume = 0.6
			hitSound.Parent = targetChar:FindFirstChild("HumanoidRootPart") or targetChar.PrimaryPart
			hitSound:Play()
			Debris:AddItem(hitSound, 2)
		end
	end
end

-- === EVENTOS ===

CombatRemote.OnServerEvent:Connect(function(player, action, ...)
	if action == "RegisterHit" then
		local targetChar, hitPosition = ...

		if not targetChar or not hitPosition then return end

		local isValid, reason = ValidateHit(player, targetChar, hitPosition)
		if not isValid then return end

		ApplyDamage(player, targetChar, hitPosition)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	PlayerAttackCooldowns[player] = nil
	PlayerHitCooldowns[player] = nil
end)

print("✅ CombatHandler Iniciado e Atualizado (Classes)")
