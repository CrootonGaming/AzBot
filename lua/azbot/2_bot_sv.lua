
return function(lib)
	lib.IsEnabled = engine.ActiveGamemode() == "zombiesurvival"
	lib.BotPosMilestoneUpdateDelay = 25
	lib.BotPosMilestoneDistMin = 200
	lib.BotTgtFixationDistMin = 250
	lib.BotTgtAreaRadius = 100
	lib.BotSeeTr = {
		mins = Vector(-15, -15, -15),
		maxs = Vector(15, 15, 15),
		mask = MASK_PLAYERSOLID }
	lib.BotAttackDistMin = 100
	lib.BotMinSpdFactor = 0.75
	lib.BotAngOffshoot = 45
	lib.BotAdditionalAngOffshoot = 30
	lib.BotAngLerpFactor = 0.25
	lib.BotAimPosVelocityOffshoot = 0.2
	lib.BotJumpAntichance = 25
	lib.MaintainBotRolesAutomatically = table.Count(lib.MapNavMesh.ItemById) > 0
	lib.IsSelfRedeemEnabled = lib.MaintainBotRolesAutomatically
	lib.SelfRedeemWaveMax = 4
	lib.BotHooksId = tostring({})
	lib.BotClasses = { "Zombie", "Zombie", "Ghoul", "Bloated Zombie", "Bloated Zombie", "Scratcher", "Poison Zombie", "Poison Zombie", "Zombine", "Zombine" }
	
	hook.Add("PlayerInitialSpawn", lib.BotHooksId, function(pl) if lib.IsEnabled and pl:IsBot() then lib.InitializeBot(pl) end end)
	hook.Add("PlayerSpawn", lib.BotHooksId, function(pl)
		if not lib.IsEnabled then return end
		if pl:IsBot() then lib.SetUpBot(pl) end
		if lib.MaintainBotRolesAutomatically then lib.MaintainBotRoles() end
	end)
	hook.Add("EntityRemoved", lib.BotHooksId, function(ent) if lib.IsEnabled and lib.MaintainBotRolesAutomatically and ent:IsPlayer() then timer.Simple(0, lib.MaintainBotRoles) end end)
	hook.Add("StartCommand", lib.BotHooksId, function(pl, cmd) if lib.IsEnabled and pl:IsBot() then lib.UpdateBotCmd(pl, cmd) end end)
	hook.Add("EntityTakeDamage", lib.BotHooksId, function(ent, dmg) if lib.IsEnabled and ent:IsPlayer() and ent:IsBot() then lib.HandleBotDamage(ent, dmg) end end)
	
	lib.MemByBot = {}
	local memByBot = lib.MemByBot
	
	function lib.GetBotAttackPosOrNil(bot)
		local tgt = memByBot[bot].TgtOrNil
		if not IsValid(tgt) then return end
		return tgt:IsPlayer() and LerpVector(0.75, tgt:GetPos(), tgt:EyePos()) or tgt:WorldSpaceCenter()
	end
	
	function lib.CanBotSeeTarget(bot)
		local attackPos = lib.GetBotAttackPosOrNil(bot)
		if not attackPos then return false end
		local mem = memByBot[bot]
		if mem.TgtNodeOrNil and mem.NodeOrNil ~= mem.TgtNodeOrNil and mem.TgtNodeOrNil.Params.nosee == 1 then return false end
		local tr = lib.BotSeeTr
		tr.start = lib.GetViewCenter(bot)
		tr.endpos = attackPos
		tr.filter = player.GetAll()
		return attackPos and not util.TraceHull(tr).Hit
	end
	
	function lib.BotFace(bot, pos)
		local mem = memByBot[bot]
		mem.Angs = LerpAngle(lib.BotAngLerpFactor, mem.Angs, (pos - lib.GetViewCenter(bot)):Angle() + mem.AngsOffshoot)
	end
	
	function lib.RerollBotClass(bot)
		if not GAMEMODE:GetWaveActive() then return end
		local classId = table.Random(lib.BotClasses)
		local class = GAMEMODE.ZombieClasses[classId]
		if not class then
			table.RemoveByValue(lib.BotClasses, classId)
			lib.RerollBotClass(bot)
			return
		end
		if class.Wave > GAMEMODE:GetWave() then class = GAMEMODE.ZombieClasses.Zombie end
		bot:SetZombieClass(class.Index)
	end
	
	function lib.GetDesiredZombiesCount() return math.ceil(#player.GetHumans() * GAMEMODE.WaveOneZombies * math.max(1, GAMEMODE:GetWave())) end
	
	function lib.MaintainBotRoles()
		local desiredZombiesCount = lib.GetDesiredZombiesCount()
		local zombiesCount = #team.GetPlayers(TEAM_UNDEAD)
		while zombiesCount < desiredZombiesCount do
			RunConsoleCommand("bot")
			if lib.MaintainBotRolesAutomatically then return end -- unavoidably loops by itself in this case
			zombiesCount = zombiesCount + 1
		end
		for idx, bot in ipairs(player.GetBots()) do
			if bot:Team() == TEAM_UNDEAD then
				if zombiesCount > desiredZombiesCount then
					bot:Kick()
					zombiesCount = zombiesCount - 1
				end
			else
				bot:Kick()
			end
		end
	end
	
	function lib.InitializeBot(bot)
		if lib.MaintainBotRolesAutomatically then
			GAMEMODE.PreviouslyDied[bot:UniqueID()] = CurTime()
			GAMEMODE:PlayerInitialSpawn(bot)
		end
		
		memByBot[bot] = {
			PosMilestone = Vector(),
			NextPosMilestoneTime = 0,
			NextFailPosMilestone = function() end,
			TgtOrNil = nil,
			TgtNodeOrNil = nil,
			NodeOrNil = nil,
			NextNodeOrNil = nil,
			RemainingNodes = {},
			Spd = 0,
			Angs = Angle(),
			AngOffshoot = 0,
			AngsOffshoot = Angle(),
			NextSlowThinkTime = 0,
			ButtonsToBeClicked = 0 }
	end
	
	function lib.SetUpBot(bot)
		local mem = memByBot[bot]
		lib.ResetBotPosMilestone(bot)
		mem.TgtOrNil = nil
		mem.NextNodeOrNil = nil
		mem.RemainingNodes = {}
		mem.Angs = bot:EyeAngles()
		mem.NextSlowThinkTime = 0
		
		lib.RerollBotClass(bot)
	end
	
	function lib.ResetBotPosMilestone(bot)
		lib.SetBotPosMilestone(bot)
		memByBot[bot].NextFailPosMilestone = lib.FailFirstPosMilestone
	end
	function lib.UpdateBotPosMilestone(bot)
		local mem = memByBot[bot]
		if mem.NextPosMilestoneTime > CurTime() then return end
		local failed = bot:GetPos():Distance(mem.PosMilestone) < lib.BotPosMilestoneDistMin
		lib.SetBotPosMilestone(bot)
		if failed then mem.NextFailPosMilestone(bot) end
	end
	function lib.SetBotPosMilestone(bot)
		local mem = memByBot[bot]
		mem.PosMilestone = bot:GetPos()
		mem.NextPosMilestoneTime = CurTime() + lib.BotPosMilestoneUpdateDelay - math.random(0, math.floor(lib.BotPosMilestoneUpdateDelay * 0.5))
	end
	function lib.FailFirstPosMilestone(bot)
		local mem = memByBot[bot]
		lib.ResetBotTgtOrNil(bot)
		mem.NextFailPosMilestone = lib.FailSecondPosMilestone
		mem.ButtonsToBeClicked = bit.bor(mem.ButtonsToBeClicked, IN_JUMP)
	end
	function lib.FailSecondPosMilestone(bot)
		bot:Kill()
		lib.ResetBotPosMilestone(bot)
	end
	
	function lib.GetPotentialBotTgts(bot) return team.GetPlayers(TEAM_HUMAN) end
	function lib.ResetBotTgtOrNil(bot) memByBot[bot].TgtOrNil = table.Random(lib.GetPotentialBotTgts(bot)) end
	function lib.UpdateBotTgtOrNil(bot) if not lib.CanBeBotTgt(memByBot[bot].TgtOrNil) then lib.ResetBotTgtOrNil(bot) end end
	function lib.CanBeBotTgt(tgtOrNil) return IsValid(tgtOrNil) and tgtOrNil:IsPlayer() and tgtOrNil:Team() == TEAM_HUMAN end
	
	function lib.UpdateBotTgtProximity(bot)
		local mem = memByBot[bot]
		local inverseFactor = IsValid(mem.TgtOrNil) and math.min(1, bot:GetPos():Distance(mem.TgtOrNil:GetPos()) / lib.BotTgtAreaRadius) or 1
		mem.Spd = bot:GetMaxSpeed() * (lib.BotMinSpdFactor + (1 - lib.BotMinSpdFactor) * inverseFactor)
		mem.AngOffshoot = lib.BotAngOffshoot + lib.BotAdditionalAngOffshoot * (1 - inverseFactor)
	end
	
	function lib.UpdateBotAngsOffshoot(bot)
		local mem = memByBot[bot]
		local angOffshoot = mem.AngOffshoot
		mem.AngsOffshoot = Angle(math.random(-angOffshoot, angOffshoot), math.random(-angOffshoot, angOffshoot), 0)
	end
	
	function lib.UpdateBotPath(bot)
		local mem = memByBot[bot]
		if not IsValid(mem.TgtOrNil) then return end
		local mapNavMesh = lib.MapNavMesh
		local node = mapNavMesh:GetNearestNodeOrNil(bot:GetPos())
		mem.TgtNodeOrNil = mapNavMesh:GetNearestNodeOrNil(mem.TgtOrNil:GetPos())
		if not node or not mem.TgtNodeOrNil then return end
		local path = lib.GetBestMeshPathOrNil(node, mem.TgtNodeOrNil)
		if not path then return end
		mem.NodeOrNil = table.remove(path, 1)
		mem.NextNodeOrNil = table.remove(path, 1)
		mem.RemainingNodes = path
	end
	
	function lib.UpdateBotPathProgress(bot)
		local mem = memByBot[bot]
		while mem.NextNodeOrNil do
			if mem.NextNodeOrNil:GetContains(bot:GetPos()) then
				mem.NodeOrNil = mem.NextNodeOrNil
				mem.NextNodeOrNil = table.remove(mem.RemainingNodes, 1)
			else
				break
			end
		end
	end
	
	function lib.UpdateBotMem(bot)
		local mem = memByBot[bot]
		lib.UpdateBotPosMilestone(bot)
		lib.UpdateBotTgtOrNil(bot)
		lib.UpdateBotTgtProximity(bot)
		if mem.NextSlowThinkTime <= CurTime() then
			mem.NextSlowThinkTime = CurTime() + 0.5
			lib.UpdateBotAngsOffshoot(bot)
			lib.UpdateBotPath(bot)
		end
		lib.UpdateBotPathProgress(bot)
	end
	
	function lib.UpdateBotCmd(bot, cmd)
		cmd:ClearButtons()
		cmd:ClearMovement()
		
		if bot:Team() ~= TEAM_UNDEAD then return end
		
		if not bot:Alive() then
			cmd:SetButtons(IN_ATTACK)
			return
		end
		
		lib.UpdateBotMem(bot)
		local mem = memByBot[bot]
		
		local facesTgt = false
		local facesHindrance = bot:GetVelocity():Length2D() < 0.25 * bot:GetMaxSpeed()
		
		local aimPos
		if mem.NextNodeOrNil and not lib.CanBotSeeTarget(bot) then
			aimPos = mem.NextNodeOrNil.Pos
		elseif IsValid(mem.TgtOrNil) then
			aimPos = lib.GetBotAttackPosOrNil(bot) + mem.TgtOrNil:GetVelocity() * math.Rand(0, lib.BotAimPosVelocityOffshoot)
			facesTgt = aimPos:Distance(lib.GetViewCenter(bot)) < lib.BotAttackDistMin
		else
			return
		end
		
		lib.BotFace(bot, aimPos)
		cmd:SetViewAngles(mem.Angs)
		
		cmd:SetForwardMove(mem.Spd)
		
		local ternaryButton = 0
		if bot:GetMoveType() ~= MOVETYPE_LADDER then
			if bot:IsOnGround() then
				if facesHindrance then ternaryButton = math.random(lib.BotJumpAntichance) == 1 and IN_JUMP or IN_DUCK end
			else
				ternaryButton = IN_DUCK
			end
		end
		
		cmd:SetButtons(bit.bor(IN_FORWARD, (facesTgt or facesHindrance) and IN_ATTACK or 0, ternaryButton, facesHindrance and IN_USE or 0, mem.ButtonsToBeClicked))
		mem.ButtonsToBeClicked = 0
	end
	
	function lib.HandleBotDamage(bot, dmg)
		local attacker = dmg:GetAttacker()
		if not lib.CanBeBotTgt(attacker) then return end
		local mem = memByBot[bot]
		if IsValid(mem.TgtOrNil) and mem.TgtOrNil:GetPos():Distance(bot:GetPos()) <= lib.BotTgtFixationDistMin then return end
		mem.TgtOrNil = attacker
		lib.ResetBotPosMilestone(bot)
	end
end