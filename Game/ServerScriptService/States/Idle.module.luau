-- States/Idle.module.luau
local Idle = {}

local ServerScriptService = game:GetService("ServerScriptService")
local NPCMovement = require(ServerScriptService.NPCMovement)

function Idle.Enter(npc, context)
	NPCMovement.Stop(npc)
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
