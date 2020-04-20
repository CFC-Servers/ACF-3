local Weapons = ACF.Classes.Weapons

function EFFECT:Init(Data)
	local Gun = Data:GetEntity()

	if not IsValid(Gun) then return end

	local Propellant = Data:GetScale()
	local ReloadTime = Data:GetMagnitude()
	local Sound = Gun:GetNWString("Sound")
	local Class = Gun:GetNWString("Class")
	local ClassData = Weapons[Class]
	local Attachment = "muzzle"
	local LongBarrel = ClassData.LongBarrel

	if LongBarrel and Gun:GetBodygroup(LongBarrel.Index) == LongBarrel.Submodel then
		Attachment = LongBarrel.NewPos
	end

	if not IsValidSound(Sound) then
		Sound = ClassData.Sound
	end

	if Propellant > 0 then
		local GunPos = Gun:GetPos()

		if Sound ~= "" then
			local SoundPressure = (Propellant * 1000) ^ 0.5

			sound.Play(Sound, GunPos, math.Clamp(SoundPressure, 75, 127), 100) --wiki documents level tops out at 180, but seems to fall off past 127

			if not (Class == "MG" or Class == "RAC") then
				sound.Play(Sound, GunPos, math.Clamp(SoundPressure, 75, 127), 100)

				if SoundPressure > 127 then
					sound.Play(Sound, GunPos, math.Clamp(SoundPressure - 127, 1, 127), 100)
				end
			end
		end

		local Effect = ClassData.MuzzleFlash
		local AttachID = Gun:LookupAttachment(Attachment)

		if AttachID > 0 then
			ParticleEffectAttach(Effect, PATTACH_POINT_FOLLOW, Gun, AttachID)
		else
			ParticleEffect(Effect, GunPos, Gun:GetAngles(), Gun)
		end

		Gun:Animate(ReloadTime, false)
	else
		Gun:Animate(ReloadTime, true)
	end
end

function EFFECT:Think()
	return false
end

function EFFECT:Render()
end