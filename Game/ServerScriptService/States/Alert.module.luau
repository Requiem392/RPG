-- States/Alert.module.luau
local Alert = {}

local ServerScriptService = game:GetService("ServerScriptService")
local NPCPerception = require(ServerScriptService.NPCPerception)
local NPCMovement = require(ServerScriptService.NPCMovement) 

-- Configuração do Comportamento
local LOOK_DURATION = 1.5
local SEARCH_RADIUS = 8
local MOVE_SPEED = 8
local SEARCH_SPEED = 6
local OBSERVE_DURATION = 2.5
local MAX_SEARCH_STEPS = 6

function Alert.Enter(npc, context)
	-- Inicializa Fases
	context.AlertPhase = "LOOK"
	context.AlertStartTime = tick()
	context.CurrentPhaseStartTime = tick()
	
	-- Inicializa SEARCH (mesmo que não use agora)
	context.SearchStep = 1
	context.IsObserving = false
	context.AlertTargetPos = nil -- Fixa a posição do som
	
	NPCMovement.Stop(npc) 
	print(npc.Name .. " 👀 ouviu algo... (LOOK)")
end

function Alert.Update(npc, context, dt)
	local npcRoot = npc:FindFirstChild("HumanoidRootPart")
	if not npcRoot then return end

	local currentTime = tick()
	local phaseTime = currentTime - context.CurrentPhaseStartTime
	
	-- Busca dados UMA VEZ para fixar alvo se necessário
	if not context.AlertTargetPos then
		local data = NPCPerception.GetData(npc)
		if data and data.SuspectPosition then 
			context.AlertTargetPos = data.SuspectPosition
		else
			return -- Sem alvo, NPCDecision resolve
		end
	end

	-- MÁQUINA DE ESTADOS INTERNA
	
	-- ======================================================================
	-- FASE 1: LOOK (Parado -> Move)
	-- ======================================================================
	if context.AlertPhase == "LOOK" then
		-- Apenas espera (NÃO GIRA MAIS MANUALMENTE)
		-- Futuro: Tocar animação de "olhar para os lados"
		
		-- Transição -> MOVE
		if phaseTime >= LOOK_DURATION then
			context.AlertPhase = "MOVE"
			context.CurrentPhaseStartTime = currentTime
			context.InvestigationLocked = true -- TRAVA! Agora ele vai até o fim
			print(npc.Name .. " 👣 investigando... (MOVE)")
		end
		
	-- ======================================================================
	-- FASE 2: MOVE (Vai até o som)
	-- ======================================================================
	elseif context.AlertPhase == "MOVE" then
		NPCMovement.MoveTo(npc, context.AlertTargetPos, {speed = MOVE_SPEED})
		
		local dist = (npcRoot.Position - context.AlertTargetPos).Magnitude
		
		-- Transição -> SEARCH (SÓ QUANDO CHEGAR)
		if dist < 1.5 then 
			context.AlertPhase = "SEARCH"
			context.CurrentPhaseStartTime = currentTime
			context.SearchStep = 1
			context.NextSearchPoint = nil 
			-- Reset context values
			context.PointArriveTime = nil
			context.IsObserving = false
			print(npc.Name .. " 🔍 chegou no local suspeito... SEARCH inicado.")
		end
		
	-- ======================================================================
	-- FASE 3: SEARCH (6 Passos)
	-- ======================================================================
	elseif context.AlertPhase == "SEARCH" then
		
		-- Se terminou os passos, libera a trava e para
		if context.SearchStep > MAX_SEARCH_STEPS then
			context.InvestigationLocked = false -- DESTRAVA! Pode voltar pra Idle
			NPCMovement.Stop(npc)
			return
		end

		-- PENÚLTIMO PASSO: OBSERVAÇÃO (Obrigatório)
		if context.SearchStep == MAX_SEARCH_STEPS - 1 then
			if not context.IsObserving then
				context.IsObserving = true
				context.ObserveStartTime = currentTime
				NPCMovement.Stop(npc)
				print(npc.Name .. " 👀 observando área... (Step " .. context.SearchStep .. ")")
			end
			
			-- Rotação 360 Suave (via NPCMovement)
			local elapsedTime = currentTime - context.ObserveStartTime
			local angle = elapsedTime * 2 -- Velocidade de rotação
			local rotDir = Vector3.new(math.sin(angle), 0, math.cos(angle))
			NPCMovement.FaceDirection(npc, rotDir)
			
			-- Acabou observação? Próximo passo
			if elapsedTime >= OBSERVE_DURATION then
				context.IsObserving = false
				context.SearchStep = context.SearchStep + 1
				context.NextSearchPoint = nil
				print(npc.Name .. " 🔍 busca retomada...")
			end
			return
		end
		
		-- PASSOS DE MOVIMENTO
		if not context.NextSearchPoint then
			local randomOffset = Vector3.new(
				math.random(-SEARCH_RADIUS, SEARCH_RADIUS),
				0,
				math.random(-SEARCH_RADIUS, SEARCH_RADIUS)
			)
			context.NextSearchPoint = context.AlertTargetPos + randomOffset
			context.PointArriveTime = nil -- Reset timer
		end
		
		-- Se já chegou, espera. Se não, anda.
		if context.PointArriveTime then
			NPCMovement.Stop(npc)
			if currentTime - context.PointArriveTime > 1.5 then -- Pausa de 1.5s
				context.SearchStep = context.SearchStep + 1
				context.NextSearchPoint = nil
				context.PointArriveTime = nil
				if context.SearchStep <= MAX_SEARCH_STEPS then
					print(npc.Name .. " 🔍 indo para Step " .. context.SearchStep)
				end
			end
		else
			-- Anda até o ponto
			NPCMovement.MoveTo(npc, context.NextSearchPoint, {speed = SEARCH_SPEED})
			
			-- Verifica chegada (ESTRITA)
			if context.NextSearchPoint then
				local distToPoint = (Vector3.new(npcRoot.Position.X, 0, npcRoot.Position.Z) - Vector3.new(context.NextSearchPoint.X, 0, context.NextSearchPoint.Z)).Magnitude
				
				if distToPoint < 1.5 then -- Chegou no ponto EXATO!
					context.PointArriveTime = currentTime 
					NPCMovement.Stop(npc)
					print(npc.Name .. " 🛑 chegou no ponto... verificando.")
				end
			end
		end
	end
end

function Alert.Exit(npc, context)
	NPCMovement.Stop(npc)
	
	-- Limpa contexto
	context.AlertPhase = nil
	context.AlertStartTime = nil
	context.AlertTargetPos = nil
	context.SearchStep = nil
	context.IsObserving = nil
	context.NextSearchPoint = nil
end

return Alert
