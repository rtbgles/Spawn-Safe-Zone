ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.Editable = false
ENT.PrintName = "Safe Zone"
ENT.Author = "Boggle"
ENT.Category = "Boggle"
ENT.Spawnable = false
ENT.AdminOnly = true
ENT.RenderGroup = RENDERGROUP_BOTH
ENT.IsBoggleSafeZone = true

function ENT:SetupDataTables()
    self:NetworkVar( "Vector", 0, "CornerA" )
    self:NetworkVar( "Vector", 1, "CornerB" )
    self:NetworkVar( "Bool", 0, "BlockOutgoing" )
    self:NetworkVar( "Bool", 1, "ProtectNPCs" )
    self:NetworkVar( "Bool", 2, "Persist" )
end

function ENT:GetBounds()
    local a = self:GetCornerA()
    local b = self:GetCornerB()
    local mins = Vector( math.min( a.x, b.x ), math.min( a.y, b.y ), math.min( a.z, b.z ) )
    local maxs = Vector( math.max( a.x, b.x ), math.max( a.y, b.y ), math.max( a.z, b.z ) )
    return mins, maxs
end

function ENT:Contains( pos, pad )
    if not pos then
        return false
    end
    pad = tonumber( pad ) or 0
    local mins, maxs = self:GetBounds()
    return pos.x >= mins.x - pad and pos.x <= maxs.x + pad
        and pos.y >= mins.y - pad and pos.y <= maxs.y + pad
        and pos.z >= mins.z - pad and pos.z <= maxs.z + pad
end

function ENT:NearestDistSqr( pos )
    local mins, maxs = self:GetBounds()
    local cx = math.Clamp( pos.x, mins.x, maxs.x )
    local cy = math.Clamp( pos.y, mins.y, maxs.y )
    local cz = math.Clamp( pos.z, mins.z, maxs.z )
    local dx, dy, dz = pos.x - cx, pos.y - cy, pos.z - cz
    return dx * dx + dy * dy + dz * dz
end
