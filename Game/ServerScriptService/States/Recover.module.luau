-- States/Recover.lua
local Recover = {}

function Recover.Enter(npc, context)
	-- Estado de vulnerabilidade pós-ataque
	local humanoid = npc:FindFirstChild("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 4 -- Anda devagar
	end
	
	context.RecoverTime = 1.0 -- Tempo fixo por enquanto
	context.EnteredRecover = tick()
	
	-- print(npc.Name .. " recuperando...")
end

function Recover.Update(npc, context, dt)
	-- Checa se tempo acabou
	if tick() - context.EnteredRecover >= context.RecoverTime then
		context.RecoverFinished = true
	end
end

function Recover.Exit(npc, context)
	context.RecoverFinished = false
end

return Recover
