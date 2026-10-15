# Martini Hub · Fix It Up

Script for Fix It Up! (place 72712036210947), Obsidian UI.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Martinikaws/fix-it-up/main/fiu_main.lua"))()
```

## Debug

If the script doesn't load, or auto flip / the Drive farm misbehaves, run this and press **Quick check**. It's safe: nothing moves and nothing is bought.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Martinikaws/fix-it-up/main/fiu_debug.lua"))()
```

On someone else's PC, add your Discord webhook first. The check then runs by itself and the report arrives in your Discord as a `.txt` file:

```lua
getgenv().FIU_DEBUG_WEBHOOK = "https://discord.com/api/webhooks/..."
loadstring(game:HttpGet("https://raw.githubusercontent.com/Martinikaws/fix-it-up/main/fiu_debug.lua"))()
```
