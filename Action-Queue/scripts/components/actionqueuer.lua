
local GeoUtil = require("utils/geoutil")
local Image = require("widgets/image")
local headings = {[0] = true, [45] = false, [90] = false, [135] = true, [180] = true, [225] = false, [270] = false, [315] = true, [360] = true}
local easy_stack = {minisign_item = "structure", minisign_drawn = "structure", spidereggsack = "spiderden"}
local entity_morph = {spiderhole = "spiderhole_rock"}
local moving_target = {tumbleweed = true}
local deploy_spacing = {wall = 1, fence = 1, trap = 2, mine = 2, turf = 4, moonbutterfly = 4}
local drop_spacing = {trap = 2}
local unselectable_tags = {"DECOR", "FX", "INLIMBO", "NOCLICK", "player"}
local selection_thread_id = "actionqueue_selection_thread"
local action_thread_id = "actionqueue_action_thread"
local allowed_actions = {}
for _, category in pairs({"allclick", "leftclick", "rightclick", "single", "noworkdelay", "tools", "autocollect", "collect"}) do
    allowed_actions[category] = {}
end
local offsets = {}
for i, offset in pairs({{0,0},{0,1},{1,1},{1,0},{1,-1},{0,-1},{-1,-1},{-1,0},{-1,1}}) do
    offsets[i] = Point(offset[1] * 1.5, 0, offset[2] * 1.5)
end

local DebugPrint = TUNING.ACTION_QUEUE_DEBUG_MODE and function(...)
    local msg = "[ActionQueue]"
    for i = 1, arg.n do
        msg = msg.." "..tostring(arg[i])
    end
    print(msg)
end or function() --[[disabled]] end

local function AddAction(category, action, testfn)
    if type(category) ~= "string" or not allowed_actions[category] then
        DebugPrint("Category doesn't exist:", category)
        return
    end
    local action_ = type(action) == "string" and ACTIONS[action] or action
    if type(action_) ~= "table" or not action_.id then
        DebugPrint("Action doesn't exist:", action)
        return
    end
    if testfn ~= nil and testfn ~= true and type(testfn) ~= "function" then
        DebugPrint("testfn should be true, a function that returns a boolean, or nil:", testfn, "type:", type(testfn))
        return
    end
    local modifier = allowed_actions[category][action_] and (testfn and "modified" or "removed") or (testfn and "added")
    if not modifier then return end
    allowed_actions[category][action_] = testfn
    DebugPrint("Successfully", modifier, action_.id, "action in", category, "category.")
end

local function AddActionList(category, ...)
    for _, action in pairs({...}) do
        AddAction(category, action, true)
    end
end

local function RemoveActionList(category, ...)
    for _, action in pairs({...}) do
        AddAction(category, action)
    end
end

--[[global console functions]]
AddActionQueuerAction = AddAction
RemoveActionQueuerAction = AddAction
AddActionQueuerActionList = AddActionList
RemoveActionQueuerActionList = RemoveActionList

--[[allclick]]
AddActionList("allclick", "CHOP", "MINE", "NET")
AddAction("allclick", "ATTACK", function(target)
    return target:HasTag("wall")
end)
--[[leftclick]]
AddActionList("leftclick", "ADDFUEL", "ADDWETFUEL", "CHECKTRAP", "COMBINESTACK", "COOK", "DECORATEVASE", "DIG", "DRAW", "DRY",
"EAT", "FERTILIZE", "FILL", "GIVE", "HAUNT", "LOWER_SAIL_BOOST", "PLANT", "RAISE_SAIL", "REPAIR_LEAK", "SEW", "TAKEITEM", "UPGRADE")
AddAction("leftclick", "ACTIVATE", function(target)
    return target.prefab == "dirtpile"
end)
AddAction("leftclick", "HARVEST", function(target)
    return target.prefab ~= "birdcage"
end)
AddAction("leftclick", "HEAL", function(target)
    --ThePlayer can only heal themselves, not other players
    return target == ThePlayer or not target:HasTag("player")
end)
AddAction("leftclick", "PICK", function(target)
    return target.prefab ~= "flower_evil"
end)
AddAction("leftclick", "PICKUP", function(target)
    return target.prefab ~= "trap" and target.prefab ~= "birdtrap"
       and not target:HasTag("mineactive") and not target:HasTag("minesprung")
end)
AddAction("leftclick", "SHAVE", function(target)
    return target:HasTag("brushable")
end)
--[[rightclick]]
AddActionList("rightclick", "CASTSPELL", "COOK", "DIG", "DISMANTLE","EAT",
"FEEDPLAYER", "HAMMER", "REPAIR", "RESETMINE", "TURNON", "TURNOFF", "UNWRAP")
--[[single]]
AddActionList("single", "CASTSPELL", "DECORATEVASE")
--[[noworkdelay]]
AddActionList("noworkdelay", "ADDFUEL", "ADDWETFUEL", "ATTACK", "CHOP", "COOK", "DIG", "DRY", "EAT",
"FERTILIZE", "FILL", "HAMMER", "HARVEST", "HEAL", "MINE", "PLANT", "REPAIR", "TERRAFORM", "UPGRADE")
AddAction("noworkdelay", "GIVE", function(target)
    return target:HasTag("trader")
end)
AddAction("noworkdelay", "NET", function(target)
    return not ThePlayer.components.locomotor or not target:HasTag("butterfly")
end)
--[[tools]]
AddActionList("tools", "ATTACK", "CHOP", "DIG", "HAMMER", "MINE", "NET")
--[[autocollect]]
AddActionList("autocollect", "CHOP", "DIG", "HAMMER", "HARVEST", "MINE", "PICK", "PICKUP", "RESETMINE")
AddAction("autocollect", "GIVE", function(target)
    return target.prefab ~= "mushroom_farm" and target.prefab ~= "moonbase" and not target:HasTag("gemsocket")
end)
--[[collect]]
AddActionList("collect", "HARVEST", "PICKUP")
AddAction("collect", "PICK", function(target)
    return not target:HasTag("flower")
end)

local ActionQueuer = Class(function(self, inst)
    self.inst = inst
    self.selection_widget = Image("images/selection_square.xml", "selection_square.tex")
    self.selection_widget:Hide()
    self.clicked = false
    self.TL, self.TR, self.BL, self.BR = nil, nil, nil, nil
    TheInput:AddMoveHandler(function(x, y)
        self.screen_x, self.screen_y = x, y
        self.queued_movement = true
    end)
    --Maps ent to key and rightclick(true or false) to value
    self.selected_ents = {}
    self.selection_thread = nil
    self.action_thread = nil
    self.action_delay = FRAMES * 3
    self.work_delay = FRAMES * 6
    self.color = {x = 1, y = 1, z = 1}
    self.deploy_on_grid = false
    self.auto_collect = false
    self.endless_deploy = false
    self.last_click = {time = 0}
    self.double_click_speed = 0.4
    self.double_click_range = 15
    self.AddAction = AddAction
    self.RemoveAction = AddAction
    self.AddActionList = AddActionList
    self.RemoveActionList = RemoveActionList
end)

local function IsValidEntity(ent)
    return ent and ent.Transform and ent:IsValid() and not ent:HasTag("INLIMBO")
end

local function IsHUDEntity()
    local ent = TheInput:GetWorldEntityUnderMouse()
    return ent and ent:HasTag("INLIMBO") or TheInput:GetHUDEntityUnderMouse()
end

local function CheckAllowedActions(category, action, target)
    local allowed_action = allowed_actions[category][action]
    return allowed_action and (allowed_action == true or allowed_action(target))
end

local function GetWorldPosition(screen_x, screen_y)
    return Point(TheSim:ProjectScreenPos(screen_x, screen_y))
end

local function GetDeploySpacing(item)
    for key, spacing in pairs(deploy_spacing) do
        if item.prefab:find(key) or item:HasTag(key) then return spacing end
    end
    local spacing = item.replica.inventoryitem:DeploySpacingRadius()
    return spacing ~= 0 and spacing or 1
end

local function GetDropSpacing(item)
    for key, spacing in pairs(drop_spacing) do
        if item.prefab:find(key) or item:HasTag(key) then return spacing end
    end
    return 1
end

local function CompareDeploySpacing(item, spacing)
    return item and item.replica.inventoryitem and item.replica.inventoryitem.classified
       and item.replica.inventoryitem.classified.deployspacing:value() == spacing
end

local function GetHeadingDir()
    local dir = headings[TheCamera.heading]
    if dir ~= nil then return TheCamera.heading, dir end
    for heading, dir in pairs(headings) do --diagonal priority
        local check_angle = heading % 2 ~= 0 and 23 or 22.5
        if math.abs(TheCamera.heading - heading) < check_angle then
            return heading, dir
        end
    end
end

local function GetAccessibleTilePosition(pos)
    local ent_blockers = TheSim:FindEntities(pos.x, 0, pos.z, 4, {"blocker"})
    for _, offset in pairs(offsets) do
        local offset_pos = offset + pos
        for _, ent in pairs(ent_blockers) do
            local ent_radius = ent:GetPhysicsRadius(0) + 0.6 --character size + 0.1
            if offset_pos:DistSq(ent:GetPosition()) < ent_radius * ent_radius then
                offset_pos = nil
                break
            end
        end
        if offset_pos then return offset_pos end
    end
    return nil
end

function ActionQueuer:SetToothTrapSpacing(num)
    deploy_spacing.trap = num
end

function ActionQueuer:Wait(action, target)
    local current_time = GetTime()
    if action and CheckAllowedActions("noworkdelay", action, target) then
        repeat
            Sleep(self.action_delay)
        until not (self.inst.sg and self.inst.sg:HasStateTag("moving")) and not self.inst:HasTag("moving")
    else
        Sleep(self.work_delay)
        repeat
            Sleep(self.action_delay)
        until not (self.inst.sg and self.inst.sg:HasStateTag("moving")) and not self.inst:HasTag("moving")
              and self.inst:HasTag("idle") and not self.inst.components.playercontroller:IsDoingOrWorking()
    end
    DebugPrint("Time waited:", GetTime() - current_time)
end

function ActionQueuer:GetAction(target, rightclick, pos)
    local pos = pos or target:GetPosition()
    local playeractionpicker = self.inst.components.playeractionpicker
    if rightclick then
        for _, act in ipairs(playeractionpicker:GetRightClickActions(pos, target)) do
            if CheckAllowedActions("rightclick", act.action, target) then
                DebugPrint("Allowed rightclick action:", act)
                return act, true
            end
        end
    end
    for _, act in ipairs(playeractionpicker:GetLeftClickActions(pos, target)) do
        if not rightclick and CheckAllowedActions("leftclick", act.action, target)
          or CheckAllowedActions("allclick", act.action, target) then
            DebugPrint("Allowed leftclick action:", act)
            return act, false
        end
    end
    DebugPrint("No allowed action for:", target)
    return nil
end

function ActionQueuer:SendAction(act, rightclick, target)
    DebugPrint("Sending action:", act)
    local playercontroller = self.inst.components.playercontroller
    if playercontroller.ismastersim then
        self.inst.components.combat:SetTarget(nil)
        playercontroller:DoAction(act)
        return
    end
    local pos = act:GetActionPoint() or self.inst:GetPosition()
    local controlmods = 10 --force stack and force attack
    if playercontroller.locomotor then
        act.preview_cb = function()
            if rightclick then
                SendRPCToServer(RPC.RightClick, act.action.code, pos.x, pos.z, target, act.rotation, true, nil, nil, act.action.mod_name)
            else
                SendRPCToServer(RPC.LeftClick, act.action.code, pos.x, pos.z, target, true, controlmods, nil, act.action.mod_name)
            end
        end
        playercontroller:DoAction(act)
    else
        if rightclick then
            SendRPCToServer(RPC.RightClick, act.action.code, pos.x, pos.z, target, act.rotation, true, nil, act.action.canforce, act.action.mod_name)
        else
            SendRPCToServer(RPC.LeftClick, act.action.code, pos.x, pos.z, target, true, controlmods, act.action.canforce, act.action.mod_name)
        end
    end
end

function ActionQueuer:SendActionAndWait(act, rightclick, target)
    self:SendAction(act, rightclick, target)
    self:Wait(act.action, target)
end

function ActionQueuer:SetSelectionColor(r, g, b, a)
    self.selection_widget:SetTint(r, g, b, a)
    self.color.x = r * 0.5
    self.color.y = g * 0.5
    self.color.z = b * 0.5
end

function ActionQueuer:SelectionBox(rightclick)
    local previous_ents = {}
    local started_selection = false
    local start_x, start_y = self.screen_x, self.screen_y
    self.update_selection = function()
        if not started_selection then
            if math.abs(start_x - self.screen_x) + math.abs(start_y - self.screen_y) < 32 then
                return
            end
            started_selection = true
        end
        local xmin, xmax = start_x, self.screen_x
        if xmax < xmin then
            xmin, xmax = xmax, xmin
        end
        local ymin, ymax = start_y, self.screen_y
        if ymax < ymin then
            ymin, ymax = ymax, ymin
        end
        self.selection_widget:SetPosition((xmin + xmax) / 2, (ymin + ymax) / 2)
        self.selection_widget:SetSize(xmax - xmin + 2, ymax - ymin + 2)
        self.selection_widget:Show()
        self.TL, self.BL, self.TR, self.BR = GetWorldPosition(xmin, ymax), GetWorldPosition(xmin, ymin), GetWorldPosition(xmax, ymax), GetWorldPosition(xmax, ymin)
        --self.TL, self.BL, self.TR, self.BR = GetWorldPosition(xmin, ymin), GetWorldPosition(xmin, ymax), GetWorldPosition(xmax, ymin), GetWorldPosition(xmax, ymax)
        local center = GetWorldPosition((xmin + xmax) / 2, (ymin + ymax) / 2)
        local range = math.sqrt(math.max(center:DistSq(self.TL), center:DistSq(self.BL), center:DistSq(self.TR), center:DistSq(self.BR)))
        local IsBounded = GeoUtil.NewQuadrilateralTester(self.TL, self.TR, self.BR, self.BL)
        local current_ents = {}
        for _, ent in pairs(TheSim:FindEntities(center.x, 0, center.z, range, nil, unselectable_tags)) do
            if IsValidEntity(ent) then
                local pos = ent:GetPosition()
                if IsBounded(pos) then
                    if not self:IsSelectedEntity(ent) and not previous_ents[ent] then
                        local act, rightclick_ = self:GetAction(ent, rightclick, pos)
                        if act then self:SelectEntity(ent, rightclick_) end
                    end
                    current_ents[ent] = true
                end
            end
        end
        for ent in pairs(previous_ents) do
            if not current_ents[ent] then
                self:DeselectEntity(ent)
            end
        end
        previous_ents = current_ents
    end
    self.selection_thread = StartThread(function()
        while self.inst:IsValid() do
            if self.queued_movement then
                self.update_selection()
                self.queued_movement = false
            end
            Sleep(FRAMES)
        end
        self:ClearSelectionThread()
    end, selection_thread_id)
end

function ActionQueuer:CherryPick(rightclick)
    local current_time = GetTime()
    if current_time - self.last_click.time < self.double_click_speed and self.last_click.prefab then
        local x, y, z = self.last_click.pos:Get()
        for _, ent in pairs(TheSim:FindEntities(x, 0, z, self.double_click_range, nil, unselectable_tags)) do
            if ent.prefab == self.last_click.prefab and IsValidEntity(ent) and not self:IsSelectedEntity(ent) then
                local act, rightclick_ = self:GetAction(ent, rightclick)
                if act and act.action == self.last_click.action then
                    self:SelectEntity(ent, rightclick_)
                end
            end
        end
        self.last_click.prefab = nil
        return
    end
    for _, ent in ipairs(TheInput:GetAllEntitiesUnderMouse()) do
        if IsValidEntity(ent) then
            local act, rightclick_ = self:GetAction(ent, rightclick)
            if act then
                self:ToggleEntitySelection(ent, rightclick_)
                self.last_click = {prefab = ent.prefab, pos = ent:GetPosition(), action = act.action, time = current_time}
                break
            end
        end
    end
end

function ActionQueuer:OnDown(rightclick)
    self:ClearSelectionThread()
    if self.inst:IsValid() and not IsHUDEntity() then
        self.clicked = true
        self:SelectionBox(rightclick)
        self:CherryPick(rightclick)
    end
end

function ActionQueuer:OnUp(rightclick)
    self:ClearSelectionThread()
    if self.clicked then
        self.clicked = false
        if self.action_thread then return end
        if self:IsWalkButtonDown() then
            self:ClearSelectedEntities()
        elseif next(self.selected_ents) then
            self:ApplyToSelection()
        elseif rightclick then
            local active_item = self:GetActiveItem()
            if active_item then
                if easy_stack[active_item.prefab] then
                    local ent = TheInput:GetWorldEntityUnderMouse()
                    if ent and ent:HasTag(easy_stack[active_item.prefab]) then
                        local act = BufferedAction(self.inst, nil, ACTIONS.DEPLOY, active_item, ent:GetPosition())
                        self:SendAction(act, true)
                        return
                    end
                end
                if active_item.replica.inventoryitem:IsDeployable(self.inst) then
                    self:DeployToSelection(self.DeployActiveItem, GetDeploySpacing(active_item), active_item)
                else
                    self:DeployToSelection(self.DropActiveItem, GetDropSpacing(active_item), active_item)
                end
                return
            end
            local equip_item = self:GetEquippedItemInHand()
            if equip_item and equip_item.prefab == "pitchfork" then
                self:DeployToSelection(self.TerraformAtPoint, 4, equip_item)
            end
        elseif self.inst.components.playercontroller.placer then
            local playercontroller = self.inst.components.playercontroller
            local recipe = playercontroller.placer_recipe
            local rotation = playercontroller.placer:GetRotation()
            local skin = playercontroller.placer_recipe_skin
            local builder = self.inst.replica.builder
            local spacing = recipe.min_spacing > 2 and 4 or 2
            self:DeployToSelection(function(self, pos, item)
                if not builder:IsBuildBuffered(recipe.name) then
                    if not builder:CanBuild(recipe.name) then return false end
                    builder:BufferBuild(recipe.name)
                end
                if builder:CanBuildAtPoint(pos, recipe, rotation) then
                    builder:MakeRecipeAtPoint(recipe, pos, rotation, skin)
                    self:Wait()
                end
                return true
            end, spacing)
        end
    end
end

function ActionQueuer:IsWalkButtonDown()
    return self.inst.components.playercontroller:IsAnyOfControlsPressed(CONTROL_MOVE_UP, CONTROL_MOVE_DOWN, CONTROL_MOVE_LEFT, CONTROL_MOVE_RIGHT)
end

function ActionQueuer:GetActiveItem()
    return self.inst.replica.inventory:GetActiveItem()
end

function ActionQueuer:GetEquippedItemInHand()
    return self.inst.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
end

function ActionQueuer:GetNewActiveItem(prefab)
    local inventory = self.inst.replica.inventory
    local body_item = inventory:GetEquippedItem(EQUIPSLOTS.BODY)
    local backpack = body_item and body_item.replica.container
    for _, inv in pairs(backpack and {inventory, backpack} or {inventory}) do
        for slot, item in pairs(inv:GetItems()) do
            if item and item.prefab == prefab then
                inv:TakeActiveItemFromAllOfSlot(slot)
                return item
            end
        end
    end
end

function ActionQueuer:GetNewEquippedItemInHand(prefab)
    local inventory = self.inst.replica.inventory
    local body_item = inventory:GetEquippedItem(EQUIPSLOTS.BODY)
    local backpack = body_item and body_item.replica.container
    for _, inv in pairs(backpack and {inventory, backpack} or {inventory}) do
        for slot, item in pairs(inv:GetItems()) do
            if item and item.prefab == prefab then
                inventory:UseItemFromInvTile(item)
                return item
            end
        end
    end
end

function ActionQueuer:DeployActiveItem(pos, item)
    local active_item = self:GetActiveItem() or self:GetNewActiveItem(item.prefab)
    if not active_item then return false end
    local inventoryitem = active_item.replica.inventoryitem
    if inventoryitem and inventoryitem:CanDeploy(pos, nil, self.inst) then
        local act = BufferedAction(self.inst, nil, ACTIONS.DEPLOY, active_item, pos)
        local playercontroller = self.inst.components.playercontroller
        if playercontroller.deployplacer then
            act.rotation = playercontroller.deployplacer.Transform:GetRotation()
        end
        self:SendActionAndWait(act, true)
        if not playercontroller.ismastersim and not CompareDeploySpacing(active_item, DEPLOYSPACING.NONE) then
            while inventoryitem and inventoryitem:CanDeploy(pos, nil, self.inst) do
                Sleep(self.action_delay)
                if self.inst:HasTag("idle") then
                    self:SendActionAndWait(act, true)
                end
            end
        end
    end
    return true
end

function ActionQueuer:DropActiveItem(pos, item)
    local active_item = self:GetActiveItem() or self:GetNewActiveItem(item.prefab)
    if not active_item then return false end
    if #TheSim:FindEntities(pos.x, 0, pos.z, 0.1, nil, unselectable_tags) == 0 then
        local act = BufferedAction(self.inst, nil, ACTIONS.DROP, active_item, pos)
        act.options.wholestack = false
        self:SendActionAndWait(act, false)
    end
    return true
end

function ActionQueuer:TerraformAtPoint(pos, item)
    local x, y, z = pos:Get()
    if not self:GetEquippedItemInHand() then return false end
    if TheWorld.Map:CanTerraformAtPoint(x, y, z) then
        local act = BufferedAction(self.inst, nil, ACTIONS.TERRAFORM, item, pos)
        self:SendActionAndWait(act, true)
        while TheWorld.Map:CanTerraformAtPoint(x, y, z) do
            Sleep(self.action_delay)
            if self.inst:HasTag("idle") then
                self:SendActionAndWait(act, true)
            end
        end
        if self.auto_collect then
            self:AutoCollect(pos, true)
        end
    end
    return true
end

function ActionQueuer:GetClosestTarget()
    local mindistsq, target
    local player_pos = self.inst:GetPosition()
    for ent in pairs(self.selected_ents) do
        if IsValidEntity(ent) then
            local curdistsq = player_pos:DistSq(ent:GetPosition())
            if not mindistsq or curdistsq < mindistsq then
                mindistsq = curdistsq
                target = ent
            end
        else
            self:DeselectEntity(ent)
        end
    end
    return target
end

function ActionQueuer:WaitToolReEquip()
    if not self:GetEquippedItemInHand() and not self.inst:HasTag("wereplayer") then
        self:Wait()
        return true
    end
end

function ActionQueuer:CheckEntityMorph(prefab, pos, rightclick)
    if not entity_morph[prefab] then return end
    for _, ent in pairs(TheSim:FindEntities(pos.x, 0, pos.z, 1, nil, unselectable_tags)) do
        if ent.prefab == entity_morph[prefab] then
            self:SelectEntity(ent, rightclick)
        end
    end
end

function ActionQueuer:AutoCollect(pos, collect_now)
    for _, ent in pairs(TheSim:FindEntities(pos.x, 0, pos.z, 4, nil, unselectable_tags)) do
        if IsValidEntity(ent) and not self:IsSelectedEntity(ent) then
            local act = self:GetAction(ent, false)
            if act and CheckAllowedActions("collect", act.action, ent) then
                self:SelectEntity(ent, false)
                if collect_now then
                    self:SendActionAndWait(act, false, ent)
                    self:DeselectEntity(ent)
                end
            end
        end
    end
end

function ActionQueuer:ApplyToSelection()
    self.action_thread = StartThread(function()
        self.inst:ClearBufferedAction()
        local active_item = self:GetActiveItem()
        while self.inst:IsValid() do
            local target = self:GetClosestTarget()
            if not target then break end
            local rightclick = self.selected_ents[target]
            local pos = target:GetPosition()
            local act = self:GetAction(target, rightclick, pos)
            if act and act:IsValid() then
                local tool_action = allowed_actions.tools[act.action]
                local auto_collect = CheckAllowedActions("autocollect", act.action, target)
                self:SendActionAndWait(act, rightclick, target)
                if not CheckAllowedActions("single", act.action, target) then
                    local noworkdelay = CheckAllowedActions("noworkdelay", act.action, target)
                    local current_action = act.action
                    while IsValidEntity(target) do
                        local act = self:GetAction(target, rightclick, pos)
                        if not act then
                            if active_item then
                                if noworkdelay then Sleep(self.action_delay) end --queue can exit without this delay
                                if not self:GetActiveItem() and self:GetNewActiveItem(active_item.prefab) then
                                    act = self:GetAction(target, rightclick, pos)
                                end
                            elseif tool_action and self:WaitToolReEquip() then
                                act = self:GetAction(target, rightclick, pos)
                            end
                            if not act then break end
                        end
                        if act.action ~= current_action then break end
                        self:SendActionAndWait(act, rightclick, target)
                    end
                end
                self:DeselectEntity(target)
                self:CheckEntityMorph(target.prefab, pos, rightclick)
                if active_item and not self:GetActiveItem() then
                    self:GetNewActiveItem(active_item.prefab)
                elseif tool_action then
                    self:WaitToolReEquip()
                end
                if self.auto_collect and auto_collect then
                    Sleep(FRAMES)
                    pos = moving_target[target.prefab] and self.inst:GetPosition() or pos
                    self:AutoCollect(pos, false)
                end
            else
                DebugPrint("No act or invalid")
                self:DeselectEntity(target)
            end
        end
        self:ClearActionThread()
    end, action_thread_id)
end

function ActionQueuer:DeployToSelection(deploy_fn, spacing, item)
    if not self.TL then return end
    local heading, dir = GetHeadingDir()
    local diagonal = heading % 2 ~= 0
    DebugPrint("Heading:", heading, "Diagonal:", diagonal, "Spacing:", spacing)
    DebugPrint("TL:", self.TL, "TR:", self.TR, "BL:", self.BL, "BR:", self.BR)
    local X, Z = "x", "z"
    if dir then X, Z = Z, X end
    local spacing_x = self.TL[X] > self.TR[X] and -spacing or spacing
    local spacing_z = self.TL[Z] > self.BL[Z] and -spacing or spacing
    local adjusted_spacing_x = diagonal and spacing * 1.4 or spacing
    local adjusted_spacing_z = diagonal and spacing * 0.7 or spacing
    local width = math.floor(self.TL:Dist(self.TR) / adjusted_spacing_x)
    local height = self.endless_deploy and 100 or math.floor(self.TL:Dist(self.BL) / (width < 1 and adjusted_spacing_x or adjusted_spacing_z))
    DebugPrint("Width:", width + 1, "Height:", height + 1) --since counting from 0
    local start_x, _, start_z = self.TL:Get()
    local terraforming = false
    if deploy_fn == self.TerraformAtPoint or item and item:HasTag("groundtile") then
        start_x, _, start_z = TheWorld.Map:GetTileCenterPoint(start_x, 0, start_z)
        terraforming = true
    elseif deploy_fn == self.DropActiveItem or item and (item:HasTag("wallbuilder") or item:HasTag("fencebuilder")) then
        start_x, start_z = math.floor(start_x) + 0.5, math.floor(start_z) + 0.5
    elseif self.deploy_on_grid then
        start_x, start_z = math.floor(start_x * 2 + 0.5) * 0.5, math.floor(start_z * 2 + 0.5) * 0.5
    end
    local cur_pos = Point()
    local count = {x = 0, y = 0, z = 0}
    local row_swap = 1
    self.action_thread = StartThread(function()
        self.inst:ClearBufferedAction()
        while self.inst:IsValid() do
            cur_pos.x = start_x + spacing_x * count.x
            cur_pos.z = start_z + spacing_z * count.z
            if diagonal then
                if width < 1 then
                    if count[Z] > height then break end
                    count[X] = count[X] - 1
                    count[Z] = count[Z] + 1
                else
                    local row = math.floor(count.y / 2)
                    if count[X] + row > width or count[X] + row < 0 then
                        count.y = count.y + 1
                        if count.y > height then break end
                        row_swap = -row_swap
                        count[X] = count[X] + row_swap - 1
                        count[Z] = count[Z] + row_swap
                        cur_pos.x = start_x + spacing_x * count.x
                        cur_pos.z = start_z + spacing_z * count.z
                    end
                    count.x = count.x + row_swap
                    count.z = count.z + row_swap
                end
            else
                if count[X] > width or count[X] < 0 then
                    count[Z] = count[Z] + 1
                    if count[Z] > height then break end
                    row_swap = -row_swap
                    count[X] = count[X] + row_swap
                    cur_pos.x = start_x + spacing_x * count.x
                    cur_pos.z = start_z + spacing_z * count.z
                end
                count[X] = count[X] + row_swap
            end
            local accessible_pos = cur_pos
            if terraforming then
                accessible_pos = GetAccessibleTilePosition(cur_pos)
            end
            DebugPrint("Current Position:", accessible_pos or "skipped")
            if accessible_pos then
                if not deploy_fn(self, accessible_pos, item) then break end
            end
        end
        self:ClearActionThread()
        self.inst:DoTaskInTime(0, function() if next(self.selected_ents) then self:ApplyToSelection() end end)
    end, action_thread_id)
end

function ActionQueuer:RepeatRecipe(builder, recipe, skin)
    self.action_thread = StartThread(function()
        self.inst:ClearBufferedAction()
        while self.inst:IsValid() and builder:CanBuild(recipe.name) do
            builder:MakeRecipeFromMenu(recipe, skin)
            Sleep(self.action_delay)
        end
        self:ClearActionThread()
    end, action_thread_id)
end

function ActionQueuer:StartAutoFisher(target)
    self:ToggleEntitySelection(target, false)
    if self.action_thread then return end
    if self.inst.locomotor then
        self.inst.components.talker:Say("Auto fisher will not work with lag compensation enabled")
        self:DeselectEntity(target)
        return
    end
    self.action_thread = StartThread(function()
        self.inst:ClearBufferedAction()
        self.auto_fishing = true
        while self.auto_fishing and self.inst:IsValid() and next(self.selected_ents) do
            for pond in pairs(self.selected_ents) do
                local fishingrod = self:GetEquippedItemInHand() or self:GetNewEquippedItemInHand("fishingrod")
                if not fishingrod or self:GetActiveItem() then self.auto_fishing = false break end
                local pos = pond:GetPosition()
                local fish_act = BufferedAction(self.inst, pond, ACTIONS.FISH, fishingrod, pos)
                while not self.inst:HasTag("nibble") do
                    if not self.inst:HasTag("fishing") and self.inst:HasTag("idle") then
                        self:SendAction(fish_act, false, pond)
                    end
                    Sleep(self.action_delay)
                end
                local catch_act = BufferedAction(self.inst, pond, ACTIONS.REEL, fishingrod, pos)
                self:SendAction(catch_act, false, pond)
                Sleep(self.action_delay)
                self:SendActionAndWait(catch_act, false, pond)
                local fish = FindEntity(self.inst, 2, nil, {"fish"})
                if fish then
                    local pickup_act = BufferedAction(self.inst, fish, ACTIONS.PICKUP, nil, fish:GetPosition())
                    self:SendActionAndWait(pickup_act, false, fish)
                end
            end
        end
        self:ClearActionThread()
        self:ClearSelectedEntities()
    end, action_thread_id)
end

function ActionQueuer:IsSelectedEntity(ent)
    --nil check because boolean value
    return self.selected_ents[ent] ~= nil
end

function ActionQueuer:SelectEntity(ent, rightclick)
    if self:IsSelectedEntity(ent) then return end
    self.selected_ents[ent] = rightclick
    if not ent.components.highlight then
        ent:AddComponent("highlight")
    end
    local highlight = ent.components.highlight
    highlight.highlight_add_colour_red = nil
    highlight.highlight_add_colour_green = nil
    highlight.highlight_add_colour_blue = nil
    highlight:SetAddColour(self.color)
    highlight.highlit = true
end

function ActionQueuer:DeselectEntity(ent)
    if self:IsSelectedEntity(ent) then
        self.selected_ents[ent] = nil
        if ent:IsValid() and ent.components.highlight then
            ent.components.highlight:UnHighlight()
        end
    end
end

function ActionQueuer:ToggleEntitySelection(ent, rightclick)
    if self:IsSelectedEntity(ent) then
        self:DeselectEntity(ent)
    else
        self:SelectEntity(ent, rightclick)
    end
end

function ActionQueuer:ClearSelectedEntities()
    for ent in pairs(self.selected_ents) do
        self:DeselectEntity(ent)
    end
end

function ActionQueuer:ClearSelectionThread()
    if self.selection_thread then
        DebugPrint("Thread cleared:", self.selection_thread.id)
        KillThreadsWithID(self.selection_thread.id)
        self.selection_thread:SetList(nil)
        self.selection_thread = nil
        self.selection_widget:Hide()
    end
end

function ActionQueuer:ClearActionThread()
    if self.action_thread then
        DebugPrint("Thread cleared:", self.action_thread.id)
        KillThreadsWithID(self.action_thread.id)
        self.action_thread:SetList(nil)
        self.action_thread = nil
        self.auto_fishing = false
        self.TL, self.TR, self.BL, self.BR = nil, nil, nil, nil
    end
end

function ActionQueuer:ClearAllThreads()
    self:ClearActionThread()
    self:ClearSelectionThread()
    self:ClearSelectedEntities()
    self.selection_widget:Kill()
end

ActionQueuer.OnRemoveEntity = ActionQueuer.ClearAllThreads
ActionQueuer.OnRemoveFromEntity = ActionQueuer.ClearAllThreads

return ActionQueuer
