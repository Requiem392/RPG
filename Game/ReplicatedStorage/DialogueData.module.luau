local DialogueData = {}

-- === BIBLIOTECA DE EXPRESSÕES (Seus IDs organizados) ===
local Faces = {
	Preocupado  = 76774137736593,
	Preocupado2 = 102062479307110,
	Angry       = 136587912998408,
	Angry2      = 108202422228477,
	Duvida      = 95690305974532,
	Evil        = 74184733207706,
	Falando     = 84993627960380,
	Smile       = 75854250903097,
	Smile2      = 78507650614070,
}

-- === SEUS DIÁLOGOS ===

DialogueData["Guardiao_Inicio"] = {
	Text = "Olá viajante. A floresta está perigosa.",
	-- Agora você usa a tabela 'Faces' aqui:
	FaceAnimId = Faces.Preocupado, 

	SoundId = 89536729288428,
	BodyAnimId = 507766388, -- Exemplo de corpo

	Responses = {
		{
			Text = "Eu não tenho medo.",
			NextID = "Guardiao_Missao",
		},
		{
			Text = "Tchau.",
			NextID = "EXIT"
		}
	}
}

DialogueData["Guardiao_Missao"] = {
	Text = "Corajoso... Mas você é forte o suficiente?",
	FaceAnimId = Faces.Duvida, -- Olha como fica fácil trocar!

	Requirements = {
		{Type = "Level", Value = 5},
	},

	Responses = {
		{
			Text = "Eu sou forte! (Aceitar Missão)",
			NextID = "Guardiao_Aceitou",
			Action = {Type = "StartQuest", Value = "MatarLobos"} 
		},
		{
			Text = "Vou treinar mais.",
			NextID = "EXIT"
		}
	},

	FailText = "Volte quando for nível 5."
}

DialogueData["Guardiao_Aceitou"] = {
	Text = "Ótimo! Mate 10 Lobos e volte aqui.",
	FaceAnimId = Faces.Smile, -- Usando o sorriso

	Responses = {
		{Text = "Pode deixar!", NextID = "EXIT"}
	}
}

return DialogueData