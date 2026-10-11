# Boggle Safe Zone

Admin-placed box zones for Garry's Mod. Inside a zone:

- **Players can't be hurt by anything.** That covers bullets, explosions, props, vehicles, fire, falling, map hazards and the `kill` command. The protection is a damage hook with engine god mode as a backstop.
- **Nothing inside can deal damage**, when "Block outgoing damage" is on (the default). Bullets fired from inside are cancelled. Damage done by anything a player inside is responsible for is also blocked: grenades, props they threw, the vehicle they drive. Explosives sitting inside a zone are blocked as well.
- NPCs are protected too, if the zone's "protect NPCs" option is on.

## Install

Put this repository in `garrysmod/addons/`. Use a lowercase folder name such as `boggle_safezone`, because Linux servers are case sensitive.

## Usage

Admins use the **Safe Zone** tool (Tools → Boggle → Safe Zone):

| Input | Action |
| --- | --- |
| Left click ×2 | Place opposite corners. If both clicks are on the floor, the "Floor height" setting is added upward. |
| Right click | Cancel the first corner. Otherwise, remove the zone you're aiming at. |
| Reload | Apply the current checkboxes to the zone you're aiming at. |

Zones are drawn while you hold the tool (green = outgoing damage blocked, yellow = allowed). Undo works too.

Persistent zones are saved to `data/boggle_safezone/<map>.json`. They come back after a restart or map cleanup. Remove them with the tool or undo, not with the cleanup menu.

## Console variables

| ConVar | Default | Realm | Meaning |
| --- | --- | --- | --- |
| `boggle_safezone_staff_bypass` | `0` | server | `1` lets superadmins inside a zone still deal damage outward. Players inside a zone stay protected either way. |
| `boggle_safezone_draw` | `0` | server | `1` shows zone boundaries to everyone, not just tool holders. |
| `boggle_safezone_hud` | `1` | client | Shows the "SAFE ZONE" banner while you're inside a zone. |

`boggle_safe_debug` (admin only) prints every zone and your own protection state to the console.

## Limits

- `Player:Kill()` and admin "slay" commands bypass all damage, so they aren't blocked.
- Protection depends on where you are. A player who steps out of a zone to shoot can be shot back. Once they step back in, they're protected again.
