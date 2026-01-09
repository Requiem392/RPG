--[[
	NPCDecision.module.luau
	
	Pilar 3: DECISION MAKING (Macro)
	
	Responsabilidades:
	- Determinar "Qual a próxima intenção do NPC?"
	- Avaliar transições de estado com base em:
		1. Percepção (PerceptionData)
		2. Estado Atual (StateMachine)
		3. Status (Vida, etc.)
	
	NÃO FAZ:
	- Executar ações
	- Escolher ataques específicos (Isso é Pilar 4)
	- Mover o NPC
]]

local NPCDecision = {}

-- ======================================================================
-- CONFIGURAÇÃO
-- ======================================================================

local ATTACK_RANGE = 6  -- Distância para começar a atacar
local STOP_CHASE_DISTANCE = 40 -- Distância para desistir (se perder visão)

-- ======================================================================
-- LÓGICA DE DECISÃO
-- ======================================================================

function NPCDecision.DecideNextState(npc, perceptionData, currentStateName, context)
	if not perceptionData then return nil end
	
	-- 1. MORTE (Prioridade Máxima)
	local humanoid = npc:FindFirstChild("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		if currentStateName ~= "Dead" then
			return "Dead"
		end
		return nil
	end
	
	-- Se já está morto, não decide mais nada
	if currentStateName == "Dead" then
		return nil
	end
	
	-- 2. RECUPERAÇÃO (Recover)
	if currentStateName == "Recover" then
		-- Só sai se terminou
		if context and context.RecoverFinished then
			-- Fallthrough para reavaliar (provavelmente Chase ou Idle)
		else
			return nil -- Continua recuperando
		end
	end
	
	-- 3. ATAQUE (Attack)
	if currentStateName == "Attack" then
		-- Só sai se terminou
		if context and context.AttackFinished then
			-- Se terminou ataque, DEVE ir para Recover (regra de combate)
			return "Recover"
		else
			return nil -- Continua atacando
		end
	end

	-- 4. ALVO PERDIDO OU INVÁLIDO
	local target = perceptionData.CurrentTarget
	if not target or (not perceptionData.HasVisual and not perceptionData.HasSuspicion and not perceptionData.LastSeenPosition) then
		-- Sem alvo, sem visão, sem memória, sem suspeita -> IDLE
		if currentStateName ~= "Idle" then
			return "Idle"
		end
		return nil
	end
	
	-- 5. REAÇÃO A SUSPEITA (Sem visão, mas ouviu algo)
	-- Se está em Alert, verifica trava de investigação
	if currentStateName == "Alert" then
		-- Se tem VISÃO, interrompe e persegue (prioridade alta)
		if perceptionData.HasVisual then
			return "Chase" -- Chase sempre vence Alert
		end
		
		-- Se está travado na investigação, NÃO SAI (ignora timeouts ou outros sons menores)
		if context and context.InvestigationLocked then
			return nil 
		end
	end
	
	if not perceptionData.HasVisual and not perceptionData.LastSeenPosition and perceptionData.HasSuspicion then
		if currentStateName ~= "Alert" then
			return "Alert"
		end
		return nil
	end
	
	-- 6. COMBATE / PERSEGUIÇÃO (Com alvo confirmado ou memória visual)
	
	-- Distância até o alvo (ou até a última posição conhecida)
	local dist = perceptionData.DistanceToTarget
	
	-- Se estamos muito longe e sem visão direta (apenas memória), talvez desistir?
	-- Por enquanto, se tem memória (LastSeenPosition), ele vai até lá (Chase).
	
	-- Se está perto o suficiente para atacar (e tem visão direta)
	if dist <= ATTACK_RANGE and perceptionData.HasVisual then
		if currentStateName ~= "Attack" then
			return "Attack"
		end
	else
		-- Se não pode atacar, deve perseguir
		if currentStateName ~= "Chase" then
			return "Chase" -- Chase lida com ir até o Alvo ou LastSeenPosition
		end
	end
	
	-- Nenhuma mudança necessária
	return nil
end

return NPCDecision
