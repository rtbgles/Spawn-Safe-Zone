include( "shared.lua" )

local colorBox = Color( 70, 200, 90, 80 )
local colorFill = Color( 70, 200, 90, 12 )
local colorText = Color( 200, 255, 200 )

function ENT:Draw()
end

function ENT:DrawTranslucent()
    local mins, maxs = self:GetBounds()
    local center = ( mins + maxs ) * 0.5
    local localMins = mins - center
    local localMaxs = maxs - center

    render.SetColorMaterial()
    render.DrawWireframeBox( center, angle_zero, localMins, localMaxs, colorBox, true )
    render.DrawBox( center, angle_zero, localMins, localMaxs, colorFill, true )

    local ply = LocalPlayer()
    if not IsValid( ply ) or ply:GetPos():DistToSqr( center ) > ( 1200 * 1200 ) then
        return
    end

    local size = maxs - mins
    local ang = Angle( 0, ply:EyeAngles().y, 90 )
    cam.Start3D2D( center + Vector( 0, 0, 8 ), ang, 0.12 )
        draw.SimpleTextOutlined( "SAFE", "DermaDefault", 0, 0, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black )
        draw.SimpleTextOutlined(
            string.format( "%d x %d x %d", size.x, size.y, size.z ),
            "DermaDefault",
            0,
            14,
            colorText,
            TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER,
            1,
            color_black
        )
    cam.End3D2D()
end
