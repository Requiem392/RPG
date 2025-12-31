local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- Ajuste o tempo de espera ou remova se estiver dando erro de timeout
local AssetsFolder = ReplicatedStorage:FindFirstChild("AssetsItems") 

local ItemDataModule = {}

-- ============================================================================
-- TABELA DE ANIMAÇÕES (Seus IDs aqui)
-- ============================================================================
local CaladbolgAnims = {
	Reach   = "rbxassetid://119051669592142",  -- Mão indo buscar nas costas
	Equip   = "rbxassetid://73645844171878",   -- Sacando (Pull)

	-- Você pediu para deixar nil por enquanto:
	Idle    = nil, -- "rbxassetid://129922265401211"

	Unequip = "rbxassetid://136686216344450"   -- Guardando
}

-- ============================================================================
-- BANCO DE DADOS
-- ============================================================================
local Database = {

	["Weapons"] = {
		["Caladbolg"] = {
			Name = "Caladbolg",
			Type = "Weapon",
			Damage = 50,
			Description = "A espada lendária.",
			Rarity = "Legendary",

			Model = AssetsFolder and AssetsFolder:FindFirstChild("Caladbolg"), 
			Icon = "rbxassetid://123456789", 
			MaxStack = 1,
			Weight = 5,

			-- >>> AQUI LIGAMOS AS ANIMAÇÕES <<<
			SheathPart = "Torso", -- Define que ela guarda nas costas
			Animations = CaladbolgAnims
		},

		["Espada de Ferro"] = {
			Name = "Espada de Ferro",
			Type = "Weapon",
			Model = nil, -- Sem modelo por enquanto
			Icon = "rbxassetid://0",
			MaxStack = 1
		}
	},

	["Consumables"] = {
		["Poção de Cura"] = {
			Name = "Poção de Cura",
			Type = "Consumable",
			HealAmount = 25,
			Description = "Restaura vida.",
			Model = nil, 
			Icon = "rbxassetid://987654321",
			MaxStack = 5,
			Weight = 0.5
		}
	}
}

-- ============================================================================
-- FUNÇÃO DE BUSCA (.Get)
-- ============================================================================
function ItemDataModule.Get(itemName)
	if not itemName then return nil end

	for categoryName, items in pairs(Database) do
		if items[itemName] then
			return items[itemName]
		end
	end

	return nil
end

return ItemDataModule