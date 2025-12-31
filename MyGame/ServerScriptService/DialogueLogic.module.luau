local DialogueLogic = {}

-- === BIBLIOTECA DE CONDIÇÕES ===
-- Aqui você adiciona qualquer regra nova que seu RPG precisar
function DialogueLogic.CheckRequirements(player, requirements)
	if not requirements then return true end -- Sem requisitos = aprovado

	local leaderstats = player:FindFirstChild("leaderstats")

	for _, req in pairs(requirements) do

		-- TIPO 1: LEVEL
		if req.Type == "Level" then
			if not leaderstats or leaderstats.Level.Value < req.Value then
				return false -- Reprovado
			end

			-- TIPO 2: GOLD
		elseif req.Type == "Gold" then
			if not leaderstats or leaderstats.Gold.Value < req.Value then
				return false
			end

			-- TIPO 3: ITEM (Exemplo)
		elseif req.Type == "HasItem" then
			if not player.Backpack:FindFirstChild(req.Value) then
				return false
			end

			-- TIPO 4: QUEST (Exemplo com boolvalues ou pasta)
		elseif req.Type == "QuestFinished" then
			local questData = player:FindFirstChild("QuestsCompleted")
			if not questData or not questData:FindFirstChild(req.Value) then
				return false
			end
		end
	end

	return true -- Passou em tudo!
end

-- === BIBLIOTECA DE AÇÕES ===
-- Aqui você define o que acontece quando o player escolhe uma resposta
function DialogueLogic.ExecuteAction(player, actionData)
	if not actionData then return end

	if actionData.Type == "StartQuest" then
		-- Chame seu sistema de quest aqui
		print("⚔️ Quest Iniciada: " .. actionData.Value)
		-- Exemplo: QuestSystem.Start(player, actionData.Value)

	elseif actionData.Type == "GiveGold" then
		player.leaderstats.Gold.Value += actionData.Value

	elseif actionData.Type == "Teleport" then
		-- Lógica de tp...
	end
end

return DialogueLogic