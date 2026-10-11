AddCSLuaFile( "shared.lua" )
AddCSLuaFile( "cl_init.lua" )
include( "shared.lua" )

local MAX_SPAN_XY = 32768
local MAX_SPAN_Z = 8192

function ENT:Initialize()
    self:SetModel( "models/props_junk/PopCan01a.mdl" )
    self:SetMoveType( MOVETYPE_NONE )
    self:SetSolid( SOLID_NONE )
    self:SetNotSolid( true )
    self:DrawShadow( false )
    self:SetNoDraw( true )
    self:SetPersist( true )
    self:SetBlockOutgoing( true )
end

-- Takes any two opposite corners; stores them normalized as CornerA = mins, CornerB = maxs.
function ENT:ApplyCorners( a, b )
    if not a or not b then return end

    local mins = Vector( math.min( a.x, b.x ), math.min( a.y, b.y ), math.min( a.z, b.z ) )
    local maxs = Vector( math.max( a.x, b.x ), math.max( a.y, b.y ), math.max( a.z, b.z ) )
    maxs.x = math.min( maxs.x, mins.x + MAX_SPAN_XY )
    maxs.y = math.min( maxs.y, mins.y + MAX_SPAN_XY )
    maxs.z = math.min( maxs.z, mins.z + MAX_SPAN_Z )

    self:SetCornerA( mins )
    self:SetCornerB( maxs )
    self:SetPos( ( mins + maxs ) * 0.5 )

    if BoggleSafe and BoggleSafe.Invalidate then
        BoggleSafe.Invalidate()
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
