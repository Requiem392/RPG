local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local net = require("@lune/net")
local serde = require("@lune/serde")

--========== CONFIGURAÇÕES ===========--

local outputFolder = "Game"
local inputFileName = "Place.rbxl" -- NOME DO ARQUIVO AQUI
local API_URL = "https://raw.githubusercontent.com/CloneTrooper1019/Roblox-Client-Tracker/roblox/API-Dump.json"

local RobloxClasses = {} 

local ScriptExtensions = {
    ["ModuleScript"] = ".module.luau",
    ["Script"]       = ".server.luau",
    ["LocalScript"]  = ".client.luau"
}

--===============================--

local function FetchRobloxAPI()
    print("Baixando API Dump...")
    local response = net.request({ url = API_URL, method = "GET" })
    if not response.ok then error("Erro API: " .. response.statusMessage) end
    local data = serde.decode("json", response.body)
    for _, classDef in ipairs(data.Classes) do RobloxClasses[classDef.Name] = classDef end
end

local function CreateDir(path)
    if not fs.isDir(path) then fs.writeDir(path) end
end

--===============================--
-- INÍCIO
--===============================--

FetchRobloxAPI()

print("Lendo arquivo " .. inputFileName .. "...")
local parsedFile = fs.readFile(inputFileName)
local game = roblox.deserializePlace(parsedFile)

CreateDir(outputFolder)

--===============================--

local function InheritsFrom(className, targetBaseClass)
    local currentClass = RobloxClasses[className]
    while currentClass do
        if currentClass.Name == targetBaseClass then return true end
        currentClass = RobloxClasses[currentClass.Superclass]
    end
    return false
end

local function IsInstanceInteresting(instance)
    local className = instance.ClassName
    if not RobloxClasses[className] then return false end
    if InheritsFrom(className, "Service") then return false end -- Serviços são tratados no loop principal
    if className == "Folder" then return false end -- Pastas são apenas diretórios
    if className == "Terrain" or className == "Camera" then return false end
    return true
end

local function CleanScriptSource(file)
    -- Remove tags XML ao redor do código fonte para salvar limpo
    local startTag = "<string name=\"Source\">"
    local endTag = "</string>"
    local s = file:find(startTag, 1, true)
    if not s then return file end
    s = s + #startTag
    local e = file:find(endTag, s, true) or -1
    local code = file:sub(s, e - 1)
    
    -- Decodifica HTML entities
    code = code:gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&amp;", "&"):gsub("&quot;", '"'):gsub("&apos;", "'")
    
    -- Remove seção CDATA se existir
    code = code:gsub("<!%[CDATA%[", ""):gsub("%]%]>", "")
    
    return code
end

local function SanitizeName(name)
    return name:gsub("[\\/:*?\"<>|]", "_") -- Remove caracteres proibidos no Windows
end

local function OutputFile(instance, folderPath)
    if not IsInstanceInteresting(instance) then return end

    local name = SanitizeName(instance.Name)
    local ext = ScriptExtensions[instance.ClassName]
    
    local content
    if ext then
        -- É SCRIPT: Salva apenas o código fonte limpo
        name = name .. ext
        local rawXml = roblox.serializeModel({instance}, true)
        content = CleanScriptSource(rawXml)
    else
        -- É OUTRA COISA (Part, Model, etc): Salva o modelo completo
        name = name .. "." .. instance.ClassName:lower() .. ".rbxmx"
        content = roblox.serializeModel({instance}, true)
    end

    fs.writeFile(folderPath .. "/" .. name, content)
end

-- Função Recursiva Principal
local function ProcessTree(instance, currentPath)
    -- 1. Cria a pasta para o item atual (se necessário)
    -- Se for o game ou serviços, a pasta já foi criada pelo loop principal
    
    -- 2. Itera sobre os filhos
    local children = instance:GetChildren()
    
    for _, child in ipairs(children) do
        -- A) Tenta salvar o arquivo do filho
        OutputFile(child, currentPath)
        
        -- B) Se o filho tiver filhos (ex: Model com Scripts, Pasta, ScreenGui)
        -- Cria uma subpasta e entra nela
        if #child:GetChildren() > 0 then
            local childFolderName = SanitizeName(child.Name)
            local newPath = currentPath .. "/" .. childFolderName
            
            CreateDir(newPath)
            ProcessTree(child, newPath)
        end
    end
end

--===============================--
-- LOOP DOS SERVIÇOS (Onde a mágica acontece)
--===============================--

local ServicesToExport = {
   -- "Workspace",
    "Lighting",
    "ReplicatedFirst",
    "ReplicatedStorage",
    "ServerScriptService",
    "ServerStorage",
    "StarterGui",
    "StarterPack",
    "StarterPlayer",
    "SoundService",
    "Chat"
}

for _, serviceName in ipairs(ServicesToExport) do
    local service = game:GetService(serviceName)
    if service then
        print("Exportando Serviço: " .. serviceName)
        
        -- Cria a pasta do serviço explicitamente dentro de Project/
        local servicePath = outputFolder .. "/" .. serviceName
        CreateDir(servicePath)
        
        -- Processa tudo dentro desse serviço
        ProcessTree(service, servicePath)
    end
end

print("Concluído! Pastas separadas com sucesso.")