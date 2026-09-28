-- The npc feature's controller. It owns one foundation.npc Npc per NPC
-- entity, the foundation.npc.spawner models, a registry by kind and the
-- per-variant shared state, and checks the navigation mesh once per map.
-- The rules live in the models; this file only feeds them engine events and
-- turns their answers into entities.
local NpcSystem = WETSAND.require("foundation.npc")
local Spawner = WETSAND.require("foundation.npc.spawner")

local NAV_MESSAGE = "wetsand_nextbot: %s has no usable navigation mesh; run .devtools/bin/nav_convert.py or nav_generate"
local BOSS_HEALTH = "wetsand_boss_health" -- the boss bar's fraction; 0 hides it

local Controller = {
	npcs = {}, -- entity -> Npc
	variantNames = {}, -- entity -> variant name
	kinds = {}, -- kind -> { [entity] = true }
	shared = {}, -- variant name -> table
	spawners = {}, -- spawner entity -> Spawner
	spawnedBy = {}, -- NPC entity -> Spawner
	navChecked = false,
}

function Controller:CheckNavMesh()
	if self.navChecked then return end
	self.navChecked = true
	if not navmesh.IsLoaded() or navmesh.GetNavAreaCount() == 0 then
		print(string.format(NAV_MESSAGE, game.GetMap()))
	end
end

-- The NPCs bound to one variant, oldest first.
function Controller:NpcsOf(variantName)
	local found = {}
	for ent, name in pairs(self.variantNames) do
		if name == variantName then found[#found + 1] = ent end
	end
	table.sort(found, function(a, b) return a:GetCreationID() < b:GetCreationID() end)
	local npcs = {}
	for i, ent in ipairs(found) do npcs[i] = self.npcs[ent] end
	return npcs
end

function Controller:Bind(ent, variantName, config)
	self:CheckNavMesh()
	local variant = WETSAND.require(variantName)
	local npc = NpcSystem.Npc.New(variant, config, ent)
	self.npcs[ent] = npc
	self.variantNames[ent] = variantName
	self.kinds[variant.KIND] = self.kinds[variant.KIND] or {}
	self.kinds[variant.KIND][ent] = true
	NpcSystem.Cull(variant, self:NpcsOf(variantName))
	return npc
end

function Controller:Unbind(ent)
	local npc = self.npcs[ent]
	npc:Destroy()
	self.kinds[npc.variant.KIND][ent] = nil
	self.npcs[ent] = nil
	self.variantNames[ent] = nil
	local spawner = self.spawnedBy[ent]
	if spawner then
		spawner:Died(ent)
		self.spawnedBy[ent] = nil
	end
end

function Controller:All(kind)
	local found = {}
	for ent in pairs(self.kinds[kind] or {}) do found[#found + 1] = ent end
	return found
end

function Controller:Shared(variantName)
	self.shared[variantName] = self.shared[variantName] or {}
	return self.shared[variantName]
end

-- Every spawnable class of this gamemode takes its config through Configure.
function Controller:Spawn(class, config, pos, ang)
	local ent = ents.Create(class)
	ent:Configure(config)
	ent:SetPos(pos)
	ent:SetAngles(ang)
	ent:Spawn()
	return ent
end

function Controller:SetBossHealth(fraction)
	SetGlobal2Float(BOSS_HEALTH, fraction)
end

function Controller:BindSpawner(ent, config)
	local spawner = Spawner.New(config)
	self.spawners[ent] = spawner
	return spawner
end

-- Spawn at the spawner's origin whatever the models ask for. A spawner the
-- map removed is forgotten.
function Controller:ThinkSpawners(now)
	for ent, spawner in pairs(self.spawners) do
		if not IsValid(ent) then
			self.spawners[ent] = nil
		else
			local request = spawner:Think(now, math.Rand)
			if request then
				local npc = self:Spawn(request.class, request.config, ent:GetPos(), ent:GetAngles())
				spawner:Spawned(npc)
				self.spawnedBy[npc] = spawner
			end
		end
	end
end

hook.Add("Think", "wetsand_npc_spawners", function()
	Controller:ThinkSpawners(CurTime())
end)

-- The model's FilterDamage decides what an NPC takes.
hook.Add("EntityTakeDamage", "wetsand_npc_filter_damage", function(ent, dmg)
	local npc = Controller.npcs[ent]
	if npc and not npc:FilterDamage(ent:DamageEvent(dmg)) then return true end
end)

return Controller
