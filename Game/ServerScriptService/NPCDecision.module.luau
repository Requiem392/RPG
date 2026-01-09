--[[
	NPCDecision.module.luau
	
	Pilar 3: DECISION MAKING (MACRO)
	
	Responsabilidade:
	- Analisar dados de Percepção e Estado Atual
	- Decidir qual o PRÓXIMO estado
	- NÃO executa ações
	- NÃO altera variáveis de estado (apenas lê)
]]

local NPCDecision = {}

-- Configurações Básicas (serão movidas para NPCConfig depois)
local DECISION_CONFIG = {
	AlertDuration = 2.0,    -- Tempo em Alert antes de Chase
	AttackRange = 5.0,      -- Distância para iniciar ataque
	RecoverDuration = 1.0,  -- Tempo vulnerável pós-ataque
	ChaseGiveUpDistance = 60 -- Distância para desistir
}

function NPCDecision.GetNextState(npc, perceptionData, currentState, stateTime)
	local currentTime = tick()
	local timeInState = currentTime - stateTime
	
	-- ======================================================================
	-- 1. PRIORIDADE MÁXIMA (Sobrevivência/Global)
	-- ======================================================================
	
	local humanoid = npc:FindFirstChild("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		if currentState ~= "Dead" then
			return "Dead"
		end
		return nil -- Já está morto
	end
	
	-- ======================================================================
	-- 2. SEM ALVO DETECTADO
	-- ======================================================================
	
	if not perceptionData.CurrentTarget then
		-- Se ouviu algo (Suspeita), vai para Alert
		if perceptionData.HasSuspicion then
			if currentState ~= "Alert" then
				return "Alert"
			end
			return nil
		end
		
		-- Sem visão e sem suspeita -> Idle
		if currentState ~= "Idle" then
			return "Idle"
		end
		return nil
	end
	
	-- 3. COM ALVO (Potencialmente)
	-- ======================================================================
	
	-- Só consideramos que "TEM ALVO" se tivermos alguma info sensorial
	local hasSensoryInfo = perceptionData.HasVisual or perceptionData.HasSuspicion or perceptionData.LastSeenPosition
	
	if not hasSensoryInfo then
		if currentState ~= "Idle" then
			return "Idle"
		end
		return nil
	end

	-- Transições específicas do estado atual
	
	if currentState == "Idle" then
		-- Só sai do Idle se tiver info sensorial concreta (já checado acima)
		return "Alert"
	end
	
	if currentState == "Alert" then
		-- Se já confirmou alvo visualmente e passou o tempo de reação
		if perceptionData.HasVisual and timeInState >= DECISION_CONFIG.AlertDuration then
			return "Chase"
		end
		
		-- Se perdeu o alvo de vista E a suspeita acabou -> Idle
		if not perceptionData.HasVisual and not perceptionData.LastSeenPosition and not perceptionData.HasSuspicion then
			return "Idle"
		end
	end
	
	if currentState == "Chase" then
		local dist = perceptionData.DistanceToTarget
		
		-- Alvo muito longe -> Desiste (Idle) ou volta pra Alert?
		-- Por enquanto: se perdeu visual E memória acabou -> Alert (para procurar)
		if not perceptionData.HasVisual and (currentTime - perceptionData.LastSeenTime > 5) then
			return "Alert"
		end
		
		-- Perto o suficiente -> Attack
		if dist <= DECISION_CONFIG.AttackRange then
			return "Attack"
		end
	end
	
	if currentState == "Attack" then
		-- O estado Attack deve sinalizar quando acabou (via Context, não temos acesso aqui ainda)
		-- Mas o StateMachine deve passar dados extras?
		-- Por simplificação, vamos assumir que Attack termina por tempo ou sinal
		-- Como Decisions roda todo frame, precismos saber se o ataque acabou.
		
		-- *NOTA*: O correto é checar uma flag no Context compartilhado.
		-- Vamos assumir que essa flag é passada ou o próprio Attack transitiona?
		-- NÃO, Estados não decidem.
		
		-- Solução Temporária: Attack define TimeInState e nós usamos tempo fixo simulado
		-- Depois, Pilar 5 (Execution) vai dar a flag de "AttackFinished"
		
		if timeInState >= 1.5 then -- Tempo mock de ataque
			return "Recover"
		end
	end
	
	if currentState == "Recover" then
		if timeInState >= DECISION_CONFIG.RecoverDuration then
			-- Voltou do recover, ainda tem alvo?
			if perceptionData.HasVisual then
				-- Se está perto, ataca de novo? Ou Chase para reposicionar?
				return "Chase"
			else
				return "Alert"
			end
		end
	end
	
	return nil -- Nenhuma mudança necessária
end

return NPCDecision
