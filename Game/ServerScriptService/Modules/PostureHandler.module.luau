local PostureHandler = {}
PostureHandler.__index = PostureHandler

-- Registry
PostureHandler.Registry = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

-- Dependência (Será carregada no Init para evitar ciclo se necessário, mas aqui usaremos require direto pois Modules já deve ter DefenseHandler)
-- Como estamos criando DefenseHandler agora, devemos garantir que o require aponte para o nome certo.
-- O arquivo novo chama DefenseHandler.module.luau.

local DefenseHandler -- Late require no Init ou topo se seguro.

-- Remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local PostureUpdate = Remotes:FindFirstChild("PostureUpdate")
if not PostureUpdate then
	PostureUpdate = Instance.new("RemoteEvent")
	PostureUpdate.Name = "PostureUpdate"
	PostureUpdate.Parent = Remotes
end

-- ======================================================================
-- CONFIGURAÇÃO
-- ======================================================================

local CONFIG = {
	MaxPosture = 100,
	RegenRate = 10,           -- Postura regenerada por segundo
	PostureBreakStun = 2.5,   -- Duração do stun ao quebrar postura
	MinPostureDamage = 5,     -- Dano mínimo de postura
}

-- ======================================================================
-- CONSTRUTOR
-- ======================================================================

function PostureHandler.new(owner)
    local self = setmetatable({}, PostureHandler)
    self.Owner = owner
    self.Posture = CONFIG.MaxPosture
    
    if owner:IsA("Player") then
        PostureHandler.Registry[owner] = self
        
        -- Envia estado inicial para cliente
        PostureUpdate:FireClient(owner, "Init", {
            Posture = CONFIG.MaxPosture
        })
        print("⚖️ [PostureHandler] Postura criada para:", owner.Name)
    else
        print("⚖️ [PostureHandler] Postura criada para NPC:", owner.Name)
    end
    
    return self
end

function PostureHandler:Destroy()
    if self.Owner:IsA("Player") then
        PostureHandler.Registry[self.Owner] = nil
    end
    self.Owner = nil
end

-- ======================================================================
-- MÉTODOS DE INSTÂNCIA
-- ======================================================================

function PostureHandler:Damage(damage)
    -- Aplica dano
	self.Posture = math.max(self.Posture - damage, 0)
	
	-- print("⚖️ [PostureHandler]", self.Owner.Name, "perdeu", damage, "de postura →", self.Posture)
	
	-- Atualiza cliente se for Player
    if self.Owner:IsA("Player") then
        PostureUpdate:FireClient(self.Owner, "Update", {
            Posture = self.Posture
        })
    end
	
	-- Verifica Posture Break
	if self.Posture <= 0 then
		print("💥 [PostureHandler] POSTURE BREAK!", self.Owner.Name)
		
		-- Reseta postura
		self.Posture = CONFIG.MaxPosture
		
		-- Se for Player, força parar de bloquear
        if self.Owner:IsA("Player") then
            local defenseEvent = Remotes:FindFirstChild("DefenseAction")
            if defenseEvent then
                defenseEvent:FireClient(self.Owner, "ForceStopBlock")
            end
            
            PostureUpdate:FireClient(self.Owner, "Break", {
                Posture = CONFIG.MaxPosture
            })
        end
        
		-- Aplica Stun
		if DefenseHandler then
            local defHandler = DefenseHandler.GetHandler(self.Owner)
            if defHandler then
                defHandler:Stun(CONFIG.PostureBreakStun)
            end
		end
	end
end

function PostureHandler:GetPosture()
    return self.Posture
end

function PostureHandler:Update(dt)
    -- Regeneração
    -- Precisa checar se ESTÁ BLOQUEANDO.
    local isBlocking = false
    
    if DefenseHandler then
        local defHandler = DefenseHandler.GetHandler(self.Owner)
        if defHandler then
            isBlocking = defHandler:IsBlocking()
        end
    end
    
    if not isBlocking and self.Posture < CONFIG.MaxPosture then
        self.Posture = math.min(self.Posture + CONFIG.RegenRate * dt, CONFIG.MaxPosture)
        
        -- Throttled update networking could be here, but for simplicity we send often or on change.
        -- O service original tinha throttle de 0.1s.
        
        if self.Owner:IsA("Player") then
            -- Só envia se passou X tempo (podemos adicionar self.LastUpdate)
            if not self.LastUpdate or (os.clock() - self.LastUpdate > 0.1) then
                 PostureUpdate:FireClient(self.Owner, "Update", { Posture = self.Posture })
                 self.LastUpdate = os.clock()
            end
        end
    end
end


-- ======================================================================
-- INIT ESTÁTICO
-- ======================================================================

local Initialized = false
function PostureHandler.Init()
    if Initialized then return end
    Initialized = true

    print("⚖️ Inicializando PostureHandler (Static)...")
    
    local Modules = ServerScriptService:WaitForChild("Modules")
    DefenseHandler = require(Modules:WaitForChild("DefenseHandler"))

    -- Loop de regeneração
    RunService.Heartbeat:Connect(function(dt)
        for _, handler in pairs(PostureHandler.Registry) do
            handler:Update(dt)
        end
        -- TODO: NPCs loop
    end)
    
    print("✅ PostureHandler Loop iniciado")
end

return PostureHandler
