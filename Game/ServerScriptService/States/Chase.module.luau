-- States/Chase.lua
local Chase = {}

function Chase.Enter(npc, context)
	local humanoid = npc:FindFirstChild("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 20 -- Corre
	end
	
	print(npc.Name .. " começou a PERSEGUIR!")
end

function Chase.Update(npc, context, dt)
	-- Lógica de movimento será gerenciada aqui ou no Pilar 3?
	-- Geralmente o estado executa o output da decisão.
	-- Aqui vamos assumir que se está em Chase, deve ir até o alvo.
	
	-- OBS: Movimento real deve vir de um MovementController (Pilar de Movimento)
	-- Mas por enquanto vamos fazer simples:
	
	-- local targetPos = ... (pegar da percepção)
	-- npc.Humanoid:MoveTo(targetPos)
end

function Chase.Exit(npc, context)
	local humanoid = npc:FindFirstChild("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 16 -- Volta ao normal
		humanoid:MoveTo(npc.PrimaryPart.Position) -- Para
	end
end

return Chase
