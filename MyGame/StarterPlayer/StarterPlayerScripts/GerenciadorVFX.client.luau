local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local eventoVFX = ReplicatedStorage:WaitForChild("EventoVFX")
local pastaAssets = ReplicatedStorage:WaitForChild("AssetsVFX")

local hitPrefab = pastaAssets:WaitForChild("Hitblood")
local floorPrefab = pastaAssets:WaitForChild("BloodFloor")

local function RaycastPerfurador(origem, direcao)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignoreList = {}

	while true do
		params.FilterDescendantsInstances = ignoreList
		local resultado = workspace:Raycast(origem, direcao, params)
		if not resultado then return nil end

		local hitPart = resultado.Instance
		local hitModel = hitPart.Parent
		local ehHumano = hitModel:FindFirstChild("Humanoid") or hitModel.Parent:FindFirstChild("Humanoid")
		local ehVFX = hitPart.Name == "Hitblood" or hitPart.Name == "BloodFloor" or hitPart.Transparency == 1
		local semColisao = (hitPart.CanCollide == false)

		if ehHumano or ehVFX or semColisao then
			table.insert(ignoreList, hitPart)
		else
			return resultado
		end
	end
end

local function tocarEfeito(nomeEfeito, posicaoHit, normalHit)
	if nomeEfeito == "Sangue" then

		-- REMOVI A PARTE DO SOM DAQUI PRA NÃO DAR ECO!
		-- AGORA O SOM TOCA LÁ NO CLIENTE INSTANTANEAMENTE.

		-- 1. EFEITO DE IMPACTO
		local vfxHit = hitPrefab:Clone()
		vfxHit.Parent = workspace

		local direcaoOlhar = normalHit or Vector3.new(0, 1, 0)
		if direcaoOlhar.Magnitude < 0.001 then direcaoOlhar = Vector3.new(0, 1, 0) end
		vfxHit.CFrame = CFrame.lookAt(posicaoHit, posicaoHit + direcaoOlhar)

		local attach = vfxHit:FindFirstChildWhichIsA("Attachment")
		if attach then
			local bolinha = attach:FindFirstChild("Bolinha")
			local shards = attach:FindFirstChild("Shards")
			if bolinha then bolinha:Emit(50) end
			if shards then shards:Emit(50) end
		end
		Debris:AddItem(vfxHit, 2)

		-- 2. EFEITO DE CHÃO
		task.delay(0.5, function()
			local raioChao = RaycastPerfurador(posicaoHit, Vector3.new(0, -15, 0))

			if raioChao then
				local vfxFloor = floorPrefab:Clone()
				vfxFloor.Parent = workspace
				vfxFloor.Transparency = 1 
				vfxFloor.Anchored = true 
				vfxFloor.CanCollide = false

				local posicaoSegura = raioChao.Position + (raioChao.Normal * 0.05)
				local cfAlinhado = CFrame.lookAt(posicaoSegura, posicaoSegura + raioChao.Normal)
				vfxFloor.CFrame = cfAlinhado * CFrame.Angles(math.rad(90), 0, 0) 

				local floorEmitter = vfxFloor:FindFirstChild("Floor")
				if floorEmitter then
					floorEmitter:Emit(5) 
				end
				Debris:AddItem(vfxFloor, 10)
			end
		end)
	end
end

eventoVFX.OnClientEvent:Connect(tocarEfeito)