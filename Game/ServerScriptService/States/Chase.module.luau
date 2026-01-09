-- States/Chase.module.luau
local Chase = {}

-- Precisa acessar Percepção para saber ONDE está o alvo
local ServerScriptService = game:GetService("ServerScriptService")
local NPCPerception = require(ServerScriptService.NPCPerception)
local NPCMovement = require(ServerScriptService.NPCMovement) -- Novo require

function Chase.Enter(npc, context)
	-- Velocidade é controlada pelo NPCMovement.MoveTo
	-- print(npc.Name .. " começou a PERSEGUIR!")
end

function Chase.Update(npc, context, dt)
	-- Busca dados de percepção
	local data = NPCPerception.GetData(npc)
	if not data then return end
	
	local targetPos = nil
	
	-- Prioridade: Onde o alvo está AGORA (Visão)
	if data.HasVisual and data.CurrentTarget and data.CurrentTarget.Character and data.CurrentTarget.Character.PrimaryPart then
		targetPos = data.CurrentTarget.Character.PrimaryPart.Position
		
	-- Fallback: Última posição conhecida (Memória)
	elseif data.LastSeenPosition then
		targetPos = data.LastSeenPosition
	end
	
	-- Move se tiver destino
	if targetPos then
		-- Otimização interna do NPCMovement já lida com spam, mas podemos manter um throttle simples se quisermos
		NPCMovement.MoveTo(npc, targetPos, {speed = 20}) -- Corre
	end
end

function Chase.Exit(npc, context)
	NPCMovement.Stop(npc)
end

return Chase
