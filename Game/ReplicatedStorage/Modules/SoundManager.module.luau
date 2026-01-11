local SoundManager = {}

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

-- Cache de sons reutilizáveis (Persistent)
local PersistentSounds = {}

--[[
	PlaySound
	Toca um som no parent especificado.
	
	Params:
		soundId (string): Asset ID do som (ex: "rbxassetid://...")
		parent (Instance): Onde o som será parentado (ex: HumanoidRootPart)
		volume (number): Volume do som (default: 0.5)
		isPersistent (boolean): Se true, reutiliza a instância e permite controle posterior (Loop, Stop).
								Se false (default), cria clone one-shot e destrói.
		customName (string): Nome opcional para o som (obrigatório se isPersistent = true)
	
	Returns:
		Sound (Instance) ou nil
]]
function SoundManager.PlaySound(soundId, parent, volume, isPersistent, customName)
	if not soundId or not parent then return nil end
	
	if isPersistent then
		-- Modo Persistente (ex: Breathing, Equip Loop)
		if not customName then
			warn("[SoundManager] Sons persistentes precisam de um customName!")
			return nil
		end
		
		-- Verifica se já existe no cache ou no parent
		local existingSound = parent:FindFirstChild(customName)
		if existingSound then
			existingSound.Volume = volume or 0.5
			if not existingSound.IsPlaying then
				existingSound:Play()
			end
			return existingSound
		end
		
		-- Cria novo persistente
		local sound = Instance.new("Sound")
		sound.Name = customName
		sound.SoundId = soundId
		sound.Volume = volume or 0.5
		sound.Parent = parent
		sound.Looped = true -- Persistente geralmente é loop, ou controlado manualmente
		sound:Play()
		return sound
		
	else
		-- Modo One-Shot (ex: Hit, Swing) -> Fire and Forget
		local sound = Instance.new("Sound")
		sound.Name = "SFX_" .. (customName or "OneShot")
		sound.SoundId = soundId
		sound.Volume = volume or 0.5
		sound.Parent = parent
		sound:Play()
		
		-- Cleanup automático
		local duration = 2 -- Fallback seguro
		if sound.TimeLength > 0 then
			duration = sound.TimeLength + 0.5
		end
		
		-- Se o asset não carregou instant, TimeLength pode ser 0.
		-- Debris remove depois de um tempo fixo seguro.
		Debris:AddItem(sound, math.max(duration, 2.0))
		
		return sound
	end
end

-- StopSound (Apenas para persistentes)
function SoundManager.StopSound(parent, soundName, fadeTime)
	local sound = parent:FindFirstChild(soundName)
	if sound and sound:IsA("Sound") then
		if fadeTime and fadeTime > 0 then
			local tween = TweenService:Create(sound, TweenInfo.new(fadeTime), {Volume = 0})
			tween:Play()
			local conn
			conn = tween.Completed:Connect(function()
				sound:Stop()
				if conn then conn:Disconnect() end
			end)
		else
			sound:Stop()
		end
	end
end

-- DestroySound (Remove persistente)
function SoundManager.DestroySound(parent, soundName, fadeTime)
	local sound = parent:FindFirstChild(soundName)
	if sound and sound:IsA("Sound") then
		if fadeTime and fadeTime > 0 then
			local tween = TweenService:Create(sound, TweenInfo.new(fadeTime), {Volume = 0})
			tween:Play()
			Debris:AddItem(sound, fadeTime + 0.1)
		else
			sound:Destroy()
		end
	end
end

return SoundManager
