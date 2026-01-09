local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Player = Players.LocalPlayer
local Character = Player.Character or Player.CharacterAdded:Wait()
local Humanoid = Character:WaitForChild("Humanoid")
local RootPart = Character:WaitForChild("HumanoidRootPart")
local Animator = Humanoid:WaitForChild("Animator")

-- Remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local CombatRemote = Remotes:WaitForChild("CombatAction")
local CombatStateRemote = Remotes:WaitForChild("CombatState")

-- Módulos
local RaycastHitbox = require(ReplicatedStorage:WaitForChild("RaycastHitboxV4"))
local DataFolder = ReplicatedStorage:WaitForChild("Data")
local ItemData = require(DataFolder:WaitForChild("ItemData"))
local TrailManager = require(ReplicatedStorage:WaitForChild("TrailManager"))
local ResourceManager = require(ReplicatedStorage:WaitForChild("ResourceManager"))
local DefenseManager = require(ReplicatedStorage:WaitForChild("DefenseManager"))

-- Resource Remotes
local ResourceRequest = Remotes:WaitForChild("ResourceRequest")

-- Defense Remotes
local DefenseEvent = Remotes:WaitForChild("DefenseAction")
local DefenseRequest = Remotes:WaitForChild("DefenseRequest")

-- Configurações
local DASH_FORCE = 20
local DASH_RANGE = 6 -- Distancia pra checar inimigo
local DASH_WIDTH = 3 -- Largura do leque de detecção

-- Estado de Combate
local LastSwingSide = "Right" -- Começa com Right para próximo ataque ser Left
local IsAttacking = false
local LoadedAnims = {}
local CurrentWeaponCategory = nil
local SoundCache = {}
local IdleTrack = nil -- Track da animação Idle
local PlayerHitbox = nil -- Hitbox local do cliente
local HitCooldowns = {} -- Anti-spam: {[target] = lastHitTime}

-- Estado Defensivo
local IsBlocking = false
local IsParrying = false
local IsStunned = false
local BlockDrainConnection = nil

-- Variáveis para lock de movimento no stun
local OriginalWalkSpeed = 16
local OriginalJumpPower = 50
local StunExpirationTime = 0

-- Estado de Feint
local AttackStartTime = 0
local CanFeint = false
local LastFeintTime = 0

local FEINT_CONFIG = {
	Window = 0.6,     -- Janela para feint (segundos) - AUMENTADA
	Cost = 5,         -- Custo de energia
	Cooldown = 1.0,   -- Cooldown entre feints
	AnimSpeed = 0.5   -- Velocidade das animações (70% = mais lento)
}

-- === FUNÇÕES AUXILIARES ===

-- Carrega animações baseadas na categoria da arma equipada
local function LoadAnimations(weaponCategory, weaponItemInfo)
	if not weaponCategory then return end

	-- Limpa animações antigas
	for _, track in pairs(LoadedAnims) do
		if track then
			track:Stop()
			track:Destroy()
		end
	end
	LoadedAnims = {}

	-- Para e limpa idle track anterior
	if IdleTrack then
		IdleTrack:Stop()
		IdleTrack:Destroy()
		IdleTrack = nil
	end

	-- Carrega novas animações da categoria
	local categoryData = ItemData.GetCategory(weaponCategory)
	if not categoryData then 
		warn("[CombatController] Categoria não encontrada:", weaponCategory)
		return 
	end

	-- === SISTEMA DE MERGE DE ANIMAÇÕES ===
	-- 1. Começa com animações da categoria (base)
	-- 2. Sobrescreve com animações específicas da arma (se existirem)

	local finalAnimations = {}

	-- Copia animações da categoria
	for name, id in pairs(categoryData.Animations) do
		if id then
			finalAnimations[name] = id
		end
	end

	-- Sobrescreve com animações específicas da arma (se existir)
	if weaponItemInfo and weaponItemInfo.Animations then
		for name, id in pairs(weaponItemInfo.Animations) do
			if id then -- Só sobrescreve se não for nil
				finalAnimations[name] = id
				print("✨ [Override] Usando animação customizada:", name, "da arma", weaponItemInfo.Name)
			end
		end
	end

	-- Carrega animações finais (já com overrides aplicados)
	for name, id in pairs(finalAnimations) do
		local anim = Instance.new("Animation")
		anim.AnimationId = id
		local track = Animator:LoadAnimation(anim)

		-- Configura prioridades
		if name == "Idle" then
			track.Priority = Enum.AnimationPriority.Action -- Idle elevada
			IdleTrack = track
		else
			track.Priority = Enum.AnimationPriority.Action2 -- Ataques precisam ser maior que Idle
		end

		LoadedAnims[name] = track
	end

	CurrentWeaponCategory = weaponCategory
	print("⚔️ Animações carregadas para categoria:", weaponCategory)
end

-- Carrega sons da categoria
local function LoadSounds(weaponCategory)
	SoundCache = {}

	if not weaponCategory then return end

	local categoryData = ItemData.GetCategory(weaponCategory)
	if not categoryData or not categoryData.Sounds then return end

	for soundName, soundId in pairs(categoryData.Sounds) do
		local sound = Instance.new("Sound")
		sound.SoundId = soundId
		sound.Volume = 0.5
		sound.Parent = RootPart
		SoundCache[soundName] = sound
	end
end

-- Toca um som
local function PlaySound(soundName)
	local sound = SoundCache[soundName]
	if sound then
		sound:Play()
	end
end

-- === SISTEMA DE HITBOX CLIENT-SIDE ===

-- Configura hitbox local
local function SetupLocalHitbox(weapon)
	if PlayerHitbox then
		-- Verifica se é um objeto válido com método Destroy
		if type(PlayerHitbox) == "table" and PlayerHitbox.Destroy then
			pcall(function() PlayerHitbox:Destroy() end)
		end
		PlayerHitbox = nil
	end

	if not weapon then return end

	print("⚔️ [CombatController] Configurando Hitbox local")

	-- Cria hitbox local
	local hitbox = RaycastHitbox.new(weapon)
	hitbox.RaycastParams = RaycastParams.new()
	hitbox.RaycastParams.FilterDescendantsInstances = {Character}
	hitbox.RaycastParams.FilterType = Enum.RaycastFilterType.Exclude

	-- Callback quando acerta algo
	hitbox.OnHit:Connect(function(hit, humanoid)
		if not humanoid or humanoid.Health <= 0 then return end

		local targetChar = humanoid.Parent
		local now = tick()

		-- Anti-spam: cooldown de 0.1s por alvo
		if HitCooldowns[targetChar] and (now - HitCooldowns[targetChar]) < 0.1 then
			return
		end
		HitCooldowns[targetChar] = now

		print("🎯 [CombatController] Hit detectado:", targetChar.Name)

		-- Envia para servidor validar e aplicar dano
		CombatRemote:FireServer("RegisterHit", targetChar, hit.Position)
	end)

	PlayerHitbox = hitbox
end

-- Limpa hitbox local
local function CleanupLocalHitbox()
	if PlayerHitbox then
		-- Verifica se é um objeto válido com método Destroy
		if type(PlayerHitbox) == "table" and PlayerHitbox.Destroy then
			pcall(function() PlayerHitbox:Destroy() end)
			print("🗑️ [CombatController] Hitbox local removida")
		end
		PlayerHitbox = nil
	end
	HitCooldowns = {}
end

local function SmartDash()
	-- "Linhas Inteligentes" (Lógica portada do AnimaCombate)
	local origin = RootPart.CFrame
	local foundEnemy = false

	-- Visual Folder
	local visualFolder = workspace:FindFirstChild("VisualCombate") or Instance.new("Folder", workspace)
	visualFolder.Name = "VisualCombate"

	-- Parâmetros do Raycast
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = {Character, visualFolder}
	params.FilterType = Enum.RaycastFilterType.Exclude

	-- Leque de 5 linhas
	for i = 0, 4 do
		local offset = -DASH_WIDTH/2 + (DASH_WIDTH/4 * i)
		local startPosCFrame = origin * CFrame.new(offset, 0, 0)
		local startPos = startPosCFrame.Position
		local direction = origin.LookVector * DASH_RANGE

		local result = workspace:Raycast(startPos, direction, params)
		local dist = DASH_RANGE
		local color = Color3.fromRGB(255, 0, 0) -- Vermelho (Livre)

		if result then
			dist = result.Distance
			if result.Instance.Parent:FindFirstChild("Humanoid") then
				foundEnemy = true
				color = Color3.fromRGB(0, 255, 0) -- Verde (Inimigo)
			end
		end

		-- DEBUG VISUAL
		local line = Instance.new("Part")
		line.Size = Vector3.new(0.05, 0.05, dist)
		line.CFrame = CFrame.lookAt(startPos, startPos + direction) * CFrame.new(0, 0, -dist/2)
		line.Anchored = true
		line.CanCollide = false
		line.Material = Enum.Material.Neon
		line.Color = color
		line.Transparency = 0.5
		line.Parent = visualFolder
		Debris:AddItem(line, 0.5)
	end

	if not foundEnemy then
		local bv = Instance.new("BodyVelocity")
		bv.Velocity = RootPart.CFrame.LookVector * DASH_FORCE
		bv.MaxForce = Vector3.new(100000, 0, 100000)
		bv.Parent = RootPart
		Debris:AddItem(bv, 0.2)
	end
end

local function GetEquippedWeapon()
	-- Procura por um modelo de arma no personagem
	for _, child in pairs(Character:GetChildren()) do
		if child:IsA("Model") and child:FindFirstChild("Hitbox") then
			return child
		end
	end
	return nil
end

-- Obtém informações da arma equipada
local function GetWeaponInfo()
	local weapon = GetEquippedWeapon()
	if not weapon then return nil, nil end

	local weaponName = string.gsub(weapon.Name, "Equipped_", "")
	local itemInfo = ItemData.Get(weaponName)

	return weapon, itemInfo
end

-- === SISTEMA DEFENSIVO ===

-- Inicia bloqueio
local function StartBlock()
	-- Não pode bloquear durante ataque
	if IsAttacking then
		print("⚠️ Não pode bloquear durante ataque!")
		return
	end

	-- Verifica se está stunned
	local stunned = DefenseRequest:InvokeServer("IsStunned")
	if stunned then 
		print("⚠️ Não pode bloquear enquanto stunned!")
		return 
	end

	if IsBlocking then return end

	-- Verifica energia mínima
	local currentStamina = ResourceRequest:InvokeServer("GetStamina")
	if currentStamina < 5 then
		print("⚠️ Sem energia para bloquear!")
		return
	end

	IsBlocking = true
	CombatStateRemote:FireServer("Blocking", true) -- Notifica servidor
	DefenseEvent:FireServer("StartBlock")

	-- Toca animação de bloqueio
	local blockTrack = LoadedAnims["Block"]
	if blockTrack then
		blockTrack.Looped = true
		blockTrack:Play(0.1) -- Fade in 0.1s
		print("🛡️ Bloqueio ativado")
	else
		print("🛡️ Bloqueio ativado (sem animação)")
	end
end

-- Para bloqueio
local function StopBlock()
	if not IsBlocking then return end

	IsBlocking = false
	CombatStateRemote:FireServer("Blocking", false) -- Notifica servidor
	DefenseEvent:FireServer("StopBlock")

	-- Para animação de bloqueio
	local blockTrack = LoadedAnims["Block"]
	if blockTrack and blockTrack.IsPlaying then
		blockTrack:Stop(0.1) -- Fade out 0.1s
	end

	print("🛡️ Bloqueio desativado")

	-- TODO: Sair da animação de block
end

-- Tenta parry
local function AttemptParry()
	-- Não pode parry durante ataque
	if IsAttacking then
		print("⚠️ Não pode parry durante ataque!")
		return
	end

	-- Previne spam de parry
	if IsParrying then
		print("⚠️ Parry já está ativo!")
		return
	end

	-- Verifica se está stunned
	local stunned = DefenseRequest:InvokeServer("IsStunned")
	if stunned then 
		print("⚠️ Não pode parry enquanto stunned!")
		return 
	end

	-- Verifica se pode parry (cooldown, etc)
	local canParry = DefenseRequest:InvokeServer("CanParry")
	if not canParry then
		print("⚠️ Parry em cooldown!")
		return
	end

	-- Verifica energia
	local config = DefenseManager.GetConfig()
	local hasEnergy = ResourceRequest:InvokeServer("UseStamina", config.Parry.Cost)

	if not hasEnergy then
		print("⚠️ Sem energia para parry!")
		return
	end

	-- Ativa parry
	IsParrying = true
	DefenseEvent:FireServer("StartParry")

	-- Toca animação de parry
	local parryTrack = LoadedAnims["Parry"]
	if parryTrack then
		parryTrack:Play(0.05) -- Fade in rápido
		-- Para animação automaticamente após a janela de parry
		task.delay(config.Parry.Window, function()
			if parryTrack.IsPlaying then
				parryTrack:Stop(0.1)
			end
			IsParrying = false -- Libera para novo parry
		end)
		print("⚔️ Parry ativado! Janela de", config.Parry.Window, "segundos")
	else
		IsParrying = false
		print("⚔️ Parry ativado! Janela de", config.Parry.Window, "segundos")
	end
end

-- === SISTEMA DE ATAQUE ===

local function Attack()
	local weapon, itemInfo = GetWeaponInfo()
	if not weapon or IsAttacking or IsBlocking then return end

	-- MARCA COMO ATACANDO IMEDIATAMENTE (antes de qualquer coisa)
	IsAttacking = true
	Character:SetAttribute("IsAttacking", true) -- Para PostureHandler detectar
	CombatStateRemote:FireServer("Attacking", true)

	-- Verifica se está stunned
	local stunned = DefenseRequest:InvokeServer("IsStunned")
	if stunned then 
		print("⚠️ Não pode atacar enquanto stunned!")
		IsAttacking = false -- Reseta se não pode atacar
		CombatStateRemote:FireServer("Attacking", false)
		return 
	end

	-- Pega dados da categoria
	local categoryData = ItemData.GetCategory(itemInfo.WeaponCategory)
	if not categoryData then 
		IsAttacking = false
		CombatStateRemote:FireServer("Attacking", false)
		return 
	end

	-- >>> VERIFICA E GASTA ENERGIA <<<
	local config = ResourceManager.GetConfig()
	local energyCost = config.Stamina.AttackCost

	-- Verifica com o servidor se tem energia (validação autoritativa)
	local hasEnergy = ResourceRequest:InvokeServer("UseStamina", energyCost)

	if not hasEnergy then
		-- Sem energia, não ataca
		print("⚠️ Sem energia para atacar!")
		IsAttacking = false
		CombatStateRemote:FireServer("Attacking", false)
		return
	end

	-- === ATIVA JANELA DE FEINT ===
	AttackStartTime = tick()
	CanFeint = true

	-- Desativa feint após janela
	task.delay(FEINT_CONFIG.Window, function()
		CanFeint = false
	end)

	-- === ALTERNÂNCIA DE LADOS ===
	-- Alterna entre SwingLeft e SwingRight independente do tempo
	local animName = LastSwingSide == "Right" and "SwingLeft" or "SwingRight"
	LastSwingSide = LastSwingSide == "Right" and "Left" or "Right"

	-- Motor6D: Usa apenas RightArmMotor para ambos os swings (simplificado)
	-- As novas animações vão usar o mesmo motor mas com cortes diferentes

	local track = LoadedAnims[animName]

	if track then
		-- >>> ATIVA TRAIL <<<
		if itemInfo.TrailEnabled then
			TrailManager.ActivateTrailForDuration(weapon, categoryData.TrailDuration or 0.3)
		end

		-- Toca animação com velocidade normal
		track:Play()

		-- Conecta ao evento Start para iniciar hitbox LOCAL e dash
		local startConnection
		startConnection = track:GetMarkerReachedSignal("Start"):Connect(function()
			print("🗡️ Hitbox ATIVADA (evento Start)")

			-- Som de swing (sincronizado)
			PlaySound("Swing")

			-- Dash inteligente (sincronizado com hitbox)
			SmartDash()

			if PlayerHitbox and PlayerHitbox.HitStart then
				PlayerHitbox:HitStart()
			end
			startConnection:Disconnect()
		end)

		-- Conecta ao evento End para parar hitbox
		local endConnection
		endConnection = track:GetMarkerReachedSignal("End"):Connect(function()
			print("🛡️ Hitbox DESATIVADA (evento End)")
			-- Para hitbox LOCAL
			if PlayerHitbox and PlayerHitbox.HitStop then
				PlayerHitbox:HitStop()
			end
			endConnection:Disconnect()
		end)


		-- Fallback: se a animação terminar sem disparar o evento End
		track.Stopped:Connect(function()
			if IsAttacking then
				print("⚠️ Animação parou sem evento End, resetando...")
				if PlayerHitbox and PlayerHitbox.HitStop then
					PlayerHitbox:HitStop()
				end

				-- (RightArmMotor já deve estar ativo)

				if IdleTrack and not IdleTrack.IsPlaying then
					IdleTrack:Play(0.5)
				end
				IsAttacking = false
				Character:SetAttribute("IsAttacking", false) -- Reset para PostureHandler
				CombatStateRemote:FireServer("Attacking", false)
			end
		end)
	end
end

-- ============================================================================
-- SISTEMA DE FEINT
-- ============================================================================

-- Verifica se está na janela de feint
local function InFeintWindow()
	if not IsAttacking then return false end
	if not CanFeint then return false end

	local elapsed = tick() - AttackStartTime
	return elapsed <= FEINT_CONFIG.Window
end

-- Executa feint (cancela ataque)
function ExecuteFeint()
	-- Verifica cooldown
	local now = tick()
	if now - LastFeintTime < FEINT_CONFIG.Cooldown then
		print("⚠️ Feint em cooldown!")
		return false
	end

	-- Verifica janela
	if not InFeintWindow() then
		print("⚠️ Fora da janela de feint! (primeiros 0.6s)")
		return false
	end

	-- Verifica energia
	local hasEnergy = ResourceRequest:InvokeServer("UseStamina", FEINT_CONFIG.Cost)
	if not hasEnergy then
		print("⚠️ Sem energia para feint!")
		return false
	end

	print("✨ FEINT! Ataque cancelado")

	-- Para animação atual
	for _, track in pairs(LoadedAnims) do
		if track.IsPlaying and track ~= IdleTrack then
			track:Stop()
		end
	end

	-- Para hitbox se estava ativa
	if PlayerHitbox then
		PlayerHitbox:HitStop()
	end

	-- (RightArmMotor já deve estar ativo)
	print("🔄 Feint: RightArmMotor mantido")

	-- Toca animação Idle customizada
	if IdleTrack and not IdleTrack.IsPlaying then
		IdleTrack:Play()
		print("🎭 Feint: Voltou para Idle customizada")
	end

	-- Reseta estados
	IsAttacking = false
	CanFeint = false
	LastFeintTime = now
	CombatStateRemote:FireServer("Attacking", false) -- Notifica servidor

	-- Notifica servidor
	CombatRemote:FireServer("Feint")

	return true
end

-- Input
local ToggleRemote = Remotes:WaitForChild("ToggleCombat")
local IsCombatMode = false
local ToggleDebounce = false

-- Atualiza categoria quando trocar de arma
local function UpdateWeaponCategory()
	local weapon, itemInfo = GetWeaponInfo()
	if itemInfo and itemInfo.WeaponCategory then
		if itemInfo.WeaponCategory ~= CurrentWeaponCategory then
			LoadAnimations(itemInfo.WeaponCategory, itemInfo) -- Passa itemInfo para merge
			LoadSounds(itemInfo.WeaponCategory)
		end
		-- Setup hitbox local
		SetupLocalHitbox(weapon)
	end
end

local function GetWeaponName()
	-- Tenta achar arma na mão ou costas
	for _, child in pairs(Character:GetChildren()) do
		if child:IsA("Model") and (child:FindFirstChild("Hitbox") or child.Name:find("Equipped_")) then
			return string.gsub(child.Name, "Equipped_", "")
		end
	end
	return nil
end

local function GetAnimLength(animId)
	if not animId then return 0.5 end 
	-- Carrega rapidinho só pra ler o tamanho, se não tiver cahced
	local anim = Instance.new("Animation")
	anim.AnimationId = animId
	local track = Animator:LoadAnimation(anim)
	local length = track.Length
	-- track:Destroy() -- Opcional, mas tracks se limpam
	if length == 0 then return 1 else return length end
end

UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end

	-- [T] Sacar / Guardar Arma
	if input.KeyCode == Enum.KeyCode.T then
		if ToggleDebounce then return end

		-- Bloqueia toggle durante ataque ou bloqueio
		if IsAttacking then
			print("⚠️ Não pode equipar/desequipar enquanto ataca!")
			return
		end

		-- Verificação adicional: checa se animações de ataque estão tocando
		if LoadedAnims["SwingLeft"] and LoadedAnims["SwingLeft"].IsPlaying then
			print("⚠️ Aguarde o ataque terminar!")
			return
		end

		if LoadedAnims["SwingRight"] and LoadedAnims["SwingRight"].IsPlaying then
			print("⚠️ Aguarde o ataque terminar!")
			return
		end

		if IsBlocking then
			print("⚠️ Não pode equipar/desequipar enquanto bloqueia!")
			return
		end

		local weaponName = GetWeaponName()
		if not weaponName then return end

		local itemInfo = ItemData.Get(weaponName)
		if not itemInfo then return end

		-- Busca animação de Equip/Unequip (pode vir da categoria)
		local targetAnimId
		if IsCombatMode then
			-- Desequipar: busca Unequip
			if itemInfo.Animations and itemInfo.Animations.Unequip then
				targetAnimId = itemInfo.Animations.Unequip
			else
				local categoryData = ItemData.GetCategory(itemInfo.WeaponCategory)
				if categoryData and categoryData.Animations then
					targetAnimId = categoryData.Animations.Unequip
				end
			end
		else
			-- Equipar: busca Equip
			if itemInfo.Animations and itemInfo.Animations.Equip then
				targetAnimId = itemInfo.Animations.Equip
			else
				local categoryData = ItemData.GetCategory(itemInfo.WeaponCategory)
				if categoryData and categoryData.Animations then
					targetAnimId = categoryData.Animations.Equip
				end
			end
		end

		local cooldown = GetAnimLength(targetAnimId)

		ToggleDebounce = true
		local wasCombatMode = IsCombatMode
		IsCombatMode = not IsCombatMode
		ToggleRemote:FireServer()

		-- Carrega animações da categoria quando equipar
		if IsCombatMode then
			UpdateWeaponCategory()

			-- Inicia animação Idle com delay calculado para overlap suave
			-- Começa 0.15s antes da animação de equipar terminar para fazer um crossfade
			local delayTime = math.max(0, cooldown - 0.15)

			task.delay(delayTime, function()
				if IsCombatMode and IdleTrack then
					IdleTrack:Play(0.3) -- Fade de 0.3s para blend suave
					print("⚔️ Modo de Combate! Idle ativa.")
				end
			end)

			print("⚔️ Sacando arma... (CD: " .. string.format("%.2f", cooldown) .. "s)")
		else
			-- Para animação Idle
			if IdleTrack and IdleTrack.IsPlaying then
				IdleTrack:Stop()
			end
			-- Limpa hitbox local
			CleanupLocalHitbox()
			-- Desativa qualquer trail ativo ao desequipar
			local weapon = GetEquippedWeapon()
			if weapon then
				TrailManager.DisableTrail(weapon)
			end
			print("🕊️ Modo Pacífico... (CD: " .. string.format("%.2f", cooldown) .. "s)")
		end

		task.wait(cooldown)
		ToggleDebounce = false
	end

	-- [LMB] Ataque
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if IsCombatMode and not ToggleDebounce then
			Attack()
		end
	end

	-- [RMB] Block (segurar)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		if IsCombatMode then
			StartBlock()
		end
	end

	-- [F] Parry
	if input.KeyCode == Enum.KeyCode.F then
		if IsCombatMode then
			AttemptParry()
		end
	end

	-- [E] Feint (cancelar ataque)
	if input.KeyCode == Enum.KeyCode.E then
		ExecuteFeint()
	end
end)

-- Input Ended (soltar botões)
UserInputService.InputEnded:Connect(function(input, gp)
	if gp then return end

	-- [RMB] Soltar Block
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		StopBlock()
	end
end)

-- Inicialização
Player.CharacterAdded:Connect(function(newChar)
	Character = newChar
	Humanoid = newChar:WaitForChild("Humanoid")
	RootPart = newChar:WaitForChild("HumanoidRootPart")
	Animator = Humanoid:WaitForChild("Animator")

	-- Limpa trails e hitbox do personagem anterior
	TrailManager.CleanupAll()
	CleanupLocalHitbox()
end)

-- Carrega arma inicial se já estiver equipada
task.wait(1) -- Aguarda inventário carregar
UpdateWeaponCategory()

-- Sistema de dreno de energia durante Block
local lastDrainTime = tick()
RunService.Heartbeat:Connect(function()
	if IsBlocking then
		local now = tick()
		local deltaTime = now - lastDrainTime
		lastDrainTime = now

		-- Calcula dreno (5 energia/segundo)
		local config = DefenseManager.GetConfig()
		local drainAmount = config.Block.DrainPerSecond * deltaTime

		-- Verifica se tem energia
		local currentStamina = ResourceRequest:InvokeServer("GetStamina")

		if currentStamina < drainAmount then
			-- Energia acabou, para o block
			StopBlock()
			print("⚠️ Energia esgotada! Bloqueio desativado.")
		else
			-- Drena energia
			ResourceRequest:InvokeServer("UseStamina", drainAmount)
		end
	else
		lastDrainTime = tick()
	end
end)

-- Monitora quando arma é equipada/desequipada
Character.ChildAdded:Connect(function(child)
	if child:IsA("Model") and child:FindFirstChild("Hitbox") then
		print("🔍 [DEBUG] Arma detectada:", child.Name)

		-- Arma equipada, espera um frame para garantir que está configurada
		task.wait(0.1)
		UpdateWeaponCategory()

		-- SINCRONIZA IsCombatMode com estado real
		local handle = child:FindFirstChild("Handle")
		if handle then
			-- Verifica se já tem Motor6D (arma já sacada)
			if handle:FindFirstChild("RightArmMotor") then
				IsCombatMode = true
				print("🔍 [DEBUG] Motor6D JÁ EXISTE → IsCombatMode = TRUE")
			else
				IsCombatMode = false
				print("🔍 [DEBUG] Sem Motor6D → IsCombatMode = FALSE")
			end

			-- Listener para detectar quando Motor6D é criado (DrawWeapon)
			local motorConnection
			motorConnection = handle.ChildAdded:Connect(function(motor)
				if motor.Name == "RightArmMotor" then
					-- Motor6D criado, arma foi sacada
					IsCombatMode = true
					print("🔍 [DEBUG] Motor6D CRIADO → IsCombatMode = TRUE")

					task.delay(0.1, function()
						if IdleTrack and not IdleTrack.IsPlaying then
							IdleTrack:Play(0.3)
						end
					end)
					motorConnection:Disconnect()
				end
			end)

			-- Fallback: verifica se Motor6D foi criado antes do listener
			task.delay(1.5, function()
				if handle.Parent and handle:FindFirstChild("RightArmMotor") then
					if not IsCombatMode then
						IsCombatMode = true
						print("🔍 [DEBUG FALLBACK] Motor6D detectado → IsCombatMode = TRUE")
						if IdleTrack and not IdleTrack.IsPlaying then
							IdleTrack:Play(0.3)
						end
					end
				end
				motorConnection:Disconnect()
			end)
		end
	end
end)

Character.ChildRemoved:Connect(function(child)
	-- Detecta arma removida pelo nome ao invés de Hitbox (pode já ter sido destruído)
	if child:IsA("Model") and child.Name:match("^Equipped_") then
		print("🗑️ [ChildRemoved] Arma removida:", child.Name)

		-- Arma removida, limpa animações
		for _, track in pairs(LoadedAnims) do
			if track then
				track:Stop()
				track:Destroy()
			end
		end
		LoadedAnims = {}

		if IdleTrack then
			IdleTrack:Stop()
			IdleTrack:Destroy()
			IdleTrack = nil
		end

		-- Reseta estado de combate
		if IsCombatMode then
			IsCombatMode = false
		end

		CurrentWeaponCategory = nil
		CleanupLocalHitbox()
	end
end)

-- Verifica se já tem arma equipada ao iniciar
task.wait(0.5)
UpdateWeaponCategory()

-- === LISTENER DE EVENTOS DEFENSIVOS ===

DefenseEvent.OnClientEvent:Connect(function(action, data)
	if action == "StunApplied" then
		-- Toca animação de stun
		local stunAnim = Instance.new("Animation")
		stunAnim.AnimationId = "rbxassetid://91996512144744"
		local stunTrack = Animator:LoadAnimation(stunAnim)
		stunTrack.Priority = Enum.AnimationPriority.Action4 -- Máxima prioridade

		-- TRAVA MOVIMENTO e PULO
		if not IsStunned then
			OriginalWalkSpeed = Humanoid.WalkSpeed
			OriginalJumpHeight = Humanoid.JumpHeight -- Usa JumpHeight agora
			Humanoid.WalkSpeed = 0
			Humanoid.JumpHeight = 0 -- Trava pulo
			Humanoid.JumpPower = 0 -- Garante trava em ambos modos
			IsStunned = true
		end

		-- Atualiza tempo de expiração (para lidar com overlaps de stun)
		local myStunTime = tick() + data.Duration
		StunExpirationTime = math.max(StunExpirationTime, myStunTime)

		stunTrack:Play()
		print("💫 [CombatController] STUNNED por", data.Duration, "segundos! Movimento e pulo travados.")

		-- Para stun após duração
		task.delay(data.Duration, function()
			-- Só restaura se o tempo atual já passou do tempo de expiração do stun (evita bugs com stuns sobrepostos)
			if tick() >= StunExpirationTime - 0.1 then
				if stunTrack.IsPlaying then
					stunTrack:Stop(0.2)
				end

				if IsStunned then
					Humanoid.WalkSpeed = OriginalWalkSpeed
					Humanoid.JumpHeight = OriginalJumpHeight -- Restaura JumpHeight
					Humanoid.JumpPower = 50 -- Valor padrão ou restaurar se tivesse salvo
					IsStunned = false
					print("✅ [CombatController] Stun terminado - Movimento restaurado")
				end
			end
		end)

	elseif action == "ParrySuccess" then
		-- Parry bem-sucedido! Toca som
		PlaySound("Parry")
		print("⚔️ [CombatController] PARRY BEM-SUCEDIDO!")

	elseif action == "BlockSuccess" then
		-- Block bem-sucedido! (Som toca no servidor agora)
		print("🛡️ [CombatController] BLOCK BEM-SUCEDIDO!")
		
	elseif action == "ForceStopBlock" then
		-- Postura quebrou, força parar de bloquear
		if IsBlocking then
			IsBlocking = false
			local blockTrack = LoadedAnims["Block"]
			if blockTrack and blockTrack.IsPlaying then
				blockTrack:Stop(0.1)
			end
			print("💥 [CombatController] Forçado a parar de bloquear (Posture Break)")
		end
	end
end)

print("✅ CombatController Iniciado com Sistema de Categorias ⚔️")
