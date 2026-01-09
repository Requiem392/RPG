local player = game.Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()  

local main_frame = script.Parent.HP
local hp_frame = main_frame.HP_FRAME
local orbe = hp_frame.HP_ORB

local vidaMaxima = character.Humanoid.MaxHealth
local vidaAtual = character.Humanoid.Health

local function updateHealth()
    local percentageHP = vidaAtual / vidaMaxima
    -- Inverter a direção do movimento para que a orbe suba com a vida
    local novaPosicaoY = 3.555 + (1 - percentageHP) * 2.45  -- Ajuste o "2.45" para definir a altura máxima de movimentação

    -- Atualiza a posição da orbe no eixo Y
    orbe.CFrame = CFrame.new(orbe.Position.X, novaPosicaoY, orbe.Position.Z)
    
    -- Para o HP_FRAME: mover para baixo conforme a vida aumenta
    -- A parte Y.Scale é deixada como está e o offset Y é ajustado para o movimento desejado
	local novaPosicaoFrameY = 0.303 - (1 - percentageHP) * -0.51  -- Ajuste o "0.1" para definir o movimento do frame
    hp_frame.Position = UDim2.new(hp_frame.Position.X.Scale, hp_frame.Position.X.Offset, novaPosicaoFrameY)
end

character.Humanoid.HealthChanged:Connect(function(hp)
    vidaAtual = hp
    updateHealth()
end)

updateHealth()
