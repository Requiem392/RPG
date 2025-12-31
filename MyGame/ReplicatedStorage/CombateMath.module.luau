local CombateMath = {}

-- Configurações
local ZONA_MORTA = 50 -- Tamanho do centro (para a Bolinha/Estocada)

function CombateMath.CalcularPostura(mousePos, centroTela)
	local vetor = mousePos - centroTela

	-- 1. DETECÇÃO DO CENTRO (ESTOCADA)
	if vetor.Magnitude < ZONA_MORTA then
		return "Bolinha"
	end

	-- 2. CÁLCULO DO ÂNGULO (0 a 360 graus)
	-- 0 é Direita, 90 é Cima, 180 é Esquerda, 270 é Baixo
	local angulo = math.deg(math.atan2(-vetor.Y, vetor.X))
	if angulo < 0 then angulo = angulo + 360 end

	-- === MAPEAMENTO DAS 5 PONTAS ===
	-- Fatias de 72 graus cada

	-- Ponta 1 (Cima): De 54° a 126°
	if angulo >= 54 and angulo < 126 then
		return "Ponta1"

		-- Ponta 2 (Cima Esquerda): De 126° a 198°
	elseif angulo >= 126 and angulo < 198 then
		return "Ponta2"

		-- Ponta 5 (Baixo Esquerda): De 198° a 270°
	elseif angulo >= 198 and angulo < 270 then
		return "Ponta5"

		-- Ponta 4 (Baixo Direita): De 270° a 342°
	elseif angulo >= 270 and angulo < 342 then
		return "Ponta4"

		-- Ponta 3 (Cima Direita): O que sobrou (342° a 360° E 0° a 54°)
	else
		return "Ponta3"
	end
end

return CombateMath