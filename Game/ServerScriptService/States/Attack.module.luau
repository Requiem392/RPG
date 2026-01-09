-- States/Attack.module.luau
local Attack = {}

local ServerScriptService = game:GetService("ServerScriptService")
local NPCMovement = require(ServerScriptService.NPCMovement)

function Attack.Enter(npc, context)
	-- Zera velocidade e para
	NPCMovement.Stop(npc)
	local humanoid = npc:FindFirstChild("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 0 -- Força zero para não ser empurrado facilmente
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
