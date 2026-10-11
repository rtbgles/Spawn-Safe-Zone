if SERVER then
    AddCSLuaFile()
end

BoggleSafe = BoggleSafe or {}

local ZONE_CLASS = "ent_boggle_safezone"
local cache, cacheAt = {}, -1
local saveQueued = false
local cleaning = false

local function savePath()
    local map = string.gsub( string.lower( game.GetMap() or "map" ), "[^%w_%-]", "_" )
    return "boggle_safezone/" .. map .. ".json"
end

local function zoneList()
    local now = CurTime()
    if now - cacheAt > 0.25 then
        cache = ents.FindByClass( ZONE_CLASS )
        cacheAt = now
    end
    return cache
end

function BoggleSafe.Invalidate()
    cacheAt = -1
end

function BoggleSafe.FindAt( pos, pad )
    if not pos then
        return nil
    end
    local list = zoneList()
    for i = 1, #list do
        local zone = list[i]
        if IsValid( zone ) and zone.Contains and zone:Contains( pos, pad ) then
            return zone
        end
    end
end

function BoggleSafe.Nearest( pos, maxDist )
    local best, bestD
    local cap = ( maxDist or 128 ) ^ 2
    local list = zoneList()
    for i = 1, #list do
        local zone = list[i]
        if IsValid( zone ) and zone.NearestDistSqr then
            local d = zone:NearestDistSqr( pos )
            if d <= cap and ( not bestD or d < bestD ) then
                best, bestD = zone, d
            end
        end
    end
    return best
end

local function isNpcLike( ent )
    if not IsValid( ent ) then
        return false
    end
    if ent:IsNPC() then
        return true
    end
    if isfunction( ent.IsNextBot ) and ent:IsNextBot() then
        return true
    end
    local class = ent:GetClass() or ""
    if string.StartWith( class, "npc_" ) then
        return true
    end
    if string.find( class, "nextbot", 1, true ) then
        return true
    end
    return false
end

function BoggleSafe.Protects( ent )
    if not IsValid( ent ) then
        return false, nil
    end

    local pad = ent:IsPlayer() and 12 or 0
    local zone = BoggleSafe.FindAt( ent:WorldSpaceCenter(), pad )
    if not zone then
        zone = BoggleSafe.FindAt( ent:GetPos(), pad )
    end
    if not zone and ent:IsPlayer() then
        zone = BoggleSafe.FindAt( ent:EyePos(), pad )
        if not zone then
            zone = BoggleSafe.FindAt( ent:GetPos() + Vector( 0, 0, 36 ), pad )
        end
        if not zone and ent:InVehicle() then
            local veh = ent:GetVehicle()
            if IsValid( veh ) then
                zone = BoggleSafe.FindAt( veh:WorldSpaceCenter(), pad )
            end
        end
    end
    if not zone then
        return false, nil
    end

    if ent:IsPlayer() then
        return true, zone
    end

    if zone:GetProtectNPCs() and isNpcLike( ent ) then
        return true, zone
    end

    return false, zone
end

local function asActor( ent )
    if not IsValid( ent ) then
        return nil
    end
    if ent:IsPlayer() then
        return ent
    end
    if ent:IsWeapon() then
        local owner = ent:GetOwner()
        if IsValid( owner ) then
            return owner
        end
    end
    if isfunction( ent.GetDriver ) then
        local drv = ent:GetDriver()
        if IsValid( drv ) then
            return drv
        end
    end
    if isfunction( ent.GetOwner ) then
        local owner = ent:GetOwner()
        if IsValid( owner ) then
            return owner
        end
    end
    if isfunction( ent.GetPhysicsAttacker ) then
        local phys = ent:GetPhysicsAttacker()
        if IsValid( phys ) then
            return phys
        end
    end
    if isfunction( ent.CPPIGetOwner ) then
        local owner = ent:CPPIGetOwner()
        if IsValid( owner ) then
            return owner
        end
    end
    if IsValid( ent.Owner ) then
        return ent.Owner
    end
    return ent
end

local function damageOwner( dmg )
    if not dmg then
        return nil
    end
    return asActor( dmg:GetAttacker() ) or asActor( dmg:GetInflictor() )
end

local function zoneBlocking( ent )
    if not IsValid( ent ) then
        return nil
    end
    local pad = ent:IsPlayer() and 16 or 0
    local zone = BoggleSafe.FindAt( ent:WorldSpaceCenter(), pad ) or BoggleSafe.FindAt( ent:GetPos(), pad )
    if not zone and ent:IsPlayer() then
        zone = BoggleSafe.FindAt( ent:EyePos(), pad )
        if not zone then
            zone = BoggleSafe.FindAt( ent:GetPos() + Vector( 0, 0, 36 ), pad )
        end
    end
    return zone
end

local function outgoingBlocked( dmg, extra )
    local actor = damageOwner( dmg )
    if zoneBlocking( actor ) then
        return true
    end
    if zoneBlocking( extra ) then
        return true
    end
    if dmg then
        if zoneBlocking( dmg:GetAttacker() ) then
            return true
        end
        if zoneBlocking( dmg:GetInflictor() ) then
            return true
        end
    end
    return false
end

local function staffBypass( actor )
    return IsValid( actor ) and actor:IsPlayer() and actor:IsSuperAdmin()
end

local function stopDamage( dmg )
    if not dmg then
        return
    end
    dmg:SetDamage( 0 )
    dmg:SetDamageForce( vector_origin )
    dmg:SetDamageType( DMG_GENERIC )
end

if SERVER then
    hook.Add( "EntityTakeDamage", "BoggleSafe", function( target, dmg )
        if not IsValid( target ) or not dmg then
            return
        end

        local actor = damageOwner( dmg )
        if staffBypass( actor ) then
            return
        end

        if BoggleSafe.Protects( target ) then
            stopDamage( dmg )
            return true
        end

        if outgoingBlocked( dmg, actor ) then
            stopDamage( dmg )
            return true
        end
    end )

    hook.Add( "EntityFireBullets", "BoggleSafe", function( ent, data )
        if not IsValid( ent ) or not data then
            return
        end
        local actor = asActor( ent ) or ent
        if staffBypass( actor ) then
            return
        end
        if zoneBlocking( actor ) or zoneBlocking( ent ) then
            data.Damage = 0
            data.Force = 0
            data.Num = 0
            data.Callback = nil
            return true
        end
        local prev = data.Callback
        data.Callback = function( atk, tr, dmginfo )
            if tr and IsValid( tr.Entity ) and BoggleSafe.Protects( tr.Entity ) then
                if dmginfo then
                    stopDamage( dmginfo )
                end
                return
            end
            if isfunction( prev ) then
                return prev( atk, tr, dmginfo )
            end
        end
        return true
    end )

    hook.Add( "PlayerShouldTakeDamage", "BoggleSafe", function( ply, attacker )
        if staffBypass( attacker ) then
            return
        end
        if BoggleSafe.Protects( ply ) then
            return false
        end
        if zoneBlocking( attacker ) then
            return false
        end
    end )

    timer.Create( "BoggleSafe_God", 0.1, 0, function()
        for _, ply in ipairs( player.GetAll() ) do
            if not IsValid( ply ) then
                -- skip
            elseif BoggleSafe.Protects( ply ) then
                if not ply._BoggleSafeGod then
                    ply._BoggleSafeGod = true
                    ply:GodEnable()
                end
            elseif ply._BoggleSafeGod then
                ply._BoggleSafeGod = nil
                ply:GodDisable()
            end
        end
    end )

    hook.Add( "CanPlayerSuicide", "BoggleSafe", function( ply )
        if BoggleSafe.Protects( ply ) then
            return false
        end
    end )

    hook.Add( "ScalePlayerDamage", "BoggleSafe", function( ply, _, dmg )
        local actor = damageOwner( dmg )
        if staffBypass( actor ) then
            return
        end
        if BoggleSafe.Protects( ply ) or outgoingBlocked( dmg, actor ) then
            stopDamage( dmg )
            return true
        end
    end )

    hook.Add( "ScaleNPCDamage", "BoggleSafe", function( npc, _, dmg )
        local actor = damageOwner( dmg )
        if staffBypass( actor ) then
            return
        end
        if BoggleSafe.Protects( npc ) or outgoingBlocked( dmg, actor ) then
            stopDamage( dmg )
            return true
        end
    end )

    hook.Add( "CanProperty", "BoggleSafe", function( ply, property, ent )
        if not IsValid( ent ) or not ent.IsBoggleSafeZone then
            return
        end
        if not IsValid( ply ) or not ply:IsAdmin() then
            return false
        end
    end )

    hook.Add( "CanTool", "BoggleSafe", function( ply, tr, _tool )
        if not tr or not IsValid( tr.Entity ) or not tr.Entity.IsBoggleSafeZone then
            return
        end
        if not IsValid( ply ) or not ply:IsAdmin() then
            return false
        end
    end )

    hook.Add( "PhysgunPickup", "BoggleSafe", function( _ply, ent )
        if IsValid( ent ) and ent.IsBoggleSafeZone then
            return false
        end
    end )

    hook.Add( "GravGunPickupAllowed", "BoggleSafe", function( _ply, ent )
        if IsValid( ent ) and ent.IsBoggleSafeZone then
            return false
        end
    end )

    hook.Add( "AllowPlayerPickup", "BoggleSafe", function( _ply, ent )
        if IsValid( ent ) and ent.IsBoggleSafeZone then
            return false
        end
    end )

    hook.Add( "CanPlayerUnfreeze", "BoggleSafe", function( _ply, ent )
        if IsValid( ent ) and ent.IsBoggleSafeZone then
            return false
        end
    end )

    hook.Add( "OnEntityCreated", "BoggleSafe_Cache", function( ent )
        if IsValid( ent ) and ent.IsBoggleSafeZone then
            BoggleSafe.Invalidate()
        end
    end )

    hook.Add( "EntityRemoved", "BoggleSafe_Cache", function( ent )
        if IsValid( ent ) and ent.IsBoggleSafeZone then
            BoggleSafe.Invalidate()
        end
    end )

    hook.Add( "PlayerDisconnected", "BoggleSafe_Place", function( ply )
        if not IsValid( ply ) then
            return
        end
        ply.BoggleSafeA = nil
        if ply._BoggleSafeGod then
            ply._BoggleSafeGod = nil
            ply:GodDisable()
        end
    end )

    concommand.Add( "boggle_safe_debug", function( ply )
        if IsValid( ply ) and not ply:IsAdmin() then
            return
        end
        local who = IsValid( ply ) and ply or nil
        if not who then
            return
        end
        local zone = select( 2, BoggleSafe.Protects( who ) )
        local msg = string.format(
            "[Safe Zone] protected=%s pos=%s zones=%d god=%s",
            zone and "yes" or "no",
            tostring( who:GetPos() ),
            #ents.FindByClass( ZONE_CLASS ),
            who._BoggleSafeGod and "1" or "0"
        )
        who:ChatPrint( msg )
    end )

    BoggleSafe.Stored = BoggleSafe.Stored or {}

    local function rowKey( row )
        return string.format( "%.1f:%.1f:%.1f:%.1f:%.1f:%.1f",
            tonumber( row.ax ) or 0, tonumber( row.ay ) or 0, tonumber( row.az ) or 0,
            tonumber( row.bx ) or 0, tonumber( row.by ) or 0, tonumber( row.bz ) or 0 )
    end

    function BoggleSafe.Remember( zone )
        if not IsValid( zone ) or not zone.GetCornerA then
            return
        end
        if zone.GetPersist and not zone:GetPersist() then
            BoggleSafe.Forget( zone )
            return
        end
        local a, b = zone:GetCornerA(), zone:GetCornerB()
        local row = {
            ax = a.x, ay = a.y, az = a.z,
            bx = b.x, by = b.y, bz = b.z,
            outgoing = zone:GetBlockOutgoing() and true or false,
            npcs = zone:GetProtectNPCs() and true or false,
            persist = true
        }
        BoggleSafe.Stored[rowKey( row )] = row
        BoggleSafe.QueueSave()
    end

    function BoggleSafe.Forget( zone )
        if not IsValid( zone ) or not zone.GetCornerA then
            return
        end
        local a, b = zone:GetCornerA(), zone:GetCornerB()
        BoggleSafe.Stored[rowKey( {
            ax = a.x, ay = a.y, az = a.z,
            bx = b.x, by = b.y, bz = b.z
        } )] = nil
        BoggleSafe.QueueSave()
    end

    function BoggleSafe.QueueSave()
        if saveQueued then
            return
        end
        saveQueued = true
        timer.Create( "BoggleSafe_Save", 0.25, 1, function()
            saveQueued = false
            BoggleSafe.Save()
        end )
    end

    function BoggleSafe.Save()
        file.CreateDir( "boggle_safezone" )
        local rows = {}
        for _, row in pairs( BoggleSafe.Stored ) do
            rows[#rows + 1] = row
        end
        file.Write( savePath(), util.TableToJSON( rows, true ) or "[]" )
    end

    function BoggleSafe.Load()
        local path = savePath()
        if not file.Exists( path, "DATA" ) and file.Exists( "boggle_safezone/zones.json", "DATA" ) then
            path = "boggle_safezone/zones.json"
        end
        if file.Exists( path, "DATA" ) then
            local raw = file.Read( path, "DATA" ) or ""
            local rows = util.JSONToTable( raw )
            if istable( rows ) then
                BoggleSafe.Stored = {}
                for _, row in ipairs( rows ) do
                    if istable( row ) and row.ax then
                        row.persist = true
                        BoggleSafe.Stored[rowKey( row )] = row
                    end
                end
            end
        end
        cleaning = true
        for _, zone in ipairs( ents.FindByClass( ZONE_CLASS ) ) do
            if IsValid( zone ) then
                zone:Remove()
            end
        end
        cleaning = false
        for _, row in pairs( BoggleSafe.Stored ) do
            local zone = ents.Create( ZONE_CLASS )
            if IsValid( zone ) then
                local a = Vector( row.ax, row.ay, row.az )
                local b = Vector( row.bx, row.by, row.bz )
                zone:SetPos( ( a + b ) * 0.5 )
                zone:Spawn()
                zone:SetPersist( true )
                zone:SetBlockOutgoing( row.outgoing ~= false )
                zone:SetProtectNPCs( row.npcs == true )
                zone:ApplyCorners( a, b )
                zone._BoggleSafeLoaded = true
            end
        end
        BoggleSafe.Invalidate()
    end

    hook.Add( "InitPostEntity", "BoggleSafe_Load", function()
        timer.Simple( 1, function()
            BoggleSafe.Load()
        end )
    end )

    hook.Add( "PreCleanupMap", "BoggleSafe_Load", function()
        cleaning = true
        BoggleSafe.Save()
    end )

    hook.Add( "ShutDown", "BoggleSafe_Save", function()
        BoggleSafe.Save()
    end )

    hook.Add( "PostCleanupMap", "BoggleSafe_Load", function()
        timer.Simple( 0.5, function()
            BoggleSafe.Load()
            cleaning = false
        end )
    end )
end
