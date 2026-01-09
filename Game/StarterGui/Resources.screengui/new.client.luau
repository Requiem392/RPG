local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")

-- --- REFERÊNCIAS ---
local main_frame = script.Parent:WaitForChild("HP")
local hp_frame = main_frame:WaitForChild("ORB_FRAME") 
local gradient = hp_frame:WaitForChild("UIGradient") -- O NOVO método!

-- ======================================================================
-- CONFIGURAÇÃO UIGradient Masking
-- ======================================================================
-- Usando UIGradient como "máscara de corte" (clipping mask)
-- Método MUITO mais otimizado que mover câmera ou frames!
--
-- Offset.Y:
--   0.0 = Barra 100% cheia (líquido até o topo)
--   1.0 = Barra 0% vazia (líquido sumiu)
--
-- IMPORTANTE: O UIGradient deve estar configurado assim no Explorer:
--   - Rotation = -90 (para gradiente vertical)
--   - Transparency = NumberSequence com:
--      • 0.0 → Transparency 0 (opaco)
--      • ~0.99 → Transparency 0 (opaco)
--      • 1.0 → Transparency 1 (transparente)
--   Isso cria o "corte seco" sem fade!
-- ======================================================================

-- VELOCIDADE DO LÍQUIDO (O Segredo da Fluidez)
local VELOCIDADE_SUAVIZACAO = 0.15

-- ======================================================================

-- Variável para guardar onde o líquido está "visualmente" neste momento
local vidaVisual = humanoid.Health 

local function atualizarLiquido()
	local maxHp = humanoid.MaxHealth
	local vidaReal = humanoid.Health

	-- --- A MÁGICA (LERP MANUAL) ---
	-- Em vez de ir direto, a vida visual viaja 15% do caminho a cada frame.
	vidaVisual = vidaVisual + (vidaReal - vidaVisual) * VELOCIDADE_SUAVIZACAO

	-- Transforma em porcentagem (0 a 1)
	local porcentagem = math.clamp(vidaVisual / maxHp, 0, 1)

	-- MÉTODO NOVO: Usa Offset.Y do UIGradient como máscara de corte
	-- (Invertido: 1 - porcentagem porque Offset 0 = cheio, Offset 1 = vazio)
	gradient.Offset = Vector2.new(0, 1 - porcentagem)
end

-- Roda essa função a cada frame do jogo (super suave)
RunService.RenderStepped:Connect(atualizarLiquido)

-- Se o personagem morrer e nascer de novo
player.CharacterAdded:Connect(function(newChar)
	character = newChar
	humanoid = newChar:WaitForChild("Humanoid")
	-- Puxa o visual direto pra vida real pra não "encher" do zero ao nascer
	vidaVisual = humanoid.Health 
end)