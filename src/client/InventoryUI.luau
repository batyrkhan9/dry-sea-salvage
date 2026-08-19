--[[
	InventoryUI - the relics panel:
	  - RELICS toggle button (bottom left)
	  - scrolling list of owned relics, sorted by tier then name
	  - a MERGE button on rows with enough copies to merge

	Like RollUI, this module doesn't talk to remotes itself. The entry
	script provides callbacks:
	  InventoryUI.onInventoryRequested(fetch)  -> fetch(): {[string]: number}
	  InventoryUI.onMergeRequested(merge)      -> merge(relicName)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local RelicUtil = require(ReplicatedStorage.Shared.RelicUtil)

local InventoryUI = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "InventoryUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

-- ---------- toggle button ----------

local toggleButton = Instance.new("TextButton")
toggleButton.Name = "ToggleButton"
toggleButton.AnchorPoint = Vector2.new(0, 1)
toggleButton.Position = UDim2.new(0, 20, 0.92, 0)
toggleButton.Size = UDim2.fromOffset(140, 44)
toggleButton.Text = "RELICS"
toggleButton.Font = Enum.Font.GothamBold
toggleButton.TextSize = 18
toggleButton.TextColor3 = Color3.fromRGB(240, 230, 210)
toggleButton.BackgroundColor3 = Color3.fromRGB(90, 70, 45) -- rust brown
toggleButton.Parent = screenGui

local toggleCorner = Instance.new("UICorner")
toggleCorner.CornerRadius = UDim.new(0, 10)
toggleCorner.Parent = toggleButton

-- ---------- panel ----------

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0, 1)
panel.Position = UDim2.new(0, 20, 0.92, -54)
panel.Size = UDim2.fromOffset(300, 340)
panel.BackgroundColor3 = Color3.fromRGB(35, 30, 25)
panel.BackgroundTransparency = 0.1
panel.Visible = false
panel.Parent = screenGui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 14)
panelCorner.Parent = panel

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Position = UDim2.fromOffset(0, 8)
title.Size = UDim2.new(1, 0, 0, 28)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 18
title.TextColor3 = Color3.fromRGB(240, 230, 210)
title.Text = "RELICS"
title.Parent = panel

local list = Instance.new("ScrollingFrame")
list.Name = "List"
list.Position = UDim2.fromOffset(10, 40)
list.Size = UDim2.new(1, -20, 1, -50)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 6
list.AutomaticCanvasSize = Enum.AutomaticSize.Y -- canvas grows with content
list.CanvasSize = UDim2.new()
list.Parent = panel

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 6)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = list

-- ---------- callbacks from the entry script ----------

local fetchInventory: (() -> { [string]: number })? = nil
local requestMerge: ((relicName: string) -> ())? = nil

function InventoryUI.onInventoryRequested(fetch: () -> { [string]: number })
	fetchInventory = fetch
end

function InventoryUI.onMergeRequested(merge: (relicName: string) -> ())
	requestMerge = merge
end

-- ---------- building rows ----------

local function makeRow(relicName: string, count: number, layoutOrder: number)
	local rarityName = RelicUtil.rarityOf(relicName) or "?"
	local color = RelicUtil.rarityColor(rarityName)
	local canMerge = RelicUtil.isMergeable(relicName) and count >= Config.MergeCost

	local row = Instance.new("Frame")
	row.Name = relicName
	row.Size = UDim2.new(1, 0, 0, 40)
	row.BackgroundColor3 = Color3.fromRGB(50, 43, 35)
	row.LayoutOrder = layoutOrder

	local rowCorner = Instance.new("UICorner")
	rowCorner.CornerRadius = UDim.new(0, 8)
	rowCorner.Parent = row

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Position = UDim2.fromOffset(10, 0)
	nameLabel.Size = UDim2.new(1, -110, 1, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.Gotham
	nameLabel.TextSize = 15
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextColor3 = color
	nameLabel.Text = ("%s  x%d"):format(relicName, count)
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Parent = row

	if canMerge then
		local mergeButton = Instance.new("TextButton")
		mergeButton.AnchorPoint = Vector2.new(1, 0.5)
		mergeButton.Position = UDim2.new(1, -8, 0.5, 0)
		mergeButton.Size = UDim2.fromOffset(80, 28)
		mergeButton.Text = "MERGE"
		mergeButton.Font = Enum.Font.GothamBold
		mergeButton.TextSize = 14
		mergeButton.TextColor3 = Color3.fromRGB(40, 30, 15)
		mergeButton.BackgroundColor3 = Color3.fromRGB(230, 190, 100)
		mergeButton.Parent = row

		local mergeCorner = Instance.new("UICorner")
		mergeCorner.CornerRadius = UDim.new(0, 8)
		mergeCorner.Parent = mergeButton

		mergeButton.Activated:Connect(function()
			-- Disable immediately so double-clicks can't fire two merges
			-- before the refresh rebuilds the list.
			mergeButton.Active = false
			mergeButton.AutoButtonColor = false
			mergeButton.BackgroundColor3 = Color3.fromRGB(120, 105, 80)
			if requestMerge then
				requestMerge(relicName)
			end
		end)
	end

	row.Parent = list
end

-- ---------- refreshing ----------

-- Rebuild the whole list from a fresh server fetch. Rebuilding (rather than
-- diffing) is the simple option and is fine at this scale (~14 relics max).
function InventoryUI.refresh()
	if fetchInventory == nil then
		return
	end
	local inventory = fetchInventory()

	for _, child in list:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	-- Sort: rarest tier first, then alphabetical inside a tier.
	local names = {}
	for relicName in inventory do
		table.insert(names, relicName)
	end
	table.sort(names, function(a, b)
		local ra = RelicUtil.rarityIndex(RelicUtil.rarityOf(a) or "") or 0
		local rb = RelicUtil.rarityIndex(RelicUtil.rarityOf(b) or "") or 0
		if ra ~= rb then
			return ra > rb
		end
		return a < b
	end)

	for order, relicName in names do
		makeRow(relicName, inventory[relicName], order)
	end
end

-- Refresh only when the panel is actually on screen - no point fetching
-- the inventory for a hidden panel.
function InventoryUI.refreshIfOpen()
	if panel.Visible then
		InventoryUI.refresh()
	end
end

toggleButton.Activated:Connect(function()
	panel.Visible = not panel.Visible
	if panel.Visible then
		InventoryUI.refresh()
	end
end)

return InventoryUI
