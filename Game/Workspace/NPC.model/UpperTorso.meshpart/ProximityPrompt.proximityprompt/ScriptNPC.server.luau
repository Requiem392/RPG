local ReplicatedStorage = game:GetService("ReplicatedStorage")
local eventoStart = ReplicatedStorage:WaitForChild("RequestDialogoStart")

local ID_DO_DIALOGO = "NPC_TesteRecompensa" 

script.Parent.Triggered:Connect(function(player)
	-- CORREÇÃO AQUI 👇
	-- Adicionamos mais um .Parent para sair do Torso e pegar o Modelo inteiro
	local modeloNPC = script.Parent.Parent.Parent 

	-- Debug pra confirmar se agora pegou o Modelo (não pode sair "Torso" ou "HumanoidRootPart")
	print("✅ Enviando NPC correto: " .. modeloNPC.Name) 

	eventoStart:FireClient(player, ID_DO_DIALOGO, modeloNPC)
end)