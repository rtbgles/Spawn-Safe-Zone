include( "shared.lua" )

-- The zone itself has no model to draw. Boundaries are drawn by the addon's
-- PostDrawTranslucentRenderables hook (lua/autorun/boggle_safezone.lua), which isn't
-- subject to this entity's tiny render bounds or its nodraw flag.
function ENT:Draw()
end
