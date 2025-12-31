local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- 1. Pegamos os seus Módulos
local DialogueData = require(ReplicatedStorage:WaitForChild("DialogueData"))
local DialogueLogic = require(ServerScriptService:WaitForChild("DialogueLogic"))

-- 2. Pegamos o telefone (RemoteFunction)
local DialogoRF = ReplicatedStorage:WaitForChild("DialogoRF")

-- === FUNÇÃO QUE ATENDE A LIGAÇÃO DO CLIENTE ===
DialogoRF.OnServerInvoke = function(player, acao, argumento)

	-- CASO A: Player quer iniciar/pegar um diálogo
	if acao == "PegarDialogo" then
		local idDialogo = argumento
		local dados = DialogueData[idDialogo]

		if not dados then 
			warn("Dialogo não existe: " .. tostring(idDialogo))
			return nil 
		end

		-- [AQUI ENTRA O SEU MODULE LOGIC]
		-- Verifica se o player cumpre os requisitos (Level, Gold, etc)
		local podeVer = DialogueLogic.CheckRequirements(player, dados.Requirements)

		if podeVer then
			return dados -- Aprovado: Mostra o diálogo normal
		else
			-- Reprovado: Retorna o texto de falha E um botão de saída
			return {
				Text = dados.FailText or "Você não pode falar comigo agora.",
				Responses = {
					{
						Text = "Entendi.", -- Texto do botão
						NextID = "EXIT"    -- Ação de fechar
					}
				}
			}
		end

		-- CASO B: Player escolheu uma opção (Clicou no botão)
	elseif acao == "EscolherOpcao" then
		local actionData = argumento -- O objeto 'Action' que estava no DialogueData

		-- [AQUI ENTRA O SEU MODULE LOGIC]
		-- Executa a recompensa (Dar Quest, Dar Gold, etc)
		DialogueLogic.ExecuteAction(player, actionData)

		return true -- Confirma que deu certo
	end

	return nil
end