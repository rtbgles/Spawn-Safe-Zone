TOOL.Category = "Boggle"
TOOL.Name = "#tool.boggle_safezone.name"
TOOL.Command = nil
TOOL.ConfigName = ""

TOOL.Information = {
    { name = "left" },
    { name = "right" },
    { name = "reload" }
}

TOOL.ClientConVar[ "outgoing" ] = "1"
TOOL.ClientConVar[ "npcs" ] = "0"
TOOL.ClientConVar[ "height" ] = "192"
TOOL.ClientConVar[ "persist" ] = "1"

if CLIENT then
    language.Add( "tool.boggle_safezone.name", "Safe Zone" )
    language.Add( "tool.boggle_safezone.desc", "Two-click box. No dying or killing inside." )
    language.Add( "tool.boggle_safezone.left", "Click opposite corners of the box" )
    language.Add( "tool.boggle_safezone.right", "Cancel first corner, or remove a zone" )
    language.Add( "tool.boggle_safezone.reload", "Apply current options to the zone under the cursor" )
end

local function canPlace( ply )
    return IsValid( ply ) and ply:IsAdmin()
end

local function zoneAt( pos, reach )
    return BoggleSafe.FindAt( pos ) or BoggleSafe.Nearest( pos, reach )
end

local function makeBounds( a, b, height )
    local mins = Vector( math.min( a.x, b.x ), math.min( a.y, b.y ), math.min( a.z, b.z ) )
    local maxs = Vector( math.max( a.x, b.x ), math.max( a.y, b.y ), math.max( a.z, b.z ) )
    if ( maxs.z - mins.z ) < 16 then
        maxs.z = mins.z + math.max( 32, height or 192 )
    end
    if maxs.x - mins.x < 16 then
        maxs.x = mins.x + 16
    end
    if maxs.y - mins.y < 16 then
        maxs.y = mins.y + 16
    end
    maxs.x = mins.x + math.min( maxs.x - mins.x, 32768 )
    maxs.y = mins.y + math.min( maxs.y - mins.y, 32768 )
    maxs.z = mins.z + math.min( maxs.z - mins.z, 8192 )
    return mins, maxs
end

function TOOL:LeftClick( trace )
    if not trace or not trace.Hit then
        return false
    end

    local ply = self:GetOwner()
    if not canPlace( ply ) then
        return false
    end
    if CLIENT then
        return true
    end

    local pos = trace.HitPos + trace.HitNormal * 2
    if not ply.BoggleSafeA then
        ply.BoggleSafeA = pos
        ply:SetNW2Bool( "BoggleSafeHasA", true )
        ply:SetNW2Vector( "BoggleSafeA", pos )
        return true
    end

    local a = ply.BoggleSafeA
    local b = pos
    ply.BoggleSafeA = nil
    ply:SetNW2Bool( "BoggleSafeHasA", false )

    local height = math.Clamp( self:GetClientNumber( "height", 192 ), 32, 2048 )
    local mins, maxs = makeBounds( a, b, height )
    local zone = BoggleSafe.CreateZone( mins, maxs, {
        outgoing = self:GetClientNumber( "outgoing", 1 ) >= 1,
        npcs = self:GetClientNumber( "npcs", 0 ) >= 1,
        persist = self:GetClientNumber( "persist", 1 ) >= 1
    } )
    if not IsValid( zone ) then
        return false
    end

    -- Undo forgets the zone before removing it. There's deliberately no cleanup entry:
    -- cleanup removes entities without telling us, so the zone would come back on restart.
    undo.Create( "Boggle Safe Zone" )
        undo.AddFunction( function()
            BoggleSafe.Forget( zone )
        end )
        undo.AddEntity( zone )
        undo.SetPlayer( ply )
    undo.Finish()

    ply:ChatPrint( string.format( "[Safe Zone] Zone #%d created%s.", zone:EntIndex(), zone:GetPersist() and " and saved" or " (not saved)" ) )
    return true
end

function TOOL:RightClick( trace )
    local ply = self:GetOwner()
    if not canPlace( ply ) then
        return false
    end
    if CLIENT then
        return true
    end

    if ply.BoggleSafeA then
        ply.BoggleSafeA = nil
        ply:SetNW2Bool( "BoggleSafeHasA", false )
        return true
    end

    local origin = ( trace and trace.HitPos ) or ply:GetPos()
    local zone = zoneAt( origin, 80 )
    if not IsValid( zone ) then
        return false
    end

    ply:ChatPrint( string.format( "[Safe Zone] Zone #%d removed.", zone:EntIndex() ) )
    BoggleSafe.Forget( zone )
    zone:Remove()
    return true
end

function TOOL:Reload( trace )
    local ply = self:GetOwner()
    if not canPlace( ply ) then
        return false
    end
    if CLIENT then
        return true
    end

    local origin = ( trace and trace.HitPos ) or ply:GetPos()
    local zone = zoneAt( origin, 256 )
    if not IsValid( zone ) then
        return false
    end

    zone:SetBlockOutgoing( self:GetClientNumber( "outgoing", 1 ) >= 1 )
    zone:SetProtectNPCs( self:GetClientNumber( "npcs", 0 ) >= 1 )
    zone:SetPersist( self:GetClientNumber( "persist", 1 ) >= 1 )
    BoggleSafe.Remember( zone )
    ply:ChatPrint( string.format( "[Safe Zone] Options applied to zone #%d%s.", zone:EntIndex(), zone:GetPersist() and " and saved" or " (not saved)" ) )
    return true
end

function TOOL:Holster()
    local ply = self:GetOwner()
    if SERVER and IsValid( ply ) then
        ply.BoggleSafeA = nil
        ply:SetNW2Bool( "BoggleSafeHasA", false )
    end
    return true
end

if CLIENT then
    local ghostA = Color( 220, 220, 80, 180 )
    local ghostBox = Color( 90, 220, 110, 60 )

    hook.Add( "PostDrawTranslucentRenderables", "BoggleSafe_Ghost", function( _, skybox )
        if skybox then
            return
        end
        local ply = LocalPlayer()
        if not BoggleSafe.IsEditing( ply ) then
            return
        end

        local tr = ply:GetEyeTrace()
        if not tr.Hit then
            return
        end

        render.SetColorMaterial()
        if not ply:GetNW2Bool( "BoggleSafeHasA", false ) then
            render.DrawSphere( tr.HitPos, 4, 8, 8, ghostA )
            return
        end

        local a = ply:GetNW2Vector( "BoggleSafeA", tr.HitPos )
        local height = math.Clamp( tonumber( ply:GetInfo( "boggle_safezone_height" ) ) or 192, 32, 2048 )
        local mins, maxs = makeBounds( a, tr.HitPos, height )
        local center = ( mins + maxs ) * 0.5
        render.DrawWireframeBox( center, angle_zero, mins - center, maxs - center, ghostBox, true )
        render.DrawSphere( a, 5, 8, 8, ghostA )
    end )

    function TOOL.BuildCPanel( panel )
        panel:Help( "Left click two opposite corners. If both clicks are on the floor, Height is added upward so the box actually covers players." )
        panel:NumSlider( "Floor height", "boggle_safezone_height", 32, 2048, 0 )
        panel:CheckBox( "Block outgoing damage (players and NPCs)", "boggle_safezone_outgoing" )
        panel:CheckBox( "Also protect NPCs standing in the box", "boggle_safezone_npcs" )
        panel:CheckBox( "Persist after restart and cleanup", "boggle_safezone_persist" )
        panel:ControlHelp( "Reload on an existing zone applies these checkboxes to it and writes data/boggle_safezone/<map>.json." )
        panel:Help( "Zones are visible while you hold this tool (yellow = outgoing damage allowed). Right click removes the zone you're aiming at; undo also works. Map cleanup does not remove saved zones." )
    end
end
