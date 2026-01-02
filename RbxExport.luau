local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local net = require("@lune/net")
local serde = require("@lune/serde")

-- 1. CONFIGURAÇÕES
local outputFolder = "Game"
local inputFileName = "Place.rbxl" 
local API_URL = "https://raw.githubusercontent.com/CloneTrooper1019/Roblox-Client-Tracker/roblox/API-Dump.json"

local ScriptExtensions = {
    ["ModuleScript"] = ".module.luau",
    ["Script"]       = ".server.luau",
    ["LocalScript"]  = ".client.luau"
}

-- 2. PREPARAÇÃO
local RobloxClasses = {}
local response = net.request({ url = API_URL, method = "GET" })
if response.ok then
    local data = serde.decode("json", response.body)
    for _, classDef in ipairs(data.Classes) do RobloxClasses[classDef.Name] = classDef end
end

if fs.isDir(outputFolder) then fs.removeDir(outputFolder) end
fs.writeDir(outputFolder)

-- 3. FUNÇÕES AUXILIARES
local function Sanitize(name)
    return name:gsub("[\\/:*?\"<>|]", "_")
end

local function CleanSource(code)
    local s = code:find("<string name=\"Source\">")
    if not s then return code end
    s = s + 22
    local e = code:find("</string>", s) or -1
    return code:sub(s, e - 1):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&amp;", "&"):gsub("&quot;", '"'):gsub("&apos;", "'"):gsub("<!%[CDATA%[", ""):gsub("%]%]>", "")
end

-- 4. ESCREVE ARQUIVO (Itens sem filhos)
local function WriteItem(instance, path)
    local name = Sanitize(instance.Name)
    local ext = ScriptExtensions[instance.ClassName]
    local fileName, content

    local suffix = "." .. instance.ClassName:lower()

    if ext then
        fileName = name .. ext
        content = CleanSource(roblox.serializeModel({instance}, true))
    else
        -- Se for Folder sem filhos, não precisa do sufixo .folder no arquivo também, 
        -- mas como é um arquivo placeholder, vamos manter pra saber o tipo, ou tirar se preferir.
        -- Vou manter no arquivo solto pra diferenciar de arquivo sem extensão.
        fileName = name .. suffix .. ".rbxmx"
        content = "PLACEHOLDER\nType: " .. instance.ClassName
    end

    fs.writeFile(path .. "/" .. fileName, content)
end

-- 5. LÓGICA DE PASTAS (AQUI ESTÁ A MUDANÇA)
local function ProcessNode(instance, currentPath)
    local children = instance:GetChildren()
    local name = Sanitize(instance.Name)

    if #children > 0 then
        -- Define o nome da pasta
        local folderName
        
        if instance.ClassName == "Folder" then
            -- Se JÁ É uma Folder, usa só o nome (Ex: "AssetsItems")
            folderName = name
        else
            -- Se é outra coisa (ScreenGui, Frame), usa o sufixo (Ex: "CombateUI.screengui")
            folderName = name .. "." .. instance.ClassName:lower()
        end
        
        local newPath = currentPath .. "/" .. folderName
        
        if not fs.isDir(newPath) then fs.writeDir(newPath) end

        -- Se for Folder normal, não precisamos salvar o arquivo "pai" dentro dela,
        -- pois a pasta já representa a Folder.
        -- Mas se for um objeto especial (ScreenGui), precisamos do arquivo placeholder dentro?
        -- Na versão anterior removemos para limpar. Mantemos assim.
        
        -- Nota: Se o objeto tiver atributos/tags importantes, não salvar o arquivo pai 
        -- significa perder esses dados na visualização.
        -- Mas para visualização de código, tá limpo assim.

        for _, child in ipairs(children) do
            ProcessNode(child, newPath)
        end
    else
        WriteItem(instance, currentPath)
    end
end

-- 6. RODAR
local parsedFile = fs.readFile(inputFileName)
local game = roblox.deserializePlace(parsedFile)

local Services = {"ReplicatedFirst", "ReplicatedStorage", "ServerScriptService", "ServerStorage", "StarterGui", "StarterPack", "StarterPlayer", "Workspace"}

for _, sName in ipairs(Services) do
    local service = game:GetService(sName)
    if service then
        print("📦 Exportando " .. sName)
        local sPath = outputFolder .. "/" .. sName
        fs.writeDir(sPath)
        for _, child in ipairs(service:GetChildren()) do
            ProcessNode(child, sPath)
        end
    end
end

print("✅ Exportação (Sem .folder redundante) Concluída!")