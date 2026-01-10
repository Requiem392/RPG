-- States/Attack.lua
local Attack = {}

function Attack.Enter(npc, context)
	-- Zera velocidade
	local humanoid = npc:FindFirstChild("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid:MoveTo(npc.PrimaryPart.Position)
	end
	
	context.AttackFinished = false
	
	-- Decide qual ataque usar (Pilar 4: Micro Decision)
	-- Por enquanto apenas simula
	print(npc.Name .. " ATACANDO!")
	
	-- Simulação de ataque (será substituído pelo Pilar 5: Execution)
	task.delay(1.5, function()
		context.AttackFinished = true
	end)
end

function Attack.Update(npc, context, dt)
	-- Aguarda final do ataque
	-- Se terminou, Pilar 3 decidirá ir para Recover
end

function Attack.Exit(npc, context)
	-- Limpa flags de ataque
end

return Attack
