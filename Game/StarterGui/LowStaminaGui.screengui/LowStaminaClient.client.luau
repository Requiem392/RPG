--[[
	LowStaminaClient.client.luau
	
	Gerencia o feedback visual de stamina baixa (Vinheta).
	Escuta apenas o atributo "LowStamina" no Humanoid.
	Otween é criado uma única vez e reutilizado.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local Character = Player.Character or Player.CharacterAdded:Wait()
local Humanoid = Character:WaitForChild("Humanoid")

-- UI References
local Gui = script.Parent
local Vignette = Gui:WaitForChild("Vignette")

-- Configuração da Animação
local TWEEN_INFO = TweenInfo.new(
	1.0, -- Tempo (respiração lenta)
	Enum.EasingStyle.Sine,
	Enum.EasingDirection.InOut,
	-1, -- Loop infinito
	true -- Reverses (Yoyo)
)

-- Cria o Tween uma única vez
local vignetteTween = TweenService:Create(Vignette, TWEEN_INFO, {
	Size = UDim2.fromScale(1.8, 1.8)
})

-- ============================================================================
-- LÓGICA
-- ============================================================================

local function UpdateFeedback()
	local isLowStamina = Humanoid:GetAttribute("LowStamina") == true

	if isLowStamina then
		-- Ativa efeito
		Vignette.Visible = true
		Vignette.ImageTransparency = 0
		vignetteTween:Play()
	else
		-- Desativa efeito com transição suave
		vignetteTween:Cancel()
		
		-- Tween de saída (Fade Out + Return to Size)
		local exitTween = TweenService:Create(Vignette, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			Size = UDim2.fromScale(1.0, 1.0),
			ImageTransparency = 1
		})
		exitTween:Play()
		
		-- Opcional: Garantir que Visible = false após terminar, mas Transparency 1 já resolve visualmente.
		-- Se quiser performance máxima, conectar no Completed, mas criar conexão nova toda vez pode sujar.
		-- Como o script é simples, deixar visível mas transparente é aceitável para o GUI.
	end
end

-- ============================================================================
-- LISTENERS
-- ============================================================================

-- Escuta mudança de atributo ESPECÍFICO no Humanoid
Humanoid:GetAttributeChangedSignal("LowStamina"):Connect(UpdateFeedback)

-- Garante estado inicial correto
UpdateFeedback()

-- Tratamento se o personagem renascer (resetar referências)
Player.CharacterAdded:Connect(function(newCharacter)
	Character = newCharacter
	Humanoid = newCharacter:WaitForChild("Humanoid")
	
	-- Reconecta listener
	Humanoid:GetAttributeChangedSignal("LowStamina"):Connect(UpdateFeedback)
	
	-- Reseta visual
	vignetteTween:Cancel()
	Vignette.Size = UDim2.fromScale(1.0, 1.0)
	Vignette.ImageTransparency = 1
	Vignette.Visible = false
end)
