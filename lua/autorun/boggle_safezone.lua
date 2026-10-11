if SERVER then
    AddCSLuaFile()
end

BoggleSafe = BoggleSafe or {}

local ZONE_CLASS = "ent_boggle_safezone"
local PLAYER_PAD = 16
local CACHE_TTL = 1
local GOD_INTERVAL = 0.1
local SAVE_DELAY = 0.25

local staffBypassCvar = CreateConVar( "boggle_safezone_staff_bypass", "0", { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY },
    "1 = superadmins standing in a safe zone can still deal damage outward. Players inside a zone are protected either way.", 0, 1 )
local drawCvar = CreateConVar( "boggle_safezone_draw", "0", { FCVAR_ARCHIVE, FCVAR_REPLICATED },
    "1 = everyone sees safe zone boundaries. 0 = only players holding the Safe Zone tool see them.", 0, 1 )

local zoneCache, zoneCacheAt = {}, -math.huge

local function isZone( ent )
    return IsValid( ent ) and ent.IsBoggleSafeZone == true
end

local function zoneList()
    local now = CurTime()
    if now - zoneCacheAt > CACHE_TTL then
        zoneCache = ents.FindByClass( ZONE_CLASS )
        zoneCacheAt = now
    end

    return zoneCache
end

function BoggleSafe.Invalidate()
    zoneCacheAt = -math.huge
end

function BoggleSafe.GetZones()
    return zoneList()
end

-- filter is an optional function( zone ) -> bool used to require a zone flag (e.g. BlockOutgoing).
function BoggleSafe.FindAt( pos, pad, filter )
    if not pos then return nil end

    local list = zoneList()
    for i = 1, #list do
        local zone = list[i]
        if IsValid( zone ) and zone:Contains( pos, pad ) and ( not filter or filter( zone ) ) then
            return zone
        end
    end
end

function BoggleSafe.Nearest( pos, maxDist )
    local best, bestDist
    local cap = ( maxDist or 128 ) ^ 2
    local list = zoneList()
    for i = 1, #list do
        local zone = list[i]
        if IsValid( zone ) then
            local dist = zone:NearestDistSqr( pos )
            if dist <= cap and ( not bestDist or dist < bestDist ) then
                best, bestDist = zone, dist
            end
        end
    end

    return best
end

-- Returns the zone an entity is standing in. Players are probed at feet, center and eyes
-- (plus their vehicle) with a little padding so hugging a wall doesn't slip through.
function BoggleSafe.ZoneOf( ent, filter )
    if not IsValid( ent ) then return nil end

    local isPlayer = ent:IsPlayer()
    local pad = isPlayer and PLAYER_PAD or 0
    local zone = BoggleSafe.FindAt( ent:WorldSpaceCenter(), pad, filter ) or BoggleSafe.FindAt( ent:GetPos(), pad, filter )
    if zone or not isPlayer then return zone end

    zone = BoggleSafe.FindAt( ent:EyePos(), pad, filter )
    if zone or not ent:InVehicle() then return zone end

    local veh = ent:GetVehicle()
    if IsValid( veh ) then
        return BoggleSafe.FindAt( veh:WorldSpaceCenter(), pad, filter )
    end
end

local function blocksOutgoing( zone )
    return zone:GetBlockOutgoing()
end

local function protectsNPCs( zone )
    return zone:GetProtectNPCs()
end

local function isNpcLike( ent )
    return ent:IsNPC() or ent:IsNextBot()
end

-- Is this entity shielded from all incoming damage? Players always are while inside a zone;
-- NPCs only when a zone they're in has "protect NPCs" enabled.
function BoggleSafe.Protects( ent )
    if not IsValid( ent ) then return false, nil end

    local zone
    if ent:IsPlayer() then
        zone = BoggleSafe.ZoneOf( ent )
    elseif isNpcLike( ent ) then
        zone = BoggleSafe.ZoneOf( ent, protectsNPCs )
    end

    return zone ~= nil, zone
end

-- Resolve whoever is really responsible for an entity's damage (weapon -> holder,
-- vehicle -> driver, projectile/prop -> owner or whoever last threw it).
local function asActor( ent )
    if not IsValid( ent ) then return nil end
    if ent:IsPlayer() then return ent end

    if isfunction( ent.GetDriver ) then
        local driver = ent:GetDriver()
        if IsValid( driver ) then return driver end
    end

    local owner = ent:GetOwner()
    if IsValid( owner ) then return owner end

    -- Server only; the method doesn't exist clientside.
    if isfunction( ent.GetPhysicsAttacker ) then
        local thrower = ent:GetPhysicsAttacker()
        if IsValid( thrower ) then return thrower end
    end

    -- Prop protection (CPPI) is optional; only use it when installed.
    if isfunction( ent.CPPIGetOwner ) then
        local cppiOwner = ent:CPPIGetOwner()
        if IsValid( cppiOwner ) then return cppiOwner end
    end

    if IsValid( ent.Owner ) then return ent.Owner end

    return ent
end

local function staffExempt( actor )
    return staffBypassCvar:GetBool() and IsValid( actor ) and actor:IsPlayer() and actor:IsSuperAdmin()
end

-- Is damage coming from inside an outgoing-blocking zone? Checks the responsible actor,
-- the direct attacker and the inflictor (so a grenade or charge sitting inside a zone is
-- also neutered).
local function outgoingBlocked( attacker, inflictor )
    local actor = asActor( attacker ) or asActor( inflictor )
    if staffExempt( actor ) then return false end

    return BoggleSafe.ZoneOf( actor, blocksOutgoing ) ~= nil
        or BoggleSafe.ZoneOf( attacker, blocksOutgoing ) ~= nil
        or BoggleSafe.ZoneOf( inflictor, blocksOutgoing ) ~= nil
end

local function shouldBlock( target, dmg )
    return BoggleSafe.Protects( target ) or outgoingBlocked( dmg:GetAttacker(), dmg:GetInflictor() )
end

local function nullifyDamage( dmg )
    dmg:SetDamage( 0 )
    dmg:SetDamageForce( vector_origin )
end

-- Shared so the shooter's client also suppresses predicted bullets: they see their gun
-- doesn't work instead of fake impacts and blood.
hook.Add( "EntityFireBullets", "BoggleSafe", function( shooter )
    if outgoingBlocked( shooter ) then
        return false
    end
end )

-- Shared: returning true also stops blood effects/decals on a protected player.
hook.Add( "ScalePlayerDamage", "BoggleSafe", function( ply, _, dmg )
    if shouldBlock( ply, dmg ) then
        nullifyDamage( dmg )

        return true
    end
end )

if SERVER then
    hook.Add( "EntityTakeDamage", "BoggleSafe", function( target, dmg )
        if shouldBlock( target, dmg ) then
            nullifyDamage( dmg )

            return true
        end
    end )

    hook.Add( "PlayerShouldTakeDamage", "BoggleSafe", function( ply, attacker )
        if BoggleSafe.Protects( ply ) or outgoingBlocked( attacker ) then
            return false
        end
    end )

    hook.Add( "CanPlayerSuicide", "BoggleSafe", function( ply )
        if BoggleSafe.Protects( ply ) then
            return false
        end
    end )

    -- Engine-level god mode is the backstop for damage that never reaches Lua hooks, or that
    -- another addon's hook swallows first. We only ever turn off god mode that we turned on,
    -- so an admin's own god mode survives leaving a zone.
    timer.Create( "BoggleSafe_God", GOD_INTERVAL, 0, function()
        for _, ply in ipairs( player.GetAll() ) do
            if BoggleSafe.Protects( ply ) then
                if not ply:HasGodMode() then
                    ply:GodEnable()
                    ply._BoggleSafeGod = true
                end

                if ply:IsOnFire() then
                    ply:Extinguish()
                end
            elseif ply._BoggleSafeGod then
                ply._BoggleSafeGod = nil
                ply:GodDisable()
            end
        end
    end )

    local function denyIfZone( _, ent )
        if isZone( ent ) then
            return false
        end
    end

    hook.Add( "PhysgunPickup", "BoggleSafe", denyIfZone )
    hook.Add( "GravGunPickupAllowed", "BoggleSafe", denyIfZone )
    hook.Add( "AllowPlayerPickup", "BoggleSafe", denyIfZone )
    hook.Add( "CanPlayerUnfreeze", "BoggleSafe", denyIfZone )

    hook.Add( "CanProperty", "BoggleSafe", function( ply, _, ent )
        if isZone( ent ) and not ( IsValid( ply ) and ply:IsAdmin() ) then
            return false
        end
    end )

    hook.Add( "CanTool", "BoggleSafe", function( ply, tr )
        if tr and isZone( tr.Entity ) and not ( IsValid( ply ) and ply:IsAdmin() ) then
            return false
        end
    end )

    concommand.Add( "boggle_safe_debug", function( ply )
        if IsValid( ply ) and not ply:IsAdmin() then return end

        local out = IsValid( ply ) and function( msg ) ply:PrintMessage( HUD_PRINTCONSOLE, msg ) end or print
        local zones = ents.FindByClass( ZONE_CLASS )
        out( string.format( "[Safe Zone] %d zone(s), staff bypass %s", #zones, staffBypassCvar:GetBool() and "ON" or "off" ) )

        for _, zone in ipairs( zones ) do
            local mins, maxs = zone:GetBounds()
            out( string.format( "  #%d  %s -> %s  outgoing=%s npcs=%s persist=%s",
                zone:EntIndex(), tostring( mins ), tostring( maxs ),
                tostring( zone:GetBlockOutgoing() ), tostring( zone:GetProtectNPCs() ), tostring( zone:GetPersist() ) ) )
        end

        if IsValid( ply ) then
            local protected, zone = BoggleSafe.Protects( ply )
            out( string.format( "  you: protected=%s zone=%s god=%s pos=%s",
                tostring( protected ), zone and tostring( zone:EntIndex() ) or "none",
                tostring( ply:HasGodMode() ), tostring( ply:GetPos() ) ) )
            ply:ChatPrint( "[Safe Zone] Debug info printed to console." )
        end
    end )

    -- Persistence -----------------------------------------------------------------------

    BoggleSafe.Stored = BoggleSafe.Stored or {}

    local LEGACY_PATH = "boggle_safezone/zones.json"

    local function savePath()
        local map = string.gsub( string.lower( game.GetMap() or "map" ), "[^%w_%-]", "_" )

        return "boggle_safezone/" .. map .. ".json"
    end

    local function rowKey( row )
        return string.format( "%.1f:%.1f:%.1f:%.1f:%.1f:%.1f", row.ax, row.ay, row.az, row.bx, row.by, row.bz )
    end

    function BoggleSafe.Save()
        file.CreateDir( "boggle_safezone" )

        local rows = {}
        for _, row in pairs( BoggleSafe.Stored ) do
            rows[#rows + 1] = row
        end

        file.Write( savePath(), util.TableToJSON( rows, true ) or "[]" )
    end

    function BoggleSafe.QueueSave()
        timer.Create( "BoggleSafe_Save", SAVE_DELAY, 1, BoggleSafe.Save )
    end

    -- Drop a zone from the save file. Called for explicit removals only (tool, undo) so that
    -- map cleanup or shutdown never wipes saved zones.
    function BoggleSafe.Forget( zone )
        if not isZone( zone ) or not zone.BoggleSafeKey then return end

        BoggleSafe.Stored[zone.BoggleSafeKey] = nil
        zone.BoggleSafeKey = nil
        BoggleSafe.QueueSave()
    end

    -- Write a zone's current corners and flags to the save file (or remove it if it's
    -- no longer marked persistent).
    function BoggleSafe.Remember( zone )
        if not isZone( zone ) then return end
        if not zone:GetPersist() then
            BoggleSafe.Forget( zone )

            return
        end

        local a, b = zone:GetCornerA(), zone:GetCornerB()
        local row = {
            ax = a.x, ay = a.y, az = a.z,
            bx = b.x, by = b.y, bz = b.z,
            outgoing = zone:GetBlockOutgoing(),
            npcs = zone:GetProtectNPCs(),
            persist = true
        }

        if zone.BoggleSafeKey then
            BoggleSafe.Stored[zone.BoggleSafeKey] = nil
        end

        local key = rowKey( row )
        zone.BoggleSafeKey = key
        BoggleSafe.Stored[key] = row
        BoggleSafe.QueueSave()
    end

    function BoggleSafe.CreateZone( a, b, opts )
        opts = opts or {}

        local zone = ents.Create( ZONE_CLASS )
        if not IsValid( zone ) then return nil end

        zone:SetPos( ( a + b ) * 0.5 )
        zone:Spawn()
        zone:ApplyCorners( a, b )
        zone:SetBlockOutgoing( opts.outgoing ~= false )
        zone:SetProtectNPCs( opts.npcs == true )
        zone:SetPersist( opts.persist ~= false )
        BoggleSafe.Remember( zone )
        BoggleSafe.Invalidate()

        return zone
    end

    local function readRow( row )
        if not istable( row ) then return nil end

        local ax, ay, az = tonumber( row.ax ), tonumber( row.ay ), tonumber( row.az )
        local bx, by, bz = tonumber( row.bx ), tonumber( row.by ), tonumber( row.bz )
        if not ( ax and ay and az and bx and by and bz ) then return nil end

        return Vector( ax, ay, az ), Vector( bx, by, bz )
    end

    -- Replace every zone in the world with the ones in BoggleSafe.Stored.
    function BoggleSafe.SpawnStored()
        local rows = {}
        for _, row in pairs( BoggleSafe.Stored ) do
            rows[#rows + 1] = row
        end

        for _, zone in ipairs( ents.FindByClass( ZONE_CLASS ) ) do
            zone:Remove()
        end

        BoggleSafe.Stored = {}
        for _, row in ipairs( rows ) do
            local a, b = readRow( row )
            if a then
                BoggleSafe.CreateZone( a, b, { outgoing = row.outgoing ~= false, npcs = row.npcs == true, persist = true } )
            end
        end

        BoggleSafe.Invalidate()
    end

    function BoggleSafe.Load()
        local path = savePath()
        if not file.Exists( path, "DATA" ) and file.Exists( LEGACY_PATH, "DATA" ) then
            path = LEGACY_PATH
        end

        BoggleSafe.Stored = {}

        if file.Exists( path, "DATA" ) then
            local raw = file.Read( path, "DATA" ) or ""
            local rows = util.JSONToTable( raw )
            if istable( rows ) then
                for i, row in ipairs( rows ) do
                    BoggleSafe.Stored[i] = row
                end
            else
                -- Keep a copy instead of silently overwriting it on the next save.
                local backup = string.gsub( path, "%.json$", "" ) .. "_corrupt.txt"
                file.Write( backup, raw )
                ErrorNoHalt( "[Safe Zone] Could not parse " .. path .. ", copied it to data/" .. backup .. "\n" )
            end
        end

        BoggleSafe.SpawnStored()
    end

    hook.Add( "InitPostEntity", "BoggleSafe_Load", BoggleSafe.Load )

    -- Cleanup removes our zones; put them straight back (from memory, so a save that is
    -- still pending isn't lost) to keep the unprotected window to zero.
    hook.Add( "PostCleanupMap", "BoggleSafe_Load", BoggleSafe.SpawnStored )

    hook.Add( "ShutDown", "BoggleSafe_Save", function()
        if timer.Exists( "BoggleSafe_Save" ) then
            timer.Remove( "BoggleSafe_Save" )
            BoggleSafe.Save()
        end
    end )
end

hook.Add( "OnEntityCreated", "BoggleSafe_Cache", function( ent )
    if isZone( ent ) then
        BoggleSafe.Invalidate()
    end
end )

hook.Add( "EntityRemoved", "BoggleSafe_Cache", function( ent )
    if isZone( ent ) then
        BoggleSafe.Invalidate()
    end
end )

if CLIENT then
    local COLOR_EDGE = Color( 70, 200, 90, 160 )
    local COLOR_EDGE_OPEN = Color( 230, 190, 60, 160 )
    local COLOR_FILL = Color( 70, 200, 90, 10 )
    local COLOR_LABEL = Color( 200, 255, 200 )
    local COLOR_HUD = Color( 120, 230, 140 )
    local COLOR_HUD_SUB = Color( 220, 220, 220 )
    local LABEL_DIST_SQR = 1500 ^ 2
    local LABEL_SCALE = 0.15

    local hudCvar = CreateClientConVar( "boggle_safezone_hud", "1", true, false, "Show the SAFE ZONE indicator while you're inside one.", 0, 1 )

    surface.CreateFont( "BoggleSafe_HUD", { font = "Roboto", size = 22, weight = 800 } )
    surface.CreateFont( "BoggleSafe_HUDSmall", { font = "Roboto", size = 15, weight = 500 } )

    function BoggleSafe.IsEditing( ply )
        if not IsValid( ply ) then return false end

        local wep = ply:GetActiveWeapon()

        return IsValid( wep ) and wep:GetClass() == "gmod_tool" and ply:GetInfo( "gmod_toolmode" ) == "boggle_safezone"
    end

    local function drawLabel( zone, mins, maxs, eyeYaw )
        local size = maxs - mins
        local flags = ( zone:GetBlockOutgoing() and "no outgoing" or "outgoing allowed" )
            .. ( zone:GetProtectNPCs() and ", NPCs protected" or "" )
            .. ( zone:GetPersist() and "" or ", not saved" )

        cam.Start3D2D( ( mins + maxs ) * 0.5, Angle( 0, eyeYaw - 90, 90 ), LABEL_SCALE )
            draw.SimpleTextOutlined( "SAFE ZONE #" .. zone:EntIndex(), "DermaLarge", 0, 0, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, color_black )
            draw.SimpleTextOutlined( string.format( "%d x %d x %d  |  %s", math.Round( size.x ), math.Round( size.y ), math.Round( size.z ), flags ),
                "DermaDefaultBold", 0, 4, COLOR_LABEL, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, color_black )
        cam.End3D2D()
    end

    hook.Add( "PostDrawTranslucentRenderables", "BoggleSafe_Zones", function( _, skybox )
        if skybox then return end

        local ply = LocalPlayer()
        local editing = BoggleSafe.IsEditing( ply )
        if not editing and not drawCvar:GetBool() then return end

        local eyePos = EyePos()
        local eyeYaw = EyeAngles().y
        local list = zoneList()

        render.SetColorMaterial()
        for i = 1, #list do
            local zone = list[i]
            if IsValid( zone ) then
                local mins, maxs = zone:GetBounds()
                render.DrawWireframeBox( vector_origin, angle_zero, mins, maxs, zone:GetBlockOutgoing() and COLOR_EDGE or COLOR_EDGE_OPEN, true )
                render.DrawBox( vector_origin, angle_zero, mins, maxs, COLOR_FILL )

                if editing and eyePos:DistToSqr( ( mins + maxs ) * 0.5 ) < LABEL_DIST_SQR then
                    drawLabel( zone, mins, maxs, eyeYaw )
                end
            end
        end
    end )

    hook.Add( "HUDPaint", "BoggleSafe_HUD", function()
        if not hudCvar:GetBool() then return end

        local ply = LocalPlayer()
        if not IsValid( ply ) or not ply:Alive() then return end

        if not BoggleSafe.Protects( ply ) then return end

        local weaponsOff = BoggleSafe.ZoneOf( ply, blocksOutgoing ) and not staffExempt( ply )
        local sub = weaponsOff and "You can't be hurt here, and your weapons won't deal damage" or "You can't be hurt here"
        local x = ScrW() * 0.5
        draw.SimpleTextOutlined( "SAFE ZONE", "BoggleSafe_HUD", x, 12, COLOR_HUD, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, color_black )
        draw.SimpleTextOutlined( sub, "BoggleSafe_HUDSmall", x, 36, COLOR_HUD_SUB, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, color_black )
    end )
end
