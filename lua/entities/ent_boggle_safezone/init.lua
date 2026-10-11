AddCSLuaFile( "shared.lua" )
AddCSLuaFile( "cl_init.lua" )
include( "shared.lua" )

function ENT:Initialize()
    self:SetModel( "models/props_junk/PopCan01a.mdl" )
    self:SetMoveType( MOVETYPE_NONE )
    self:SetSolid( SOLID_NONE )
    self:SetCollisionGroup( COLLISION_GROUP_NONE )
    self:DrawShadow( false )
    self:SetNoDraw( true )
    self:SetNotSolid( true )
    self:SetPersist( true )
    self:SetBlockOutgoing( true )
end

function ENT:ApplyCorners( a, b )
    if not a or not b then
        return
    end
    local mins = Vector( math.min( a.x, b.x ), math.min( a.y, b.y ), math.min( a.z, b.z ) )
    local maxs = Vector( math.max( a.x, b.x ), math.max( a.y, b.y ), math.max( a.z, b.z ) )
    local span = maxs - mins
    if span.x > 32768 or span.y > 32768 or span.z > 8192 then
        maxs.x = mins.x + math.min( span.x, 32768 )
        maxs.y = mins.y + math.min( span.y, 32768 )
        maxs.z = mins.z + math.min( span.z, 8192 )
    end
    self:SetCornerA( mins )
    self:SetCornerB( maxs )
    self:SetPos( ( mins + maxs ) * 0.5 )
    if BoggleSafe and BoggleSafe.Invalidate then
        BoggleSafe.Invalidate()
    end
    if BoggleSafe and BoggleSafe.Remember then
        BoggleSafe.Remember( self )
    end
end

function ENT:OnRemove()
    if BoggleSafe and BoggleSafe.Invalidate then
        BoggleSafe.Invalidate()
    end
end

function ENT:UpdateTransmitState()
    return TRANSMIT_ALWAYS
end

function ENT:OnEntityCopyTableFinish( data )
    data.CornerA = self:GetCornerA()
    data.CornerB = self:GetCornerB()
    data.BlockOutgoing = self:GetBlockOutgoing()
    data.ProtectNPCs = self:GetProtectNPCs()
    data.Persist = self:GetPersist()
end

duplicator.RegisterEntityClass( "ent_boggle_safezone", function( ply, data )
    if IsValid( ply ) and not ply:IsAdmin() then
        return
    end
    local zone = ents.Create( "ent_boggle_safezone" )
    if not IsValid( zone ) then
        return
    end
    zone:SetPos( data.Pos or vector_origin )
    zone:Spawn()
    if data.CornerA and data.CornerB then
        zone:ApplyCorners( data.CornerA, data.CornerB )
    end
    if data.BlockOutgoing ~= nil then
        zone:SetBlockOutgoing( data.BlockOutgoing )
    end
    if data.ProtectNPCs ~= nil then
        zone:SetProtectNPCs( data.ProtectNPCs )
    end
    if data.Persist ~= nil then
        zone:SetPersist( data.Persist )
    else
        zone:SetPersist( true )
    end
    return zone
end, "Pos", "CornerA", "CornerB", "BlockOutgoing", "ProtectNPCs", "Persist" )
