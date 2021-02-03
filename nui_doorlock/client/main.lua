ESX = nil
local closestDoor, closestV, closestDistance, playerPed, playerCoords, doorCount, retrievedData
local playerNotActive = true

Citizen.CreateThread(function()
	while ESX == nil do
		TriggerEvent('esx:getSharedObject', function(obj) ESX = obj end)
		Citizen.Wait(0)
	end

	while ESX.GetPlayerData().job == nil do
		Citizen.Wait(10)
	end
	ESX.PlayerData = ESX.GetPlayerData()
	-- Sync doors with the server
	ESX.TriggerServerCallback('esx_doorlock:getDoorInfo', function(doorInfo)
		for doorID, locked in pairs(doorInfo) do
			Config.DoorList[doorID].locked = locked
		end
		retrievedData = true
	end)
	while not retrievedData do Citizen.Wait(0) end
	updateDoors(true)
	while IsPedStill(PlayerPedId()) do Citizen.Wait(0) end
	updateDoors()
	playerNotActive = nil
	retrievedData = nil
end)

-- Sync a door with the server
RegisterNetEvent('esx_doorlock:setState')
AddEventHandler('esx_doorlock:setState', function(doorID, locked)
	Config.DoorList[doorID].locked = locked
	CreateThread(function()
		while true do
			Citizen.Wait(0)

			if Config.DoorList[doorID].doors then
				for k, v in pairs(Config.DoorList[doorID].doors) do
					if not DoesEntityExist(v.object) then return end -- If the entity does not exist, end the loop
					v.currentHeading = GetEntityHeading(v.object)
					v.doorState = DoorSystemGetDoorState(v.doorHash)
					if Config.DoorList[doorID].locked and (v.doorState == 4 or Config.DoorList[doorID].slides) then
						if Config.DoorList[doorID].oldMethod then FreezeEntityPosition(v.object, true) end
						DoorSystemSetDoorState(v.doorHash, 1, false, false) -- Set to locked
						if Config.DoorList[doorID].doors[1].doorState == Config.DoorList[doorID].doors[2].doorState then return end -- End the loop
					elseif not Config.DoorList[doorID].locked then
						if Config.DoorList[doorID].oldMethod then FreezeEntityPosition(v.object, false) end
						DoorSystemSetDoorState(v.doorHash, 0, false, false) -- Set to unlocked
						if Config.DoorList[doorID].doors[1].doorState == Config.DoorList[doorID].doors[2].doorState then return end -- End the loop
					elseif not Config.DoorList[doorID].slides then
						if round(v.currentHeading, 0) == round(v.objHeading, 0) then
							DoorSystemSetDoorState(v.doorHash, 4, false, false) -- Force to close
						end
					end
				end
			else
				if not DoesEntityExist(Config.DoorList[doorID].object) then return end -- If the entity does not exist, end the loop
				Config.DoorList[doorID].currentHeading = GetEntityHeading(Config.DoorList[doorID].object)
				Config.DoorList[doorID].doorState = DoorSystemGetDoorState(Config.DoorList[doorID].doorHash)
				if Config.DoorList[doorID].locked and (doorState == 4 or Config.DoorList[doorID].slides) then
					if Config.DoorList[doorID].oldMethod then FreezeEntityPosition(Config.DoorList[doorID].object, true) end
					DoorSystemSetDoorState(Config.DoorList[doorID].doorHash, 1, false, false) -- Set to locked
					return -- End the loop
				elseif not Config.DoorList[doorID].locked then
					if Config.DoorList[doorID].oldMethod then FreezeEntityPosition(Config.DoorList[doorID].object, false) end
					DoorSystemSetDoorState(Config.DoorList[doorID].doorHash, 0, false, false) -- Set to unlocked
					return -- End the loop
				elseif not Config.DoorList[doorID].slides then
					if round(Config.DoorList[doorID].currentHeading, 0) == round(Config.DoorList[doorID].objHeading, 0) then
						DoorSystemSetDoorState(Config.DoorList[doorID].doorHash, 4, false, false) -- Force to close
					end
				end
			end

		end
	end)
end)

RegisterNetEvent('esx:setJob')
AddEventHandler('esx:setJob', function(job)
	ESX.PlayerData.job = job
end)

local last_x, last_y, lasttext, isDrawing
function DrawTextNUI(coords, text)
	local paused = false
	if IsPauseMenuActive() then paused = true end
	local onScreen,_x,_y = GetScreenCoordFromWorldCoord(coords.x,coords.y,coords.z)
	if _x ~= last_x or _y ~= last_y or text ~= lasttext or paused then
		isDrawing = true
		if paused then SendNUIMessage ({action = "hide"}) else SendNUIMessage({action = "display", x = _x, y = _y, text = text}) end
		last_x, last_y, lasttext = _x, _y, text
		Citizen.Wait(0)
	end
end

function loadAnimDict(dict)
    while (not HasAnimDictLoaded(dict)) do
        RequestAnimDict(dict)
        Citizen.Wait(5)
    end
end

function dooranim(entity, state)
	Citizen.CreateThread(function()
    loadAnimDict("anim@heists@keycard@") 
    TaskPlayAnim(playerPed, "anim@heists@keycard@", "exit", 8.0, 1.0, -1, 16, 0, 0, 0, 0)
    Citizen.Wait(550)
	ClearPedTasks(playerPed)
	end)
end

function round(num, decimal)
	local mult = 10^(decimal)
	return math.floor(num * mult + 0.5) / mult
end

function debug(index, doorID)
	if GetDistanceBetweenCoords(playerCoords, doorID.textCoords) < 3 then
		if doorID.doors then door = '{'.. doorID.doors[1].object..' '.. doorID.doors[2].object.. '}' else door = doorID.object end
		return print(   ('id: %s locked: %s object: %s state: %s'):format(index, doorID.locked, door, doorID.doorState)   )
	end
end

function updateDoors(starting)
	playerCoords = GetEntityCoords(PlayerPedId())
	for _,doorID in ipairs(Config.DoorList) do
		if doorID.doors then
			for k,v in ipairs(doorID.doors) do
				if #(vector2(playerCoords.x, playerCoords.y) - vector2(v.objCoords.x, v.objCoords.y)) < 100 then
					v.object = GetClosestObjectOfType(v.objCoords, 1.0, v.objHash, false, false, false)
					if doorID.delete then
						SetEntityAsMissionEntity(v.object, 1, 1)
						DeleteObject(v.object)
						v.object = nil
					end
					if v.object then
						v.doorHash = 'doorlock_'.._..'-'..k
						AddDoorToSystem(v.doorHash, v.objHash, v.objCoords, false, false, false)
						if doorID.locked then DoorSystemSetDoorState(v.doorHash, 4, false, false) DoorSystemSetDoorState(v.doorHash, 1, false, false) else
							DoorSystemSetDoorState(v.doorHash, 0, false, false) if doorID.oldMethod then FreezeEntityPosition(v.object, false) end end
					end
				elseif v.object then RemoveDoorFromSystem(v.doorHash) end
			end
		elseif not doorID.doors then
			if #(vector2(playerCoords.x, playerCoords.y) - vector2(doorID.objCoords.x, doorID.objCoords.y)) < 100 then
				if doorID.slides then doorID.object = GetClosestObjectOfType(doorID.objCoords, 5.0, doorID.objHash, false, false, false) else
					doorID.object = GetClosestObjectOfType(doorID.objCoords, 1.0, doorID.objHash, false, false, false)
				end
				if doorID.delete then
					SetEntityAsMissionEntity(doorID.object, 1, 1)
					DeleteObject(doorID.object)
					doorID.object = nil
				end
				if doorID.object then
					doorID.doorHash = 'doorlock_'.._
					AddDoorToSystem(doorID.doorHash, doorID.objHash, doorID.objCoords, false, false, false) 
					if doorID.locked then DoorSystemSetDoorState(doorID.doorHash, 4, false, false) DoorSystemSetDoorState(doorID.doorHash, 1, false, false) else
						DoorSystemSetDoorState(doorID.doorHash, 0, false, false) if doorID.oldMethod then FreezeEntityPosition(doorID.object, false) end end
				end
			elseif doorID.object then RemoveDoorFromSystem(doorID.doorHash) end
		end
		-- set text coords
		if not doorID.setText and doorID.doors then
			for k,v in ipairs(doorID.doors) do
				if k == 1 and DoesEntityExist(v.object) then
					doorID.textCoords = v.objCoords
				elseif k == 2 and DoesEntityExist(v.object) and doorID.textCoords then
					local textDistance = doorID.textCoords - v.objCoords
					doorID.textCoords = (doorID.textCoords - (textDistance / 2))
					doorID.setText = true
				end
				if k == 2 and doorID.textCoords and doorID.slides then
					DoorSystemSetAutomaticDistance(v.doorHash, (doorID.maxDistance * 3), false, false)
					if GetEntityHeightAboveGround(v.object) < 1 then
						doorID.textCoords = vector3(doorID.textCoords.x, doorID.textCoords.y, doorID.textCoords.z+1.2)
					end
				end
			end
		elseif not doorID.setText and not doorID.doors and DoesEntityExist(doorID.object) then
			if not doorID.garage then
				local minDimension, maxDimension = GetModelDimensions(doorID.objHash)
				if doorID.fixText then dimensions = minDimension - maxDimension else dimensions = maxDimension - minDimension end
				local dx, dy = tonumber(string.sub(dimensions.x, 1, 6)), tonumber(string.sub(dimensions.y, 1, 6))
				local h = tonumber(string.sub(doorID.objHeading, 1, 1))
				if h == 9 or h == 8 or h == 2 then dx, dy = dy, dx end
				local maths = vector3(dx/2, dy/2, 0)
				doorID.textCoords = GetEntityCoords(doorID.object) - maths
				doorID.setText = true
			else
				doorID.textCoords = GetEntityCoords(doorID.object)
				doorID.setText = true
			end
			if doorID.slides then
				DoorSystemSetAutomaticDistance(doorID.doorHash, (doorID.maxDistance * 2), false, false)
				if GetEntityHeightAboveGround(doorID.object) < 1 then
					doorID.textCoords = vector3(doorID.textCoords.x, doorID.textCoords.y, doorID.textCoords.z+1.6)
				end
			end
		end
	end
	if not starting then
		doorCount = DoorSystemGetSize()
		if doorCount ~= 0 then print(('%s doors are loaded'):format(doorCount)) end
	end
end

Citizen.CreateThread(function()
	while playerNotActive do Citizen.Wait(100) end
	lastCoords = playerCoords
	while playerCoords do
		local distance = #(playerCoords - lastCoords)
		if distance > 30 then
			updateDoors()
			lastCoords = playerCoords
		end
		Citizen.Wait(500)
	end
end)

local doorSleep = 500
Citizen.CreateThread(function()
	while not playerCoords do Citizen.Wait(0) end
	while true do
		Citizen.Wait(0)
		if doorCount then
			local distance
			for k,v in ipairs(Config.DoorList) do
				if v.setText and (v.object or (v.doors and v.doors[1].object)) then
					distance = #(v.textCoords - playerCoords)
					if v.setText and distance < v.maxDistance then
						closestDoor, closestV, closestDistance = k, v, distance
					end
				end
			end
			Citizen.Wait(doorSleep)
		else Citizen.Wait(1000) end
	end
end)



Citizen.CreateThread(function()
	while true do
		Citizen.Wait(0)
		playerPed = PlayerPedId()
		playerCoords = GetEntityCoords(playerPed)
		if doorCount ~= nil and doorCount ~= 0 and closestDistance then
			doorSleep = 100
			closestDistance = #(closestV.textCoords - playerCoords)
			if closestDistance < closestV.maxDistance and closestV.setText then
				doorSleep = 5
				if not closestV.doors then
					local doorState = DoorSystemGetDoorState(closestV.doorHash)
					local heading = GetEntityHeading(closestV.object)
					if closestV.locked and round(heading, 0) ~= round(closestV.objHeading, 0) then
						DrawTextNUI(closestV.textCoords, 'Locking')
					elseif not closestV.locked then
						if Config.ShowUnlockedText then DrawTextNUI(closestV.textCoords, 'Unlocked') else if isDrawing then SendNUIMessage ({action = "hide"}) isDrawing = false end end
					else
						DrawTextNUI(closestV.textCoords, 'Locked')
					end
				else
					local door = {}
					for k2,v2 in ipairs(closestV.doors) do
						local doorState = DoorSystemGetDoorState(v2.doorHash)
						if doorState == 1 and closestV.locked then door[k2] = true else door[k2] = false end
					end
					if door[1] and door[1] == door[2] then DrawTextNUI(closestV.textCoords, 'Locked')
					elseif not closestV.locked then if Config.ShowUnlockedText then DrawTextNUI(closestV.textCoords, 'Unlocked') else if isDrawing then SendNUIMessage ({action = "hide"}) isDrawing = false end end
					else DrawTextNUI(closestV.textCoords, 'Locking') end
				end
			else
				if closestDistance > closestV.maxDistance and isDrawing then
					SendNUIMessage ({action = "hide"}) isDrawing = false
				end
				closestDoor, closestV, closestDistance = nil, nil, nil
			end
		else Citizen.Wait(100) end
	end
end)

function IsAuthorized(doorID)
	if ESX.PlayerData.job == nil then
		return false
	end

	for _,job in pairs(doorID.authorizedJobs) do
		if job == ESX.PlayerData.job.name then
			return true
		end
	end

	return false
end

RegisterCommand('doorlock', function()
	if closestDoor and IsAuthorized(closestV) then
		if not IsPedInAnyVehicle(playerPed) then dooranim(closestV.object, closestV.locked) end
		closestV.locked = not closestV.locked
		TriggerServerEvent('esx_doorlock:updateState', closestDoor, closestV.locked) -- Broadcast new state of the door to everyone
		if not closestV.audioLock then
			if closestV.slides then
				closestV.audioLock = {['file'] = 'button-remote.ogg', ['volume'] = 0.06}
				closestV.audioUnlock = {['file'] = 'button-remote.ogg', ['volume'] = 0.06}
			else
				closestV.audioLock = {['file'] = 'door-bolt-4.ogg', ['volume'] = 0.08}
				closestV.audioUnlock = {['file'] = 'door-bolt-4.ogg', ['volume'] = 0.08}
			end
		end
		if closestV.locked then SendNUIMessage ({action = 'audio', audio = closestV.audioLock}) else SendNUIMessage ({action = 'audio', audio = closestV.audioUnlock}) end
	end
end)
RegisterKeyMapping('doorlock', 'Interact with a door lock', 'keyboard', 'e')
