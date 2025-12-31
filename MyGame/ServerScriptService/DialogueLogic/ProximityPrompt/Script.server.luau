local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Tem que ser o mesmo nome do raiozinho que criamos
local eventoStart = ReplicatedStorage:WaitForChild("RequestDialogoStart")

-- O ID tem que existir no seu ModuleScript DialogueData
local ID_DIALOGO = "Guardiao_Inicio" 

script.Parent.Triggered:Connect(function(player)
	print("📩 NPC chamando player...")
	eventoStart:FireClient(player, ID_DIALOGO)
end)