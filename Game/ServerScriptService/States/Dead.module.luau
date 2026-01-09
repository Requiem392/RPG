-- States/Dead.module.luau
local Dead = {}

local ServerScriptService = game:GetService("ServerScriptService")
local NPCMovement = require(ServerScriptService.NPCMovement)

function Dead.Enter(npc, context)
	-- Toca animação de morte
	-- Desabilita colisões
	-- Solta loot
	
	print(npc.Name .. " MORREU 💀")
	
	-- Desabilita percepção e movimento
	NPCMovement.Stop(npc)
	local humanoid = npc:FindFirstChild("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid:ChangeState(Enum.HumanoidStateType.Physics) -- Ragdoll simples
	end
end

function Dead.Update(npc, context, dt)
	-- Nada acontece feijoada
end

function Dead.Exit(npc, context)
	-- Morto não sai do estado Dead (geralmente)
end

return Dead
