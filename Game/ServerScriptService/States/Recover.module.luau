-- States/Recover.module.luau
local Recover = {}

local ServerScriptService = game:GetService("ServerScriptService")
local NPCMovement = require(ServerScriptService.NPCMovement)

function Recover.Enter(npc, context)
	-- Estado de vulnerabilidade pós-ataque
	NPCMovement.SetLocked(npc, true) -- Trava, ou talvez permitir movimento lento?
	-- "Recover should set true on Enter and false on Exit" -User
	
	local humanoid = npc:FindFirstChild("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 4 -- Anda devagar se mover manualmente (mas agora tá travado)
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
	NPCMovement.SetLocked(npc, false)
	context.RecoverFinished = false
end

return Recover
