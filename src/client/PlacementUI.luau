--[[
	PlacementUI - the cell-picking mode for deploying a relic.

	Flow: PLACE is clicked in the relics panel -> enter(relicName, taken)
	overlays the player's plot with clickable highlights on every free
	cell -> clicking one fires the onCellChosen callback -> the mode
	tears itself down. A banner with a CANCEL button shows while active.

	The highlights are LOCAL parts (created client-side, never
	replicated), so other players don't see your placement mode. The
	server re-validates the chosen cell anyway - this UI is convenience,
	not authority.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local RelicUtil = require(ReplicatedStorage.Shared.RelicUtil)

local PlacementUI = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mouse = player:GetMouse()

local FREE_COLOR = Color3.fromRGB(120, 210, 130)

-- ---------- banner with cancel ----------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "PlacementUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local banner = Instance.new("Frame")
banner.Name = "Banner"
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Position = UDim2.new(0.5, 0, 0, 20)
banner.Size = UDim2.fromOffset(380, 44)
banner.BackgroundColor3 = Color3.fromRGB(35, 30, 25)
banner.BackgroundTransparency = 0.1
banner.Visible = false
banner.Parent = screenGui

local bannerCorner = Instance.new("UICorner")
bannerCorner.CornerRadius = UDim.new(0, 12)
bannerCorner.Parent = banner

local bannerText = Instance.new("TextLabel")
bannerText.Position = UDim2.fromOffset(12, 0)
bannerText.Size = UDim2.new(1, -110, 1, 0)
bannerText.BackgroundTransparency = 1
bannerText.Font = Enum.Font.Gotham
bannerText.TextSize = 15
bannerText.TextXAlignment = Enum.TextXAlignment.Left
bannerText.TextColor3 = Color3.fromRGB(240, 230, 210)
bannerText.TextTruncate = Enum.TextTruncate.AtEnd
bannerText.Parent = banner

local cancelButton = Instance.new("TextButton")
cancelButton.AnchorPoint = Vector2.new(1, 0.5)
cancelButton.Position = UDim2.new(1, -8, 0.5, 0)
cancelButton.Size = UDim2.fromOffset(84, 28)
cancelButton.Text = "CANCEL"
cancelButton.Font = Enum.Font.GothamBold
cancelButton.TextSize = 14
cancelButton.TextColor3 = Color3.fromRGB(240, 230, 210)
cancelButton.BackgroundColor3 = Color3.fromRGB(140, 70, 55)
cancelButton.Parent = banner

local cancelCorner = Instance.new("UICorner")
cancelCorner.CornerRadius = UDim.new(0, 8)
cancelCorner.Parent = cancelButton

-- ---------- placement mode state ----------

local chosenCallback: ((relicName: string, cellX: number, cellZ: number) -> ())? = nil

function PlacementUI.onCellChosen(callback: (relicName: string, cellX: number, cellZ: number) -> ())
	chosenCallback = callback
end

local highlightFolder: Folder? = nil
local clickConnection: RBXScriptConnection? = nil
local activeRelicName: string? = nil

function PlacementUI.exit()
	if highlightFolder then
		highlightFolder:Destroy()
		highlightFolder = nil
	end
	if clickConnection then
		clickConnection:Disconnect()
		clickConnection = nil
	end
	activeRelicName = nil
	banner.Visible = false
end

-- The plot floor is the server-built part named Floor inside
-- Plot_<username>; its CFrame plus Config gives every cell's position -
-- same math as the server's cellCFrame, mirrored here.
local function findPlotFloor(): BasePart?
	local plotModel = workspace:FindFirstChild("Plot_" .. player.Name)
	local floor = plotModel and plotModel:FindFirstChild("Floor")
	return if floor and floor:IsA("BasePart") then floor else nil
end

-- Enters placement mode. `taken` is the current campRelics list from the
-- server; those cells simply get no highlight.
function PlacementUI.enter(relicName: string, taken: { { cellX: number, cellZ: number } })
	PlacementUI.exit() -- restart cleanly if a mode was already active

	local floor = findPlotFloor()
	if floor == nil then
		warn("PlacementUI: no plot found for " .. player.Name)
		return
	end
	local origin = floor.CFrame * CFrame.new(0, -0.2, 0)

	local takenSet: { [string]: boolean } = {}
	for _, placed in taken do
		takenSet[placed.cellX .. "," .. placed.cellZ] = true
	end

	activeRelicName = relicName
	-- Budget readout: what this deploy costs against the hard cap.
	local def = RelicUtil.defOf(relicName)
	local used = RelicUtil.armyCost(taken)
	local cost = if def then def.cost else 0
	if used + cost > Config.Duel.budget then
		bannerText.Text = ("%s costs %dpt - over budget (%d/%d used)"):format(relicName, cost, used, Config.Duel.budget)
	else
		bannerText.Text = ("Placing %s (%dpt) - budget %d/%d - pick a green cell"):format(
			relicName,
			cost,
			used + cost,
			Config.Duel.budget
		)
	end
	banner.Visible = true

	local folder = Instance.new("Folder")
	folder.Name = "PlacementHighlights"
	highlightFolder = folder

	local half = (Config.Camp.gridCells + 1) / 2
	for z = 1, Config.Camp.gridCells do
		for x = 1, Config.Camp.gridCells do
			if not takenSet[x .. "," .. z] then
				local pad = Instance.new("Part")
				pad.Name = ("Cell_%d_%d"):format(x, z)
				pad.Anchored = true
				pad.CanCollide = false
				pad.Size = Vector3.new(Config.Camp.cellSize * 0.9, 0.2, Config.Camp.cellSize * 0.9)
				-- z mirrored to match the server's cellCFrame: row 6 is
				-- the spawn-facing FRONT edge.
				pad.CFrame = origin
					* CFrame.new((x - half) * Config.Camp.cellSize, 0.55, (half - z) * Config.Camp.cellSize)
				pad.Material = Enum.Material.Neon
				pad.Color = FREE_COLOR
				pad.Transparency = 0.55
				pad:SetAttribute("CellX", x)
				pad:SetAttribute("CellZ", z)
				pad.Parent = folder
			end
		end
	end
	folder.Parent = workspace

	clickConnection = mouse.Button1Down:Connect(function()
		local target = mouse.Target
		if target == nil or target.Parent ~= folder then
			return
		end
		local cellX = target:GetAttribute("CellX")
		local cellZ = target:GetAttribute("CellZ")
		local placingRelic = activeRelicName
		PlacementUI.exit()
		if chosenCallback and placingRelic and cellX and cellZ then
			chosenCallback(placingRelic, cellX, cellZ)
		end
	end)
end

cancelButton.Activated:Connect(PlacementUI.exit)

return PlacementUI
