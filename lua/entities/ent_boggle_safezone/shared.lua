ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.Editable = false
ENT.PrintName = "Safe Zone"
ENT.Author = "Boggle"
ENT.Category = "Boggle"
ENT.Spawnable = false
ENT.AdminOnly = true
-- Zones store world-space corners and are saved by the addon itself; a duplicator paste
-- would land in the wrong place and bypass the save file.
ENT.DisableDuplicator = true
ENT.RenderGroup = RENDERGROUP_OPAQUE
ENT.IsBoggleSafeZone = true

function ENT:SetupDataTables()
    -- CornerA is always the min corner and CornerB the max corner (see ENT:ApplyCorners).
    self:NetworkVar( "Vector", 0, "CornerA" )
    self:NetworkVar( "Vector", 1, "CornerB" )
    self:NetworkVar( "Bool", 0, "BlockOutgoing" )
    self:NetworkVar( "Bool", 1, "ProtectNPCs" )
    self:NetworkVar( "Bool", 2, "Persist" )
end

function ENT:GetBounds()
    return self:GetCornerA(), self:GetCornerB()
end

function ENT:Contains( pos, pad )
    if not pos then return false end

    pad = pad or 0
    local mins, maxs = self:GetCornerA(), self:GetCornerB()

    return pos.x >= mins.x - pad and pos.x <= maxs.x + pad
        and pos.y >= mins.y - pad and pos.y <= maxs.y + pad
        and pos.z >= mins.z - pad and pos.z <= maxs.z + pad
end

function ENT:NearestDistSqr( pos )
    local mins, maxs = self:GetCornerA(), self:GetCornerB()
    local dx = pos.x - math.Clamp( pos.x, mins.x, maxs.x )
    local dy = pos.y - math.Clamp( pos.y, mins.y, maxs.y )
    local dz = pos.z - math.Clamp( pos.z, mins.z, maxs.z )

    return dx * dx + dy * dy + dz * dz
end
