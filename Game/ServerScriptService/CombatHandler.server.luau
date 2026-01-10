local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Debris = game:GetService("Debris")

-- Módulos
local ItemData = require(game.ReplicatedStorage:WaitForChild("Data"):WaitForChild("ItemData"))
local Modules = ServerScriptService:WaitForChild("Modules")
local DefenseService = require(Modules:WaitForChild("DefenseService"))
local PostureService = require(Modules:WaitForChild("PostureService"))

-- Eventos
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local CombatRemote = Remotes:WaitForChild("CombatAction")
local VFXEvent = Remotes:FindFirstChild("EventoVFX")

-- Estado
local PlayerAttackCooldowns = {} -- Anti-cheat: {[Player] = lastAttackTime}
local PlayerHitCooldowns = {} -- Anti-spam: {[Player] = {[Target] = lastHitTime}}

-- === CONFIGURAÇÃO ANTI-CHEAT ===
local MAX_HIT_DISTANCE = 15 -- Distância máxima para acertar (studs)
local HIT_COOLDOWN = 0.08 -- Cooldown mínimo entre hits no mesmo alvo
local ATTACK_RATE_LIMIT = 0.3 -- Mínimo de tempo entre ataques

-- === FUNÇÕES DE VALIDAÇÃO ===

-- Valida se o hit é legítimo
local function ValidateHit(player, targetChar, hitPosition)
	local character = player.Character
	if not character then return false, "Sem personagem" end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return false, "Sem RootPart" end

	-- Valida distância
	local distance = (rootPart.Position - hitPosition).Magnitude
	if distance > MAX_HIT_DISTANCE then
		warn("⚠️ [CombatHandler] Hit rejeitado - distância:", distance)
		return false, "Muito longe"
	end

	-- Valida cooldown por alvo
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

	-- Identifica o player alvo
	local targetPlayer = game.Players:GetPlayerFromCharacter(targetChar)
	
	-- Verifica Parry
	if targetPlayer and DefenseService.IsPlayerParrying(targetPlayer) then
		print("⚔️ PARRY BEM-SUCEDIDO!", targetPlayer.Name, "contra-atacou!")

		local parryDamage = DefenseService.OnParrySuccess(targetPlayer, player)
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
	if targetPlayer and DefenseService.IsPlayerBlocking(targetPlayer) then
		print("🛡️ BLOQUEADO!", targetPlayer.Name, "bloqueou o ataque")

		-- === DANO DE POSTURA ===
		-- Pega as armas de atacante e defensor
		local attackerWeaponName = itemInfo.Name
		local defenderChar = targetChar
		local defenderWeapon = nil
		
		-- Procura arma equipada do defensor
		for _, child in pairs(defenderChar:GetChildren()) do
			if child:IsA("Model") and child.Name:match("Equipped_") then
				local weaponName = child.Name:gsub("Equipped_", "")
				defenderWeapon = ItemData.Get(weaponName)
				break
			end
		end
		
		if defenderWeapon and defenderWeapon.WeaponCategory then
			-- Pega stats de ambas as categorias
			local attackerCategory = ItemData.GetCategory(itemInfo.WeaponCategory)
			local defenderCategory = ItemData.GetCategory(defenderWeapon.WeaponCategory)
			
			if attackerCategory and attackerCategory.Stats and defenderCategory and defenderCategory.Stats then
				local postureDmg = attackerCategory.Stats.PostureDamage - defenderCategory.Stats.PostureNegate
				postureDmg = math.max(postureDmg, 5) -- Mínimo 5
				
				PostureService.DamagePosture(targetPlayer, postureDmg)
				print("⚖️ Dano de postura:", postureDmg)
			end
		end

		-- Toca som de bloqueio (3D espacial para todos ouvirem)
		if itemInfo.WeaponCategory then
			local blockSoundId = ItemData.GetCategorySound(itemInfo.WeaponCategory, "Block")
			if blockSoundId then
				local blockSound = Instance.new("Sound")
				blockSound.SoundId = blockSoundId
				blockSound.Volume = 0.7
				blockSound.Parent = targetChar:FindFirstChild("HumanoidRootPart") or targetChar.PrimaryPart
				blockSound:Play()
				game:GetService("Debris"):AddItem(blockSound, 2)
			end
		end

		-- Notifica defensor visualmente (opcional - para feedback)
		local Remotes = game.ReplicatedStorage:WaitForChild("Remotes")
		local DefenseEvent = Remotes:FindFirstChild("DefenseAction")
		if DefenseEvent then
			DefenseEvent:FireClient(targetPlayer, "BlockSuccess")
		end

		return
	end

	-- === DANO DE POSTURA (se alvo está atacando) ===
	if targetPlayer then
		local CombatState = Remotes:FindFirstChild("CombatState")
		if CombatState then
			-- Verifica se o alvo está atacando (simulado via GetAttribute)
			local isTargetAttacking = targetChar:GetAttribute("IsAttacking")
			
			if isTargetAttacking and itemInfo.WeaponCategory then
				local attackerCategory = ItemData.GetCategory(itemInfo.WeaponCategory)
				if attackerCategory and attackerCategory.Stats then
					-- Dano de postura reduzido (50% do normal, pois não bloqueou)
					local postureDmg = math.floor(attackerCategory.Stats.PostureDamage * 0.5)
					postureDmg = math.max(postureDmg, 3) -- Mínimo 3
					
					PostureService.DamagePosture(targetPlayer, postureDmg)
					print("⚖️ Postura drenada (hit durante ataque):", postureDmg)
				end
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

	-- Som de Hit
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

-- Recebe hits do cliente
CombatRemote.OnServerEvent:Connect(function(player, action, ...)
	if action == "RegisterHit" then
		local targetChar, hitPosition = ...

		if not targetChar or not hitPosition then return end

		-- Valida o hit
		local isValid, reason = ValidateHit(player, targetChar, hitPosition)
		if not isValid then
			-- Silenciosamente rejeita (anti-cheat)
			return
		end

		-- Aplica dano
		ApplyDamage(player, targetChar, hitPosition)
	end
end)

-- Cleanup
game.Players.PlayerRemoving:Connect(function(player)
	PlayerAttackCooldowns[player] = nil
	PlayerHitCooldowns[player] = nil
end)

print("✅ CombatHandler Iniciado (Client-Side Hitbox)")
