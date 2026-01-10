-- States/Idle.lua
local Idle = {}

function Idle.Enter(npc, context)
	-- Para animação de movimento
	local humanoid = npc:FindFirstChild("Humanoid")
	if humanoid then
		humanoid:MoveTo(npc.PrimaryPart.Position) -- Para movimento
	end
	
	-- print(npc.Name .. " entrou em Idle")
end

function Idle.Update(npc, context, dt)
	-- Em Idle, o NPC pode:
	-- 1. Patrulhar (se tiver waypoints)
	-- 2. Ficar parado respirando
	-- 3. Observar aleatoriamente
	
	-- Lógica de decisão (Pilar 3) vai tirar ele daqui
end

function Idle.Exit(npc, context)
	-- Limpa flags de patrulha se necessário
end

return Idle
