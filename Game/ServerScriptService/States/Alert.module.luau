-- States/Alert.lua
local Alert = {}

function Alert.Enter(npc, context)
	-- Toca animação de alerta
	-- Olha na direção do som/suspeita
	
	print(npc.Name .. " está ALERTA!")
end

function Alert.Update(npc, context, dt)
	-- Gira para olhar para SuspectPosition (se houver)
	-- Aguarda confirmação visual
end

function Alert.Exit(npc, context)
	-- Para animação de alerta
end

return Alert
