--[[
	Shared Lune-side module loader for game code. Game modules use
	Roblox-style requires (script.Parent.X) and the Color3 datatype, so
	this loader runs them with shims: `script` becomes a table of file
	paths, `require` loads those paths, and Color3 becomes a plain-table
	stand-in. Only pure logic modules are loadable this way.

	Used by tests/run.luau (unit tests) and tools/balance.luau (battle
	balance simulation).
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")

-- Plain-table stand-in for Roblox's Color3. Consumers only need
-- identity (which color came back), not real color math.
local Color3Stub = {
	fromRGB = function(r: number, g: number, b: number)
		return { R = r / 255, G = g / 255, B = b / 255 }
	end,
	new = function(r: number?, g: number?, b: number?)
		return { R = r or 0, G = g or 0, B = b or 0 }
	end,
}

local cache: { [string]: any } = {}

local function loadModule(path: string, scriptShim: any): any
	if cache[path] ~= nil then
		return cache[path]
	end
	local fn = luau.load(fs.readFile(path), {
		debugName = path,
		environment = {
			Color3 = Color3Stub,
			script = scriptShim,
			require = function(target: any)
				assert(type(target) == "string", `unmapped require in {path}`)
				return loadModule(target, nil)
			end,
		},
	})
	local result = fn()
	cache[path] = result
	return result
end

return loadModule
