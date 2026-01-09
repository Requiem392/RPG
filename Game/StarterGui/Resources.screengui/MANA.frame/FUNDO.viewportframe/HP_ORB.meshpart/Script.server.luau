local TweenService = game:GetService("TweenService")

local Part = script.Parent

local Speed = 300
local Info = TweenInfo.new(Speed, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1, false, 0)

for _, texture in Part:GetDescendants() do
	if texture:IsA("Texture") then
		local Tween = TweenService:Create(texture, Info, {OffsetStudsU = 50})
		local Tween2 = TweenService:Create(texture, Info, {OffsetStudsV = 50})

		Tween:Play()
		Tween2:Play()

	end 
end