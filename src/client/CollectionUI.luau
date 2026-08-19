--[[
	CollectionUI - the index/collection book:
	  - INDEX toggle button (bottom left, next to RELICS)
	  - panel listing EVERY relic in the game grouped by tier, in config
	    order; found relics show their name, missing ones show "???"
	  - progress counter in the title ("7 / 14")

	Unlike the relics panel (which lists what you hold), this lists the
	whole game - so its rows come from Config, not from the inventory.
	Callback from the entry script:
	  CollectionUI.onCollectionRequested(fetch) -> fetch(): {[string]: boolean}
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local RelicUtil = require(ReplicatedStorage.Shared.RelicUtil)

local CollectionUI = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Total relic count in the game, for the "found / total" counter.
local totalRelics = 0
for _, relics in Config.Relics do
	totalRelics += #relics
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CollectionUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

-- ---------- toggle button (sits right of the RELICS button) ----------

local toggleButton = Instance.new("TextButton")
toggleButton.Name = "ToggleButton"
toggleButton.AnchorPoint = Vector2.new(0, 1)
toggleButton.Position = UDim2.new(0, 170, 0.92, 0)
toggleButton.Size = UDim2.fromOffset(140, 44)
toggleButton.Text = "INDEX"
toggleButton.Font = Enum.Font.GothamBold
toggleButton.TextSize = 18
toggleButton.TextColor3 = Color3.fromRGB(240, 230, 210)
toggleButton.BackgroundColor3 = Color3.fromRGB(70, 85, 95) -- faded tide blue
toggleButton.Parent = screenGui

local toggleCorner = Instance.new("UICorner")
toggleCorner.CornerRadius = UDim.new(0, 10)
toggleCorner.Parent = toggleButton

-- ---------- panel ----------

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0, 1)
-- x = 330 so it clears the RELICS panel (20 + 300 width + 10 gap) when
-- both are open at once; its own button stays at x = 170.
panel.Position = UDim2.new(0, 330, 0.92, -54)
panel.Size = UDim2.fromOffset(320, 420)
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
title.Text = "INDEX"
title.Parent = panel

local list = Instance.new("ScrollingFrame")
list.Name = "List"
list.Position = UDim2.fromOffset(10, 40)
list.Size = UDim2.new(1, -20, 1, -50)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 6
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.CanvasSize = UDim2.new()
list.Parent = panel

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 4)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = list

-- ---------- callback ----------

local fetchCollection: (() -> { [string]: boolean })? = nil

function CollectionUI.onCollectionRequested(fetch: () -> { [string]: boolean })
	fetchCollection = fetch
end

-- ---------- rows ----------

local function makeTierHeader(rarityName: string, layoutOrder: number)
	local header = Instance.new("TextLabel")
	header.Name = rarityName .. "Header"
	header.Size = UDim2.new(1, 0, 0, 26)
	header.BackgroundTransparency = 1
	header.Font = Enum.Font.GothamBold
	header.TextSize = 15
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.TextColor3 = RelicUtil.rarityColor(rarityName)
	header.Text = rarityName
	header.LayoutOrder = layoutOrder
	header.Parent = list
end

local function makeRelicRow(relicName: string, found: boolean, layoutOrder: number)
	local row = Instance.new("TextLabel")
	row.Name = relicName
	row.Size = UDim2.new(1, 0, 0, 22)
	row.BackgroundTransparency = 1
	row.Font = Enum.Font.Gotham
	row.TextSize = 14
	row.TextXAlignment = Enum.TextXAlignment.Left
	if found then
		row.TextColor3 = Color3.fromRGB(240, 230, 210)
		row.Text = "  " .. relicName
	else
		row.TextColor3 = Color3.fromRGB(110, 100, 90)
		row.Text = "  ???"
	end
	row.LayoutOrder = layoutOrder
	row.Parent = list
end

-- ---------- refreshing ----------

function CollectionUI.refresh()
	if fetchCollection == nil then
		return
	end
	local discovered = fetchCollection()

	for _, child in list:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end

	local foundCount = 0
	local order = 0
	-- Walk tiers rarest-first so the exciting stuff is at the top.
	for tierIndex = #Config.Rarities, 1, -1 do
		local rarityName = Config.Rarities[tierIndex].name
		order += 1
		makeTierHeader(rarityName, order)
		for _, relic in Config.Relics[rarityName] do
			local found = discovered[relic.name] == true
			if found then
				foundCount += 1
			end
			order += 1
			makeRelicRow(relic.name, found, order)
		end
	end

	title.Text = ("INDEX  %d / %d"):format(foundCount, totalRelics)
end

function CollectionUI.refreshIfOpen()
	if panel.Visible then
		CollectionUI.refresh()
	end
end

toggleButton.Activated:Connect(function()
	panel.Visible = not panel.Visible
	if panel.Visible then
		CollectionUI.refresh()
	end
end)

return CollectionUI
