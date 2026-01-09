local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- Ajuste o tempo de espera ou remova se estiver dando erro de timeout
local AssetsFolder = ReplicatedStorage:FindFirstChild("AssetsItems") 

local ItemDataModule = {}

-- ============================================================================
-- CATEGORIAS DE ARMAS (TEMPLATES COMPARTILHADOS)
-- ============================================================================
--[[
	🔄 QUANDO SEPARAR EM MÓDULO PRÓPRIO:
	- Se outros sistemas (crafting, skills, AI) precisarem das categorias
	- Se categorias tiverem lógica complexa (cálculos, validações)
	- Se houver mais de ~10 categorias diferentes
	
	Por enquanto, mantemos aqui para simplicidade!
]]

local WeaponCategories = {

	-- HEAVY WEAPON (Espadas Grandes/Pesadas - ex: Greatsword, Claymore)
	HeavyWeapon = {
		DisplayName = "Arma Pesada",
		ComboLength = 2,

		-- Stats de Combate e Postura
		Stats = {
			Damage = 35,
			PostureDamage = 25,  -- Dano de postura ao atacar/bloquear
			PostureNegate = 15,  -- Redução de dano de postura ao bloquear
		},

		Animations = {
			SwingLeft = "rbxassetid://75406890171293",
			SwingRight = "rbxassetid://97517518003597",
			Idle = "rbxassetid://71610929210165",
			Heavy = "rbxassetid://72139529414343",
			-- Animações de equipar padrão para HeavyWeapon
			Equip = "rbxassetid://119831656985522",
			Unequip = "rbxassetid://136686216344450",
			-- Animação de bloqueio
			Block = "rbxassetid://113888485536528",
			-- Animação de parry (universal)
			Parry = "rbxassetid://114806520233993",
		},

		-- IDs de Sons
		Sounds = {
			Swing = "rbxassetid://135315310485417",
			Hit = "rbxassetid://137628815514180",
			Block = "rbxassetid://5763723309",
			Parry = "rbxassetid://75099255490892",
			Dodge = "rbxassetid://124996690866303"
		},

		TrailDuration = 0.3,
		AttackSpeed = 1.0,
	},

	-- MEDIUM WEAPON (Espadas de Uma Mão - ex: Longsword, Katana)
	MediumWeapon = {
		DisplayName = "Arma Média",
		ComboLength = 2,

		Stats = {
			Damage = 25,
			PostureDamage = 17,
			PostureNegate = 11,
		},

		Animations = {
			SwingLeft = "rbxassetid://105911031536493",
			SwingRight = "rbxassetid://128804792118469",
			Idle = "rbxassetid://123669113436345",
			-- Animações de equipar padrão para MediumWeapon
			Equip = "rbxassetid://100436962634733",
			Unequip = "rbxassetid://93230274528603",
			-- Animação de bloqueio
			Block = "rbxassetid://133621995179435",
			-- Animação de parry (universal)
			Parry = "rbxassetid://114806520233993",
		},

		Sounds = {
			Swing = "rbxassetid://135315310485417",
			Hit = "rbxassetid://137628815514180",
			Block = "rbxassetid://5763723309",
			Parry = "rbxassetid://75099255490892",
			Dodge = "rbxassetid://124996690866303"
		},

		TrailDuration = 0.25,
		AttackSpeed = 1.2,
	},

	-- LIGHT WEAPON (Armas Leves/Rápidas - ex: Dagger, Short Sword)
	LightWeapon = {
		DisplayName = "Arma Leve",
		ComboLength = 2,

		Stats = {
			Damage = 15,
			PostureDamage = 10,
			PostureNegate = 6,
		},

		Animations = {
			SwingLeft = "rbxassetid://131239887438855",
			SwingRight = "rbxassetid://131542861989792",
			Idle = "rbxassetid://139892978812925",
			-- Animações de equipar padrão para LightWeapon
			Equip = "rbxassetid://102493269480640",
			Unequip = "rbxassetid://87276938060443",
			-- Animação de bloqueio
			Block = "rbxassetid://102396670999858",
			-- Animação de parry (universal)
			Parry = "rbxassetid://114806520233993",
		},

		Sounds = {
			Swing = "rbxassetid://135315310485417",
			Hit = "rbxassetid://137628815514180",
			Block = "rbxassetid://5763723309",
			Parry = "rbxassetid://75099255490892",
			Dodge = "rbxassetid://124996690866303"
		},

		TrailDuration = 0.2,
		AttackSpeed = 1.5,
	},
}

-- ============================================================================
-- BANCO DE DADOS
-- ============================================================================
local Database = {

	["Weapons"] = {
		["Caladbolg"] = {
			Name = "Caladbolg",
			Type = "Weapon",
			SlotType = "Weapon",
			WeaponCategory = "HeavyWeapon",

			Damage = 50,
			Description = "A espada lendária.",
			Rarity = "Legendary",

			Model = AssetsFolder and AssetsFolder:FindFirstChild("HeavyWeapons") and AssetsFolder.HeavyWeapons:FindFirstChild("Caladbolg"), 
			Icon = "rbxassetid://123456789", 
			MaxStack = 1,
			Weight = 5,

			TrailEnabled = true,
			SheathPart = "Torso"
			-- Sem Animations = usa 100% de HeavyWeapon
		},

		["Espada de Ferro"] = {
			Name = "Espada de Ferro",
			Type = "Weapon",
			SlotType = "Weapon",
			Damage = 25,

			WeaponCategory = "Sword",
			TrailEnabled = false,

			Model = nil,
			Icon = "rbxassetid://0",
			MaxStack = 1
		},

		-- MEDIUM WEAPON
		["Sword"] = {
			Name = "Sword",
			Type = "Weapon",
			SlotType = "Weapon",
			WeaponCategory = "MediumWeapon",

			Damage = 35,
			Description = "Uma espada balanceada de uma mão.",
			Rarity = "Common",

			Model = AssetsFolder and AssetsFolder:FindFirstChild("MediumWeapons") and AssetsFolder.MediumWeapons:FindFirstChild("Sword"),
			Icon = "rbxassetid://0",
			MaxStack = 1,
			Weight = 3,

			TrailEnabled = true,
			SheathPart = "Torso"
		},

		-- LIGHT WEAPON
		["Dagger"] = {
			Name = "Dagger",
			Type = "Weapon",
			SlotType = "Weapon",
			WeaponCategory = "LightWeapon",

			Damage = 20,
			Description = "Uma adaga rápida e letal.",
			Rarity = "Common",

			Model = AssetsFolder and AssetsFolder:FindFirstChild("LightWeapons") and AssetsFolder.LightWeapons:FindFirstChild("Dagger"),
			Icon = "rbxassetid://0",
			MaxStack = 1,
			Weight = 1,

			TrailEnabled = false,
			SheathPart = "Torso"
		}
	},

	["Armor"] = {
		["Armadura de Ferro"] = {
			Name = "Armadura de Ferro",
			Type = "Equipment",
			SlotType = "Armor",
			Defense = 10,
			Description = "Armadura básica.",
			Model = nil,
			Icon = "rbxassetid://0",
			MaxStack = 1
		},
		["Capacete de Ferro"] = {
			Name = "Capacete de Ferro",
			Type = "Equipment",
			SlotType = "Helm",
			Defense = 5,
			Description = "Capacete básico.",
			Model = nil,
			Icon = "rbxassetid://0",
			MaxStack = 1
		}
	},

	["Consumables"] = {
		["Poção de Cura"] = {
			Name = "Poção de Cura",
			Type = "Consumable",
			-- Sem SlotType pois não equipa em slots específicos
			HealAmount = 25,
			Description = "Restaura vida.",
			Model = nil, 
			Icon = "rbxassetid://987654321",
			Stackable = true,
			MaxStack = 64,
			Weight = 0.5
		}
	}
}

-- ============================================================================
-- FUNÇÕES DE ACESSO
-- ============================================================================

-- Retorna dados de uma categoria específica
function ItemDataModule.GetCategory(categoryName)
	return WeaponCategories[categoryName]
end

-- Retorna o ID de som de uma categoria
function ItemDataModule.GetCategorySound(categoryName, soundType)
	local category = WeaponCategories[categoryName]
	if not category then return nil end

	return category.Sounds and category.Sounds[soundType]
end

-- Retorna animação de combo de uma categoria
function ItemDataModule.GetCategoryAnimation(categoryName, comboStep)
	local category = WeaponCategories[categoryName]
	if not category then return nil end

	local animName = "Swing" .. comboStep
	return category.Animations and category.Animations[animName]
end

-- Lista todas as categorias disponíveis
function ItemDataModule.GetAllCategories()
	local list = {}
	for name, _ in pairs(WeaponCategories) do
		table.insert(list, name)
	end
	return list
end

-- Busca um item no banco de dados
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