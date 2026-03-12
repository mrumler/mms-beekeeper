local VORPcore = exports.vorp_core:GetCore()
local BccUtils = exports['bcc-utils'].initiate()
local Menu = exports.vorp_menu:GetMenuData()
local progressbar = exports.vorp_progressbar:initiate()

---- LOCALS ---

local CreatedBeehives = {}
local CreatedBlips = {}
local BeehiveData = nil
local CharID = nil
local ThreadRunning = false
local CreatedWildBeehives = {}
local SmokedBeehives = {}
local TakenBeeBeehives = {}
local TakenQueenBeehives = {}
local TakenHoneyBeehives = {}
local bees_cloud_group = "core"
local bees_cloud_name = "ent_amb_insect_bee_swarm"
local CreatedFXSwarms = {}
local WildHivesSpawned = false
local WildHiveTimers = {}
local StartBeeFX

-----------------------------------------------
---------------- BeeFx Helpers  ---------------
-----------------------------------------------

local function GetBeeFXCoords(CurrentHive, isWildHive)
    if isWildHive then
        return CurrentHive.x, CurrentHive.y, CurrentHive.z
    end

    return CurrentHive.Coords.x, CurrentHive.Coords.y, CurrentHive.Coords.z
end

local function GetWildHiveKey(CurrentHive)
    return string.format("%.3f:%.3f:%.3f", CurrentHive.x, CurrentHive.y, CurrentHive.z)
end

local function RemoveWildHiveFromList(HiveList, CurrentHive)
    for index = #HiveList, 1, -1 do
        local Hive = HiveList[index]
        local Distance = GetDistanceBetweenCoords(
            CurrentHive.x, CurrentHive.y, CurrentHive.z,
            Hive.x, Hive.y, Hive.z,
            true
        )
        if Distance < 1.0 then
            table.remove(HiveList, index)
        end
    end
end

local function ResetWildHiveTimer(CurrentHive)
    WildHiveTimers[GetWildHiveKey(CurrentHive)] = Config.ResetWildHivesTimer * 60000
end

local function ClearWildHiveState(CurrentHive)
    RemoveWildHiveFromList(TakenHoneyBeehives, CurrentHive)
    RemoveWildHiveFromList(TakenQueenBeehives, CurrentHive)
    RemoveWildHiveFromList(TakenBeeBeehives, CurrentHive)
    RemoveWildHiveFromList(SmokedBeehives, CurrentHive)
    StartBeeFX(CurrentHive, true)
    WildHiveTimers[GetWildHiveKey(CurrentHive)] = nil
end

local function StopBeeFX(CurrentHive, isWildHive)
    local x, y, z = GetBeeFXCoords(CurrentHive, isWildHive)
    for index = #CreatedFXSwarms, 1, -1 do
        local BeesFX = CreatedFXSwarms[index]
        if BeesFX.isWildHive == isWildHive then
            local Distance = GetDistanceBetweenCoords(
                x, y, z,
                BeesFX.x, BeesFX.y, BeesFX.z,
                true
            )
            if Distance < 1.0 then
                StopParticleFxLooped(BeesFX.fx, true)
                table.remove(CreatedFXSwarms, index)
            end
        end
    end
end

local function StopPlacedHiveFX()
    for index = #CreatedFXSwarms, 1, -1 do
        local BeesFX = CreatedFXSwarms[index]
        if not BeesFX.isWildHive then
            StopParticleFxLooped(BeesFX.fx, true)
            table.remove(CreatedFXSwarms, index)
        end
    end
end

local function StopWildHiveFXEntries()
    for index = #CreatedFXSwarms, 1, -1 do
        local BeesFX = CreatedFXSwarms[index]
        if BeesFX.isWildHive then
            StopParticleFxLooped(BeesFX.fx, true)
            table.remove(CreatedFXSwarms, index)
        end
    end
end

local function ClearWildHives()
    for _, WildBeehive in ipairs(CreatedWildBeehives) do
        DeleteObject(WildBeehive)
    end
    CreatedWildBeehives = {}
    StopWildHiveFXEntries()
    WildHiveTimers = {}
end

local function SpawnHiveObject(ModelName, x, y, z, heading, rotx, roty, rotz)
    local ModelHash = GetHashKey(ModelName)
    RequestModel(ModelHash)
    while not HasModelLoaded(ModelHash) do
        Citizen.Wait(100)
    end

    local HiveObject = CreateObject(ModelHash, x, y, z, false, true, false)
    SetEntityInvincible(HiveObject, true)
    FreezeEntityPosition(HiveObject, true)
    SetEntityAlwaysPrerender(HiveObject, false)
    SetEntityVisible(HiveObject, true)

    if heading ~= nil then
        SetEntityHeading(HiveObject, heading)
    end

    if rotx ~= nil and roty ~= nil and rotz ~= nil and heading ~= nil then
        Citizen.InvokeNative(0x203BEFFDBE12E96A, HiveObject, x, y, z, heading, rotx, roty, rotz)
    end

    SetModelAsNoLongerNeeded(ModelHash)
    return HiveObject
end

StartBeeFX = function(CurrentHive, isWildHive)
    if not Config.UseBeeFX then
        return
    end

    local x, y, z = GetBeeFXCoords(CurrentHive, isWildHive)
    for _, BeesFX in ipairs(CreatedFXSwarms) do
        if BeesFX.isWildHive == isWildHive then
            local Distance = GetDistanceBetweenCoords(
                x, y, z,
                BeesFX.x, BeesFX.y, BeesFX.z,
                true
            )
            if Distance < 1.0 then
                return
            end
        end
    end

    Citizen.InvokeNative(0xA10DB07FC234DD12, bees_cloud_group)
    local BeeFXSwarm = Citizen.InvokeNative(0xBA32867E86125D3A, bees_cloud_name, x, y, z, 0.0, 0.0, 0.0, 1.0, false, false, false, false)
    CreatedFXSwarms[#CreatedFXSwarms + 1] = {
        x = x,
        y = y,
        z = z,
        fx = BeeFXSwarm,
        isWildHive = isWildHive,
    }
end

-----------------------------------------------
--------------- GetBeehivesData ---------------
-----------------------------------------------

-- Debug
Citizen.CreateThread(function()
    if Config.Debug then
        Citizen.Wait(3000)
        TriggerServerEvent('mms-beekeeper:server:GetBeehivesData')
        Citizen.Wait(300)
        TriggerEvent('mms-beekeeper:client:SpawnWildBeehives')
    end
end)

RegisterNetEvent('vorp:SelectedCharacter')
AddEventHandler('vorp:SelectedCharacter', function()
    Citizen.Wait(10000)
    TriggerServerEvent('mms-beekeeper:server:GetBeehivesData')
    TriggerEvent('mms-beekeeper:client:SpawnWildBeehives')
end)

RegisterNetEvent('mms-beekeeper:client:ReciveData')
AddEventHandler('mms-beekeeper:client:ReciveData',function(Beehives,CharIdent)
    BeehiveData = Beehives
    CharID = CharIdent
    TriggerEvent('mms-beekeeper:client:CreateBeehivesOnStart')
    Citizen.Wait(500)
    TriggerEvent('mms-beekeeper:client:StartMainThred')
end)

RegisterNetEvent('mms-beekeeper:client:ReloadData')
AddEventHandler('mms-beekeeper:client:ReloadData',function()
    ThreadRunning = false
    for _, beehive in ipairs(CreatedBeehives) do
        DeleteObject(beehive)
    end
    CreatedBeehives = {}
    for _, blips in ipairs(CreatedBlips) do
        blips:Remove()
    end
    CreatedBlips = {}
    StopPlacedHiveFX()
    TriggerServerEvent('mms-beekeeper:server:GetBeehivesData')
end)

-----------------------------------------------
--------------- Create Beehive ----------------
-----------------------------------------------

RegisterNetEvent('mms-beekeeper:client:CreateBeehive')
AddEventHandler('mms-beekeeper:client:CreateBeehive',function()
    local BeehiveClose = false
    local BeehiveProp = Config.Props[Config.FixProp].BeehiveBox

    if Config.UseRandomHive then
        local MaxIndex = #Config.Props
        local RandomIndex = math.random(1,MaxIndex)
        BeehiveProp = Config.Props[RandomIndex].BeehiveBox
    end


    local MyCoords = GetEntityCoords(PlayerPedId())
    local MyHeading = GetEntityHeading(PlayerPedId())
    local SpawnCoords = GetOffsetFromEntityInWorldCoords(PlayerPedId(), 0.0, 1.0, 0.0)
    if BeehiveData ~= nil then
        for h,v in ipairs(BeehiveData) do
            local Data = json.decode(v.data)
            local Distance = GetDistanceBetweenCoords(MyCoords.x, MyCoords.y, MyCoords.z, Data.Coords.x, Data.Coords.y, Data.Coords.z, true)
            if Distance <= 5 then
                BeehiveClose = true
            end
        end
    end
    local Data = { 
        Food = 0.0,
        Water = 0.0,
        Health = 100.0,
        Clean = 0.0,
        Product = 0.0,
        BeeSettings = {
            QueenItem = '',
            QueenLabel = '',
            BeeItem = '',
            BeeLabel = '',
            Product = '',
            ProductLabel = '',
            ProductHappy = 0.0,
            ProductNormal = 0.0,
        },
        Bees = 0,
        Queen = 0,
        Coords = { 
            x = SpawnCoords.x,
            y = SpawnCoords.y,
            z = MyCoords.z -1,
            heading = MyHeading,
        },
        Sickness = {
            CurrentlySick = false,
            Type = '',
            Medicine = '',
            MedicineLabel = '',
            Intensity = 0.0,
        },
        Model = BeehiveProp,
        Helper = {
            Name = '',
            CharIdent = 0,
        },
        Damage = 0.0,
    }
    if not BeehiveClose then
        TriggerServerEvent('mms-beekeeper:server:SaveBeehiveToDatabase',Data)
    else
        VORPcore.NotifyRightTip(_U('ToCloseToAnotherHive'),5000)
    end
end)

-----------------------------------------------
------------ Create Beehives OnStart ----------
-----------------------------------------------

RegisterNetEvent('mms-beekeeper:client:CreateBeehivesOnStart')
AddEventHandler('mms-beekeeper:client:CreateBeehivesOnStart',function()
    for h,v in ipairs(BeehiveData) do
        local Data = json.decode(v.data)
        if Data.Coords.heading == nil then
            Data.Coords.heading = 100
        end
        local Beehive = SpawnHiveObject(Data.Model, Data.Coords.x, Data.Coords.y, Data.Coords.z, Data.Coords.heading)
        CreatedBeehives[#CreatedBeehives + 1] = Beehive
        if Data.Bees > 0 then
            StartBeeFX(Data, false)
        end
        if Config.UseBlips then
            if v.charident == CharID then
                local BeehiveBlip = BccUtils.Blips:SetBlip(Config.BlipName, Config.BlipSprite, Config.BlipScale, Data.Coords.x, Data.Coords.y, Data.Coords.z)
                CreatedBlips[#CreatedBlips + 1] = BeehiveBlip
            end
        end

    end
end)

-----------------------------------------------
------------------ MainThread -----------------
-----------------------------------------------

RegisterNetEvent('mms-beekeeper:client:StartMainThred')
AddEventHandler('mms-beekeeper:client:StartMainThred',function()
    ThreadRunning = true
    -- Owner Prompts
    local BeehivePromptGroup = BccUtils.Prompts:SetupPromptGroup()
    local ManageBeehive = BeehivePromptGroup:RegisterPrompt(_U('ManageBeehive'), 0x760A9C6F, 1, 1, true, 'click')--, {timedeventhash = 'SHORT_TIMED_EVENT'}) -- KEY G
    local DeleteBeehive = BeehivePromptGroup:RegisterPrompt(_U('DeleteBeehive'), 0x27D1C284, 1, 1, true, 'hold', {timedeventhash = 'SHORT_TIMED_EVENT'}) -- KEY R

    -- Helper Only Manage
    local BeehiveHelperPromptGroup = BccUtils.Prompts:SetupPromptGroup()
    local ManageHelperBeehive = BeehiveHelperPromptGroup:RegisterPrompt(_U('ManageBeehive'), 0x760A9C6F, 1, 1, true, 'click')--, {timedeventhash = 'SHORT_TIMED_EVENT'}) -- KEY G

    if BeehiveData ~= nil then
        while ThreadRunning do
            Citizen.Wait(5)
            local MyCoords = GetEntityCoords(PlayerPedId())
            for h,v in ipairs(BeehiveData) do
                local Data = json.decode(v.data)
                if v.charident == CharID then
                    local Distance = GetDistanceBetweenCoords(MyCoords.x, MyCoords.y, MyCoords.z, Data.Coords.x, Data.Coords.y, Data.Coords.z, true)
                    if Distance <= 2 then
                        BeehivePromptGroup:ShowGroup(_U('BeehivePromptGroup'))

                        if ManageBeehive:HasCompleted() then
                            TriggerServerEvent('mms-beekeeper:server:GetDataForMenu',v.id)
                        end

                        if DeleteBeehive:HasCompleted() then
                            TriggerServerEvent('mms-beekeeper:server:DeleteBeehive',v.id)
                            Citizen.Wait(500)
                        end

                    end
                end
                if Data.Helper.CharIdent == CharID then
                    local Distance2 = GetDistanceBetweenCoords(MyCoords.x, MyCoords.y, MyCoords.z, Data.Coords.x, Data.Coords.y, Data.Coords.z, true)
                    if Distance2 <= 2 then
                        BeehiveHelperPromptGroup:ShowGroup(_U('BeehivePromptGroup'))

                        if ManageHelperBeehive:HasCompleted() then
                            TriggerServerEvent('mms-beekeeper:server:GetDataForMenu',v.id)
                        end

                    end
                end
            end
        end
    else
        TriggerEvent('mms-beekeeper:client:ReloadData')
        if Config.Debug then print('DEBUG: Reloading Data') end
    end
end)

-----------------------------------------------
------------------- Menu Data -----------------
-----------------------------------------------

RegisterNetEvent('mms-beekeeper:client:OpenMenu')
AddEventHandler('mms-beekeeper:client:OpenMenu',function(CurrentBeehive)
    Data = json.decode(CurrentBeehive[1].data)
    BeehiveMenu = {
        {
            label = _U('QueenLabel') .. Data.BeeSettings.QueenLabel .. ' ' .. Data.Queen,
            value = "AddQueen",
            desc = _U('QueenLabelDesc'),
            itemHeight = "3vh"
        },
        {
            label = _U('BeeLabel') .. Data.BeeSettings.BeeLabel .. ' ' .. Data.Bees,
            value = "AddBees",
            desc = _U('BeeLabelDesc'),
            itemHeight = "3vh"
        },
        {
            label = _U('ProductLabel') .. Data.BeeSettings.ProductLabel .. ' ' .. math.floor(Data.Product / Config.ProduktPerHoney),
            value = "TakeProduct",
            desc = Data.BeeSettings.ProductLabel .. _U('ProductLabelDesc'),
            itemHeight = "3vh"
        },
        {
            label = _U('FoodLabel') .. Data.Food,
            value = "AddFood",
            desc = _U('FoodLabelDesc'),
            itemHeight = "3vh"
        },
        {
            label = _U('WaterLabel') .. Data.Water,
            value = "AddWater",
            desc = _U('WaterLabelDesc'),
            itemHeight = "3vh"
        },
        {
            label = _U('CleanLabel') .. Data.Clean,
            value = "AddClean",
            desc = _U('CleanLabelDesc'),
            itemHeight = "3vh"
        },
        {
            label = _U('HealthLabel') .. Data.Health,
            value = "AddHealth",
            desc = _U('HealthLabelDesc'),
            itemHeight = "3vh"
        },
        {
            label = _U('SicknessLabel') .. Data.Sickness.Type .. ' ' .. Data.Sickness.Intensity,
            value = "HealSickness",
            desc = _U('SicknessLabelDesc') .. Data.Sickness.MedicineLabel,
            itemHeight = "3vh"
        },
        {
            label = _U('AddHelperLabel') .. Data.Helper.Name,
            value = "SetHelper",
            desc = _U('AddHelperLabelDesc'),
            itemHeight = "3vh"
        },
        {
            label = _U('RemoveHelperLabel') .. Data.Helper.Name,
            value = "RemoveHelper",
            desc = _U('RemoveHelperLabelDesc'),
            itemHeight = "3vh"
        },
        {
            label = _U('ChangePosition'),
            value = "ChangePosition",
            desc = _U('ChangePositionDesc'),
            itemHeight = "3vh"
        },
    }

    Menu.Open("default",GetCurrentResourceName(),"BeehiveMenu", -- unique namespace will allow the menu to open where you left off

    {
        title = _U('HiveMenuHeader'),
        subtext = _U('HiveMenuSubHeader'),
        align = "top-center", -- top-right , top-center , top-left
        elements = BeehiveMenu, -- elements needed
        itemHeight = "4vh", -- set all elements to this height if they are not definded in the element (optional)
    },
        
        
    function(data, Menu)

        if data.current.value == "AddFood" then
            CrouchAnim()
            Progressbar(Config.FeedTime*1000,_U('FeedingHive'))
            TriggerServerEvent('mms-beekeeper:server:AddFood',CurrentBeehive[1].id)
            Menu.close()
        end

        if data.current.value == "TakeProduct" then
            local HowMany = {
                type = "enableinput", -- don't touch
                inputType = "input", -- input type
                button = _U('ConfirmButton'), -- button name
                placeholder = "0", -- placeholder name
                style = "block", -- don't touch
                attributes = {
                    inputHeader = _U('HowManyWannaTake'), -- header
                    type = "number", -- inputype text, number,date,textarea ETC
                    pattern = "[0-9]", --  only numbers "[0-9]" | for letters only "[A-Za-z]+" 
                    title = "numbers only", -- if input doesnt match show this message
                    style = "border-radius: 10px; background-color: ; border:none;"-- style 
                }
            }
            TriggerEvent("vorpinputs:advancedInput", json.encode(HowMany),function(result)
                local HoneyAmount = tonumber(result)
                local HoneyItem = Data.BeeSettings.Product
                local ProductNeeded = Config.ProduktPerHoney * HoneyAmount
                local JarsNeeded = HoneyAmount
                local ServerInfo =  VORPcore.Callback.TriggerAwait('mms-beekeeper:callback:GetJarAmount',HoneyAmount,HoneyItem)
                local Jars = ServerInfo[1]
                local CanCarry = ServerInfo[2]
                if CanCarry then
                    if Jars >= JarsNeeded then
                        if Data.Product >= ProductNeeded then
                            CrouchAnim()
                            Progressbar(Config.TakeHoneyTime*1000*HoneyAmount,_U('TakingHoney'))
                            TriggerServerEvent('mms-beekeeper:server:TakeProduct',CurrentBeehive[1].id,HoneyAmount)
                            Menu.close()
                        else
                            VORPcore.NotifyRightTip(_U('NotEnoghProductinHive'),5000)
                        end
                    else
                        VORPcore.NotifyRightTip(_U('NotEnoghJars'),5000)
                    end
                else
                    VORPcore.NotifyRightTip(_U('NoInvetorySpace'),5000)
                end
            end)
        end
        
        if data.current.value == "AddWater" then
            CrouchAnim()
            Progressbar(Config.WaterTime*1000,_U('WaterHive'))
            TriggerServerEvent('mms-beekeeper:server:AddWater',CurrentBeehive[1].id)
            Menu.close()
        end

        if data.current.value == "AddClean" then
            CrouchAnim()
            Progressbar(Config.CleanTime*1000,_U('CleaningHive'))
            TriggerServerEvent('mms-beekeeper:server:AddClean',CurrentBeehive[1].id)
            Menu.close()
        end

        if data.current.value == "AddHealth" then
            CrouchAnim()
            Progressbar(Config.HealTime*1000,_U('HealingHive'))
            TriggerServerEvent('mms-beekeeper:server:AddHealth',CurrentBeehive[1].id)
            Menu.close()
        end

        if data.current.value == "AddQueen" then
            if Data.Queen > 0 then
                VORPcore.NotifyRightTip(_U('AlreadyHasAQueen'),5000)
            else
                CrouchAnim()
                Progressbar(Config.QueenTime*1000,_U('AddingQueen'))
                TriggerServerEvent('mms-beekeeper:server:AddQueen',CurrentBeehive[1].id)
                Menu.close()
            end
        end

        if data.current.value == "AddBees" then
            if Data.Queen < 1 then
                VORPcore.NotifyRightTip(_U('InsertQueenFirst'),5000)
            else
                if Data.Bees >= Config.MaxBeesPerHive then
                    VORPcore.NotifyRightTip(_U('MaxBeesReached'),5000)
                else
                    CrouchAnim()
                    Progressbar(Config.BeeTime*1000,_U('AddingBee'))
                    TriggerServerEvent('mms-beekeeper:server:AddBees',CurrentBeehive[1].id,Data.BeeSettings.QueenItem)
                    Menu.close()
                end
            end
        end
        
        if data.current.value == "HealSickness" then
            if Data.Sickness.Intensity > 0 then
                CrouchAnim()
                Progressbar(Config.SickTime*1000,_U('CuringSickness'))
                TriggerServerEvent('mms-beekeeper:server:HealSickness',CurrentBeehive[1].id)
                Menu.close()
            else
                VORPcore.NotifyRightTip(_U('BeesNotSick'),5000)
            end
        end

        if data.current.value == "SetHelper" then
            TriggerServerEvent('mms-beekeeper:server:AddHelper',CurrentBeehive[1].id)
            Menu.close()
        end

        if data.current.value == "RemoveHelper" then
            TriggerServerEvent('mms-beekeeper:server:RemoveHelper',CurrentBeehive[1].id)
            Menu.close()
        end

        if data.current.value == "ChangePosition" then
            TriggerEvent('mms-beekeeper:client:ChangeHeading',CurrentBeehive[1].id)
            Menu.close()
        end

        end,

        function(data,Menu)
            Menu.close()
        end)

end)

-----------------------------------------------
------------ Change Hive Heading --------------
-----------------------------------------------

RegisterNetEvent('mms-beekeeper:client:ChangeHeading')
AddEventHandler('mms-beekeeper:client:ChangeHeading',function(HiveID)
    local NewHeading = {
        type = "enableinput", -- don't touch
        inputType = "input", -- input type
        button = _U('ConfirmButton'), -- button name
        placeholder = "0", -- placeholder name
        style = "block", -- don't touch
        attributes = {
            inputHeader = _U('HeadingLabel'), -- header
            type = "number", -- inputype text, number,date,textarea ETC
            pattern = "[0-9]", --  only numbers "[0-9]" | for letters only "[A-Za-z]+" 
            title = "numbers only", -- if input doesnt match show this message
            style = "border-radius: 10px; background-color: ; border:none;"-- style 
        }
    }
    TriggerEvent("vorpinputs:advancedInput", json.encode(NewHeading),function(result)
        local Heading = tonumber(result)
        TriggerServerEvent('mms-beekeeper:server:ChangeHeading',HiveID,Heading)
    end)
end)

-----------------------------------------------
-------- Get Damage From Wild Hives -----------
-----------------------------------------------

Citizen.CreateThread(function ()
    Citizen.Wait(10000)
    while WildHivesSpawned and Config.GetDmgFromWildBees do
        Citizen.Wait(5000)
        for h,v in ipairs(Config.WildBeehives) do
            MyCoords = GetEntityCoords(PlayerPedId())
            local Distance = GetDistanceBetweenCoords(MyCoords.x, MyCoords.y, MyCoords.z, v.x, v.y, v.z, true)
            if Distance <= 10 then
                local IsSmoked = false
                if SmokedBeehives[1] ~= nil then
                    for h,v in ipairs(SmokedBeehives) do
                        local Distance = GetDistanceBetweenCoords(MyCoords.x, MyCoords.y, MyCoords.z, v.x, v.y, v.z, true)
                        if Distance < 10 then
                            IsSmoked = true
                        end
                    end
                end
                if not IsSmoked then
                    local Chance = math.random(1,100)
                    if Chance <= Config.ChanceToGetStung then
                        local MyPed = PlayerPedId()
                        ChangeEntityHealth(MyPed,Config.StungDamage)
                        VORPcore.NotifyRightTip(_U('YouGotStungbyBees'), 5000)
                    end
                end
            end
        end
    end
end)

-----------------------------------------------
----------- Create Wild Beehives --------------
-----------------------------------------------

RegisterNetEvent('mms-beekeeper:client:SpawnWildBeehives')
AddEventHandler('mms-beekeeper:client:SpawnWildBeehives',function()
    Citizen.Wait(5000)
    if WildHivesSpawned or not Config.WildBeehiveSpawn then
        return
    end

    ClearWildHives()

    local WildBeehivePromptGroup = BccUtils.Prompts:SetupPromptGroup()
    local SmokeBeehive = WildBeehivePromptGroup:RegisterPrompt(_U('SmokeBeehive'), 0x760A9C6F, 1, 1, true, 'click')--, {timedeventhash = 'SHORT_TIMED_EVENT'}) -- KEY G
    local TakeBees = WildBeehivePromptGroup:RegisterPrompt(_U('TakeBees'), 0x27D1C284, 1, 1, true, 'click')--, {timedeventhash = 'SHORT_TIMED_EVENT'}) -- KEY R
    local TakeQueen = WildBeehivePromptGroup:RegisterPrompt(_U('TakeQueen'), 0x5181713D, 1, 1, true, 'click')--, {timedeventhash = 'SHORT_TIMED_EVENT'}) -- KEY Spacebar
    local TakeHoney = WildBeehivePromptGroup:RegisterPrompt(_U('TakeHoneyWildHive'), 0x2CD5343E, 1, 1, true, 'click')--, {timedeventhash = 'SHORT_TIMED_EVENT'}) -- KEY Enter

    -- CreateBeehives 
    for h,v in ipairs(Config.WildBeehives) do
        local WildBeehive = SpawnHiveObject(Config.WildBeehiveModel, v.x, v.y, v.z, v.heading, v.rotx, v.roty, v.rotz)
        CreatedWildBeehives[#CreatedWildBeehives + 1] = WildBeehive
        StartBeeFX(v, true)
    end
    WildHivesSpawned = true
    -- Prompt for Wild Beehives
    while true do
        Citizen.Wait(5)
        for h,v in ipairs(Config.WildBeehives) do
            MyCoords = GetEntityCoords(PlayerPedId())
            local Distance = GetDistanceBetweenCoords(MyCoords.x, MyCoords.y, MyCoords.z, v.x, v.y, v.z, true)
            local CurrentHive = v
            if Distance <= 2 then
                WildBeehivePromptGroup:ShowGroup(_U('WildBeehivePromptGroup'))

                    if SmokeBeehive:HasCompleted() then
                        local IsSmoked = false
                        local TakenHoney = false
                        local TakenQueen = false
                        local TakenBees = false
                        if TakenQueenBeehives[1] ~= nil then
                            for h,v in ipairs(TakenQueenBeehives) do
                                local Distance = GetDistanceBetweenCoords(MyCoords.x, MyCoords.y, MyCoords.z, v.x, v.y, v.z, true)
                                if Distance < 2 then
                                    TakenQueen = true
                                end
                            end
                        end
                        if TakenBeeBeehives[1] ~= nil then
                            for h,v in ipairs(TakenBeeBeehives) do
                                local Distance = GetDistanceBetweenCoords(MyCoords.x, MyCoords.y, MyCoords.z, v.x, v.y, v.z, true)
                                if Distance < 2 then
                                    TakenBees = true
                                end
                            end
                        end
                        if TakenHoneyBeehives[1] ~= nil then
                            for h,v in ipairs(TakenHoneyBeehives) do
                                local Distance = GetDistanceBetweenCoords(MyCoords.x, MyCoords.y, MyCoords.z, v.x, v.y, v.z, true)
                                if Distance < 2 then
                                    TakenHoney = true
                                end
                            end
                        end
                        if SmokedBeehives[1] ~= nil then
                            for h,v in ipairs(SmokedBeehives) do
                                local Distance = GetDistanceBetweenCoords(MyCoords.x, MyCoords.y, MyCoords.z, v.x, v.y, v.z, true)
                                if Distance < 2 then
                                    IsSmoked = true
                                end
                            end
                        end

                        if not IsSmoked then
                            local MyPed = PlayerPedId()
                            local prop_name = "p_bugkiller01x"
                            local PlayAnimStatus = true
                             -- Create the prop
                            local SmokerItem = CreateObject(GetHashKey(prop_name), MyCoords.x, MyCoords.y, MyCoords.z, true, true, true)
                            SetEntityAsMissionEntity(SmokerItem, true, true)
                            AttachEntityToEntity(SmokerItem, MyPed, GetEntityBoneIndexByName(MyPed, "SKEL_R_FINGER00"), 
                            0.2, -0.2, -0.0, -40.0, 50.0, 30.0, true, true, false, true, 1, true)

                            -- Request and play animation
                            RequestAnimDict("script_rc@gun5@ig@stage_01@ig3_bellposes")
                            while not HasAnimDictLoaded("script_rc@gun5@ig@stage_01@ig3_bellposes") do
                                Citizen.Wait(100)
                            end

                            TaskPlayAnim(MyPed, "script_rc@gun5@ig@stage_01@ig3_bellposes", "pose_01_idle_famousgunslinger_05", 
                                        1.0, 8.0, -1, 1, 0, false, false, false)
                            Citizen.Wait(Config.SmokeHiveTime*1000)
                            ClearPedTasks(MyPed)
                                while PlayAnimStatus do
                                        Citizen.Wait(100)
                                        if not IsEntityPlayingAnim(MyPed, "script_rc@gun5@ig@stage_01@ig3_bellposes", "pose_01_idle_famousgunslinger_05", 3) then
                                        DeleteEntity(SmokerItem) -- Clean up the prop
                                        PlayAnimStatus = false
                                    end
                                end
                            TriggerServerEvent('mms-beekeeper:server:SmokeBeehive', CurrentHive,SmokedBeehives)
                        else
                            VORPcore.NotifyRightTip(_U('HiveAlreadySmoked'), 5000)
                        end
                    end

                    if TakeBees:HasCompleted() then
                        local IsSmoked = false
                        local TakenHoney = false
                        local TakenQueen = false
                        local TakenBees = false
                        if TakenQueenBeehives[1] ~= nil then
                            for h,v in ipairs(TakenQueenBeehives) do
                                local Distance = GetDistanceBetweenCoords(MyCoords.x, MyCoords.y, MyCoords.z, v.x, v.y, v.z, true)
                                if Distance < 2 then
                                    TakenQueen = true
                                end
                            end
                        end
                        if TakenBeeBeehives[1] ~= nil then
                            for h,v in ipairs(TakenBeeBeehives) do
                                local Distance = GetDistanceBetweenCoords(MyCoords.x, MyCoords.y, MyCoords.z, v.x, v.y, v.z, true)
                                if Distance < 2 then
                                    TakenBees = true
                                end
                            end
                        end
                        if TakenHoneyBeehives[1] ~= nil then
                            for h,v in ipairs(TakenHoneyBeehives) do
                                local Distance = GetDistanceBetweenCoords(MyCoords.x, MyCoords.y, MyCoords.z, v.x, v.y, v.z, true)
                                if Distance < 2 then
                                    TakenHoney = true
                                end
                            end
                        end
                        if SmokedBeehives[1] ~= nil then
                            for h,v in ipairs(SmokedBeehives) do
                                local Distance = GetDistanceBetweenCoords(MyCoords.x, MyCoords.y, MyCoords.z, v.x, v.y, v.z, true)
                                if Distance < 2 then
                                    IsSmoked = true
                                end
                            end
                        end
                        
                        if IsSmoked and not TakenBees then
                            local PlayAnimStatus = true
                                local prop_name = "mp005_s_posse_col_net01x"
                                local MyPed = PlayerPedId()
                                -- Create the prop
                                local BugNet = CreateObject(GetHashKey(prop_name), MyCoords.x, MyCoords.y, MyCoords.z, true, true, true)
                                SetEntityAsMissionEntity(BugNet, true, true)
                                AttachEntityToEntity(BugNet, MyPed, GetEntityBoneIndexByName(MyPed, "PH_L_Hand"),0.0, 0.0, -0.45, 0.0, 0.0, 0.0, true, true, false, true, 1, true)

                                -- Request and play animation
                                RequestAnimDict("mini_games@fishing@shore")
                                while not HasAnimDictLoaded("mini_games@fishing@shore") do
                                    Citizen.Wait(100)
                                end
                                TaskPlayAnim(MyPed, "mini_games@fishing@shore", "cast",1.0, 8.0, -1, 31, 0, false, false, false)
                                -- Wait the Catch Time
                                Citizen.Wait(Config.GetBeeTime*1000)
                                ClearPedTasks(MyPed)
                                -- Cleanup BugNet when animation stops
                                    while PlayAnimStatus do
                                        Citizen.Wait(100)
                                        if not IsEntityPlayingAnim(MyPed, "mini_games@fishing@shore", "cast", 3) then
                                            DeleteEntity(BugNet) -- Clean up the prop
                                            PlayAnimStatus = false
                                        end
                                    end
                                TriggerServerEvent('mms-beekeeper:server:TakeBeesFromWildHive', CurrentHive)
                            elseif IsSmoked and TakenBees then
                                VORPcore.NotifyRightTip(_U('NoMoreBeesInHive'), 5000)
                            elseif not IsSmoked then
                                VORPcore.NotifyRightTip(_U('BeehiveNotSmoked'), 5000)
                            end
                    end

                    if TakeQueen:HasCompleted() then
                        local IsSmoked = false
                        local TakenHoney = false
                        local TakenQueen = false
                        local TakenBees = false
                        if TakenQueenBeehives[1] ~= nil then
                            for h,v in ipairs(TakenQueenBeehives) do
                                local Distance = GetDistanceBetweenCoords(MyCoords.x, MyCoords.y, MyCoords.z, v.x, v.y, v.z, true)
                                if Distance < 2 then
                                    TakenQueen = true
                                end
                            end
                        end
                        if TakenBeeBeehives[1] ~= nil then
                            for h,v in ipairs(TakenBeeBeehives) do
                                local Distance = GetDistanceBetweenCoords(MyCoords.x, MyCoords.y, MyCoords.z, v.x, v.y, v.z, true)
                                if Distance < 2 then
                                    TakenBees = true
                                end
                            end
                        end
                        if TakenHoneyBeehives[1] ~= nil then
                            for h,v in ipairs(TakenHoneyBeehives) do
                                local Distance = GetDistanceBetweenCoords(MyCoords.x, MyCoords.y, MyCoords.z, v.x, v.y, v.z, true)
                                if Distance < 2 then
                                    TakenHoney = true
                                end
                            end
                        end
                        if SmokedBeehives[1] ~= nil then
                            for h,v in ipairs(SmokedBeehives) do
                                local Distance = GetDistanceBetweenCoords(MyCoords.x, MyCoords.y, MyCoords.z, v.x, v.y, v.z, true)
                                if Distance < 2 then
                                    IsSmoked = true
                                end
                            end
                        end

                        if IsSmoked and TakenBees and not TakenQueen then
                            local PlayAnimStatus = true
                            local prop_name = "mp005_s_posse_col_net01x"
                            local MyPed = PlayerPedId()
                            -- Create the prop
                            local BugNet = CreateObject(GetHashKey(prop_name), MyCoords.x, MyCoords.y, MyCoords.z, true, true, true)
                            SetEntityAsMissionEntity(BugNet, true, true)
                            AttachEntityToEntity(BugNet, MyPed, GetEntityBoneIndexByName(MyPed, "PH_L_Hand"),0.0, 0.0, -0.45, 0.0, 0.0, 0.0, true, true, false, true, 1, true)

                            -- Request and play animation
                            RequestAnimDict("mini_games@fishing@shore")
                            while not HasAnimDictLoaded("mini_games@fishing@shore") do
                                Citizen.Wait(100)
                            end
                            TaskPlayAnim(MyPed, "mini_games@fishing@shore", "cast",1.0, 8.0, -1, 31, 0, false, false, false)
                            -- Wait the Catch Time
                            Citizen.Wait(Config.GetQueenTime*1000)
                            ClearPedTasks(MyPed)
                            -- Cleanup BugNet when animation stops
                                while PlayAnimStatus do
                                    Citizen.Wait(100)
                                    if not IsEntityPlayingAnim(MyPed, "mini_games@fishing@shore", "cast", 3) then
                                        DeleteEntity(BugNet) -- Clean up the prop
                                        PlayAnimStatus = false
                                    end
                                end
                            TriggerServerEvent('mms-beekeeper:server:TakeQueenFromWildHive', CurrentHive)                
                        elseif IsSmoked and not TakenBees then
                            VORPcore.NotifyRightTip(_U('StillBeesInHive'), 5000)
                        elseif IsSmoked and TakenBees and TakenQueen then
                            VORPcore.NotifyRightTip(_U('QueenAlreadyTaken'), 5000)
                        elseif not IsSmoked then
                            VORPcore.NotifyRightTip(_U('BeehiveNotSmoked'), 5000)
                        end
                    end

                    if TakeHoney:HasCompleted() then
                        local IsSmoked = false
                        local TakenHoney = false
                        local TakenQueen = false
                        local TakenBees = false
                        if TakenQueenBeehives[1] ~= nil then
                            for h,v in ipairs(TakenQueenBeehives) do
                                local Distance = GetDistanceBetweenCoords(MyCoords.x, MyCoords.y, MyCoords.z, v.x, v.y, v.z, true)
                                if Distance < 2 then
                                    TakenQueen = true
                                end
                            end
                        end
                        if TakenBeeBeehives[1] ~= nil then
                            for h,v in ipairs(TakenBeeBeehives) do
                                local Distance = GetDistanceBetweenCoords(MyCoords.x, MyCoords.y, MyCoords.z, v.x, v.y, v.z, true)
                                if Distance < 2 then
                                    TakenBees = true
                                end
                            end
                        end
                        if TakenHoneyBeehives[1] ~= nil then
                            for h,v in ipairs(TakenHoneyBeehives) do
                                local Distance = GetDistanceBetweenCoords(MyCoords.x, MyCoords.y, MyCoords.z, v.x, v.y, v.z, true)
                                if Distance < 2 then
                                    TakenHoney = true
                                end
                            end
                        end
                        if SmokedBeehives[1] ~= nil then
                            for h,v in ipairs(SmokedBeehives) do
                                local Distance = GetDistanceBetweenCoords(MyCoords.x, MyCoords.y, MyCoords.z, v.x, v.y, v.z, true)
                                if Distance < 2 then
                                    IsSmoked = true
                                end
                            end
                        end

                        if not Config.OnlySmokeToTakeProduct and TakenBees and TakenQueen and not TakenHoney then
                            TriggerServerEvent('mms-beekeeper:server:TakeHoneyFromWildHive', CurrentHive)
                        elseif Config.OnlySmokeToTakeProduct and IsSmoked and not TakenHoney then
                            TriggerServerEvent('mms-beekeeper:server:TakeHoneyFromWildHive', CurrentHive)
                        elseif TakenBees and TakenQueen and TakenHoney then
                            VORPcore.NotifyRightTip(_U('NoMoreHoneyinHive'), 5000)
                        elseif Config.OnlySmokeToTakeProduct and not TakenHoney and not IsSmoked then
                            VORPcore.NotifyRightTip(_U('HiveNotSmoked'), 5000)
                        elseif Config.OnlySmokeToTakeProduct and TakenHoney then
                            VORPcore.NotifyRightTip(_U('NoMoreHoneyinHive'), 5000)
                        elseif not Config.OnlySmokeToTakeProduct and not TakenBees then
                            VORPcore.NotifyRightTip(_U('StillInsectsInHive'), 5000)
                        end
                    end
            end
        end
    end
end)

RegisterNetEvent('mms-beekeeper:client:BeehiveSmoked',function(CurrentHive)
    RemoveWildHiveFromList(SmokedBeehives, CurrentHive)
    table.insert(SmokedBeehives,CurrentHive)
    ResetWildHiveTimer(CurrentHive)
end)

RegisterNetEvent('mms-beekeeper:client:BeesTakenFromHive',function(CurrentHive)
    RemoveWildHiveFromList(TakenBeeBeehives, CurrentHive)
    table.insert(TakenBeeBeehives,CurrentHive)
    StopBeeFX(CurrentHive, true)
end)

RegisterNetEvent('mms-beekeeper:client:QueenTakenFromHive',function(CurrentHive)
    RemoveWildHiveFromList(TakenQueenBeehives, CurrentHive)
    table.insert(TakenQueenBeehives,CurrentHive)
end)

RegisterNetEvent('mms-beekeeper:client:HoneyTakenFromHive',function(CurrentHive)
    Progressbar(CurrentHive.TakeProductTime,_U('TakeHoneyProgressbar'))
    RemoveWildHiveFromList(TakenHoneyBeehives, CurrentHive)
    table.insert(TakenHoneyBeehives,CurrentHive)
    ResetWildHiveTimer(CurrentHive)
end)

RegisterNetEvent('mms-beekeeper:client:UpdateBeeFX',function(Coords, BeeAmount)
    local CurrentHive = { Coords = Coords }
    if BeeAmount > 0 then
        StartBeeFX(CurrentHive, false)
    else
        StopBeeFX(CurrentHive, false)
    end
end)

-----------------------------------------------
------------ Reset Wild Beehives --------------
-----------------------------------------------

Citizen.CreateThread(function ()
    if Config.ResetWildHives then
        while true do
            Citizen.Wait(10000)
            for _, WildHive in ipairs(Config.WildBeehives) do
                local HiveKey = GetWildHiveKey(WildHive)
                local Counter = WildHiveTimers[HiveKey]
                if Counter ~= nil then
                    Counter = Counter - 10000
                    if Counter <= 0 then
                        ClearWildHiveState(WildHive)
                        if Config.Debug then print('WildHiveCleared: ' .. HiveKey) end
                    else
                        WildHiveTimers[HiveKey] = Counter
                    end
                end
            end
        end
    end
end)

----------------- Utilities -----------------


------ Progressbar

function Progressbar(Time,Text)
    progressbar.start(Text, Time, function ()
    end, 'linear')
    Wait(Time)
    ClearPedTasks(PlayerPedId())
end

------ Animation

function CrouchAnim()
    local dict = "script_rc@cldn@ig@rsc2_ig1_questionshopkeeper"
    RequestAnimDict(dict)
    while not HasAnimDictLoaded(dict) do
        Wait(10)
    end
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    TaskPlayAnim(ped, dict, "inspectfloor_MyPed", 0.5, 8.0, -1, 1, 0, false, false, false)
end

---- CleanUp on Resource Restart 

AddEventHandler('onResourceStop',function(resource)
    if resource == GetCurrentResourceName() then
        for _, beehive in ipairs(CreatedBeehives) do
            DeleteObject(beehive)
        end
        for _, blips in ipairs(CreatedBlips) do
            blips:Remove()
        end
        ClearWildHives()
        StopPlacedHiveFX()
    end
end)
