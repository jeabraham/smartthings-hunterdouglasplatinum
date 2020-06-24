-- Hunter Douglas Platinum bridge driver version 1.8 by Gengen
-- This software is distributed under the terms of the GNU General Public License 2.0
-- http://www.gnu.org/licenses/old-licenses/gpl-2.0.en.html

local PlatinumShade_PollStarted = false
local PlatinumShade_Connected = 0
local PlatinumShade_ConnectTime = nil
local socket = require("socket")
local http = require("socket.http")
local bit = require "bit"
local PlatinumShade_pollInterval = 180 -- 3 minutes
local PlatinumShade_Db = { rooms={}, shades={}, scenes={}, schedules={} }
local PlatinumShade_NeedSync = false
local PlatinumShade_Queue = {}
local PlatinumShade_WaitingFor = nil
local PlatinumShade_WaitingForTime = 0
local PlatinumShade_ActLevel = 0
local PlatinumShade_ActTime = 0

local kUPD01 = 1
local KShadeActionPending = 2

local ANSI_RED     = "\027[31m"
local ANSI_GREEN   = "\027[32m"
local ANSI_YELLOW  = "\027[33m"
local ANSI_BLUE    = "\027[34m"
local ANSI_MAGENTA = "\027[35m"
local ANSI_CYAN    = "\027[36m"
local ANSI_WHITE   = "\027[37m"
local ANSI_RESET   = "\027[0m"

-- All logging goes through this function.
-- Comment/uncomment the luup.log line to enable/disable verbose logging
function log(msg) 
  -- luup.log("Platinum Bridge: " .. msg)
end

-- A debugging function to output a complete LUA object heirarchically
function printTable(tab,prefix,hash)
	local k,v,s,i, top, pref
	if prefix == nil then
		prefix = ""
	end
	if hash == nil then
	    top = true
		hash = {}
	else
	    top = false
	end
	if hash[tab] ~= nil then
		log(prefix .. "recursive " .. hash[tab])
		return
	end
	if type(tab) ~= "table" then
		if type(tab) == "string" then
			tab = tab:gsub("\t", "\\t")
			tab = tab:gsub("\r", "\\r")
			tab = tab:gsub("\n", "\\n")
		end
	  	log(prefix .. " (" .. type(tab) .. ") = " .. tostring(tab))
	  	return
	end
	hash[tab] = prefix
	if top then
		log(prefix .. "{")
		pref = prefix
		prefix = prefix .. "  "
	end
	for k,v in pairs(tab) do
	  if type(k) == "table" then
	         log(prefix .. "key-{")
	         printTable(k,prefix .. "       ", hash);
			 s = "    }: "
	  else
	         s = tostring(k) .. ": "
	  end
	  if type(v) == "table" then
			 log(prefix .. s .. "{")
	         printTable(v,prefix .. string.rep(" ",#s) .. "  ", hash)
			 log(prefix .. string.rep(" ",#s) .. "}")
	  else
	         hash[v] = prefix;
			 if type(v) == "string" then
	        	v = v:gsub("\t", "\\t")
	        	v = v:gsub("\r", "\\r")
	        	v = v:gsub("\n", "\\n")
			 end
	         log(prefix .. s .. "(" .. type(v) .. ") " .. tostring(v))
	  end
	end
	if top then
		log(pref .. "}")
	end
end

-- A debugging function to convert any LUA objet to a string
function tableToString(tab)
   if type(tab) ~= "table" then
      return tostring(tab)
   end
   local k,v,s
   s = "{"
   for k,v in pairs(tab) do
      if s ~= "{" then
	     s = s .. ", "
	  end
      if type(k) == "table" then
	     s = s .. tableToString(k)
	  else
	     s = s .. tostring(k)
	  end
	  s = s .. "="
      if type(v) == "table" then
	     s = s .. tableToString(v)
	  else
	     s = s .. tostring(v)
	  end
   end
   s = s .. "}"
   return s
end

-- Here is where we automatically discover the bridge's IP address.
function FindPlatinumBridgeIPAddress(prevIp)
	PlatinumShade_Connected = 0
	local udp = socket.udp()
	udp:setoption("broadcast",true)
	udp:settimeout(1.0)
	local broadcast_ip = '255.255.255.255'
	local NBNS_port = 137 -- Netbios Name Service

	-- Netbios Name service query "PLATLINK-FDBU<00>"
	local NbnsQuery = "\000\001\001\016\000\001\000\000\000\000\000\000 FAEMEBFEEMEJEOELCNFAEEECFFCACAAA\000\000 \000\001"
	udp:sendto(NbnsQuery, broadcast_ip, NBNS_port)
	local response, bridgeIp, peerPort = udp:receivefrom()
	udp:close()
	if response then
		if prevIp == bridgeIp then
			log("NBNS query consistent response: bridgeIp=" .. tostring(bridgeIp))
			StartProtocol(bridgeIp)
		else
			-- At boot, the bridge sometimes returns bogus IP addresses like 192.168.xx.90 where
			-- xx increments every 500ms until it gets the real IP address from the DHCP server
			-- So we wait until we get a consistent answer twice in a row in 1 second intervals.
			log ("NBNS query first response: bridgeIp=" .. tostring(bridgeIp))
			prevIp = peerIp
			luup.call_delay("FindPlatinumBridgeIPAddress", 1, bridgeIp, true) 
		end
	else
		log("Cannot find Platinum Bridge: " .. bridgeIp)
		luup.call_delay("FindPlatinumBridgeIPAddress", 1, "", true) 
	end
end

-- Once we have found the bridge's IP address, we open TCP port 522 to start the session.
-- This also sets up the keep-alive timer
function StartProtocol(bridgeIp)
	local platinum_port = 522
	luup.io.open(PlatinumShade_Device, bridgeIp, platinum_port)
	log("Opening TCP socket at IP address: " .. bridgeIp .. ":" .. platinum_port)
	PlatinumShade_ConnectTime = os.time()
	PlatinumShade_Connected = 1
	if not PlatinumShade_PollStarted then
		PlatinumShade_PollStarted = true
		luup.call_delay("PlatinumPoll", PlatinumShade_pollInterval, "", true)
	end
end

-- This is the first function to be called when the LuaUPnP engine first starts (or restarts)
function PlatinumShade_Startup(lul_device)
	log("Startup(lul_device="..lul_device..")")
	PlatinumShade_Device = lul_device;
	FindPlatinumBridgeIPAddress("")
	InitializePlatinumDb()
  	return true,'ok','Platinum Shade'
end

-- Initialize the internal database with whatever Vera knows about the shades
-- We correllate this with the shade database that we receive from the bridge
-- before we do the sync to add new shades or delete old ones.
function InitializePlatinumDb()
	for k, v in pairs(luup.devices) do
		if v.device_num_parent == PlatinumShade_Device then
			local id_str = v.id
			local id_prefix = id_str:sub(1,1)
		    local id_num = tonumber(id_str:sub(2))
			if id_prefix == "S" then
				PlatinumShade_Db.shades[id_num+1] = {shade = id_num, device=k, description=v.description}
			elseif id_prefix == "R" then
				PlatinumShade_Db.rooms[id_num+1] = {room = id_num, device=k, description=v.description} 
			else
				log(ANSI_RED.."Error: Unkown ID: ".. tostring(v.id)..ANSI_RESET)
			end 
		end 
	end
	log("InitializePlatinumDb complete.")
	printTable(PlatinumShade_Db)
end

-- This sends a periodic keep-alive message to the bridge
-- to maintain the connection
function PlatinumPoll()
	log("Polling")
	if PlatinumShade_Connected >= 4 then
		Enqueue("$dmy", "^%d %$ack")
	end
	luup.call_delay("PlatinumPoll", PlatinumShade_pollInterval, "", true)
end

function Dequeue()
	local time = os.time();
	local actSeconds = time - PlatinumShade_ActTime 
	log("Dequque: Queue depth="..#PlatinumShade_Queue.." WaitingFor="..tostring(PlatinumShade_WaitingFor).." ActLevel="..tostring(PlatinumShade_ActLevel).." ActSeconds="..actSeconds.." Queue="..tableToString(PlatinumShade_Queue)) 
	if PlatinumShade_ActLevel > 0 and actSeconds > 5 then -- Timeout
		log(ANSI_CYAN.."WARNING:"..ANSI_RESET.." act timeout - bypassing actLevel "..tostring(PlatinumShade_ActLevel))
		PlatinumShade_ActLevel = 0
	end
	if PlatinumShade_WaitingFor ~= nil then
		local waitSeconds = time - PlatinumShade_WaitingForTime
		if waitSeconds > 20 then
			log(ANSI_CYAN.."WARNING:"..ANSI_RESET.." waitingFor timeout - bypassing waitingFor"..tostring(PlatinumShade_WaitingFor))
			PlatinumShade_WaitingFor = nil
		end
	end
	while #PlatinumShade_Queue > 0 and PlatinumShade_WaitingFor == nil and PlatinumShade_ActLevel == 0 do
		local t = table.remove(PlatinumShade_Queue,1)
		PlatinumShade_WaitingFor = t.wait
		PlatinumShade_WaitingForTime = time
		if not Outgoing(t.data) then
			return false
		end 
	end
	return true
end

-- Enqueue data to send but don't send any more data until we get a specific response
-- wait can either be nil to not wait, a Lua pattern to wait for that specific pattern
-- to be received, or it can be numeric constant meaning that special processing is needed.
function Enqueue(data, wait)
	log("Enqueue data=\""..tostring(data).."\" Wait="..tostring(wait).." queue depth="..#PlatinumShade_Queue.." WaitingFor="..tostring(PlatinumShade_WaitingFor).." ActLevel="..tostring(PlatinumShade_ActLevel)) 
	table.insert(PlatinumShade_Queue, {data=data, wait=wait})
	Dequeue()
end

-- Low level output function sends commands to the bridge
-- If an error occurs, assume that we lost the connection
function Outgoing(data)
	log("Outgoing: " .. data)
	local result = luup.io.write(data, PlatinumShade_Device)
	if not result then
		log("luup.io.write("..tostring(data)..", "..tostring(PlatinumShade_Device) .. ") returned " .. tostring(result))
		FindPlatinumBridgeIPAddress("")
		return false
	end
	return true
end

-- This is a list of shade types indexed by shade type + 1
-- name - The shade type name
-- order - an array of feature numbers supported by this shade type in the order in which they should be used
-- xover (optional - if shade has more than 1 feature) - The crossover point as a percentage value. Below this value, the second feature is used.
-- tdbu (optional) - Indicates special handling for top-down/bottom-up shade types
-- feature - an object matching the feature numbers to names
-- The last index (all) includes features common to all shades.
platinum_shade_types = {
	[ 0+1]={name="Alustra Woven Textures: Roller",                                   order={4},        						feature={[4]="Bottom-Up"}},
	[ 1+1]={name="Duette & Applause Honeycomb Shades: Standard",                     order={4},        						feature={[4]="Bottom-Up"}},  
	[ 2+1]={name="Duette & Applause Honeycomb Shades: DuoLite & Top-Down/Bottom-Up", order={4, 18},    xover=50, tdbu=true,	feature={[4]="Bottom Rail", [18]="Middle Rail"}},  
	[ 3+1]={name="Duette & Applause Honeycomb Shades: Top-Down",                     order={4},        						feature={[4]="Top-Down"}},  
	[ 4+1]={name="Duette & Applause Honeycomb Shades: Skylift",                      order={4},        						feature={[4]="Bottom-Up"}},  
	[ 5+1]={name="Desgner Roller & Screen Shades",                                   order={4},        						feature={[4]="Bottom-Up"}},  
	[ 6+1]={name="Luminette Privacy Sheers", 										 order={4, 19, 7}, xover=20,			feature={[4]="Traverse",    [19]="Close left",    [7]="Close right"}},
	[ 7+1]={name="Luminette Modern Draperies: Full Panel",                     	     order={4},        						feature={[4]="Traverse"}},  
	[ 8+1]={name="Luminette Modern Draperies: Dual Panel", 						     order={4, 19, 7}, xover=20,			feature={[4]="Traverse",    [19]="Close left",    [7]="Close right"}},
	[ 9+1]={name="Pirouette Window Shadings",               				         order={4},        						feature={[4]="Bottom-Up"}},  
    [10+1]={name="Silhouette & Nanticket Window Shadings",                           order={4, 7},     xover=20,			feature={[4]="Bottom-Up",   [ 7]="Vane"}},  
    [11+1]={name="Vignette Modern Roman Shades: Traditional",                        order={4},        						feature={[4]="Bottom-Up"}},  
    [12+1]={name="Vignette Modern Roman Shades: Tiered",                             order={4},        						feature={[4]="Bottom-Up"}},  
    [13+1]={name="Vignette Modern Roman Shades: Tiered Top-Down/Bottom-Up",          order={4, 18},    xover=50, tdbu=true,	feature={[4]="Bottom Rail", [18]="Middle Rail"}},  
    [14+1]={name="Skyline Gliding Window Panels",                              	     order={4},        						feature={[4]="Traverse"}},  
    [15+1]={name="Pleated Shades",               	            			         order={4},        						feature={[4]="Bottom-Up"}},  
    [16+1]={name="Alustra Woven Textures: Roman",                                    order={4},        						feature={[4]="Bottom-Up"}},
    [17+1]={name="Solera Soft Shades",                                               order={4},        						feature={[4]="Bottom-Up"}},
    [18+1]={name="Design Studio Roman Shades",                                       order={4},        						feature={[4]="Bottom-Up"}},
    all   ={name="Features common to all shades",                                    order={10,01,12}, 						feature={[10]="Intermediate stop", [01]="Sync", [12]="Test"}},
}  

local weekdays = {"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }

-- This is called whenever a shade is changed either by vera or by the platinum app on the mobile device
function UpdateShade(shade_id, feature, position)
	local shade = PlatinumShade_Db.shades[shade_id+1]
	shade.deleted = nil
	if feature == 1 then -- Sync
		log("UpdateShade: ignoring sync to shade " .. shade_id .. ": " .. tostring(shade.description)) 
		return
	elseif feature == 12 then -- test
		log("UpdateShade: ignoring test to shade " .. shade_id .. ": " .. tostring(shade.description)) 
		return
	elseif feature == 10 then -- Intermediate stop. We don't know exactly where that is so assume 50%
		log("UpdateShade: Assuming intermediat stop at 50% for shade " .. shade_id .. ": " .. tostring(shade.description)) 
		shade.feature = 4
		shade.position = 128
	else
		shade.feature = feature
		shade.position = position
	end
	if shade.device then
		local room = PlatinumShade_Db.rooms[shade.room+1]
		local shade_type = platinum_shade_types[room.type+1]
		local percent
		local status = 0
		if shade_type.tdbu then
			-- special case for top-down/bottom-up shades
			if shade.feature == shade_type.order[1] then
				percent = shade_type.xover + math.floor((shade.position * (100-shade_type.xover) / 255) + .5)
			else
				percent = shade_type.xover - math.floor((shade.position * shade_type.xover / 255) + .5)
			end
			if percent ~= shade_type.xover then
				status = 1
			end
		else
			if #shade_type.order > 2 then
				if shade.feature == shade_type.order[3] then -- 0-9%
					percent =                        math.floor((shade.position * ((shade_type.xover / 2)-1) / 255) + .5)
				elseif shade.feature == shade_type.order[1] then -- 10%, 20-100%
					percent = shade_type.xover     + math.floor((shade.position * (100-shade_type.xover)     / 255) + .5)
				else -- 10-19%
					percent = (shade_type.xover/2) + math.floor((shade.position * ((shade_type.xover / 2)-1) / 255) + .5)
				end
			elseif #shade_type.order > 1 then
				if shade.feature == shade_type.order[1] then
					percent = shade_type.xover + math.floor((shade.position * (100-shade_type.xover) / 255) + .5)
				else
					percent = math.floor((shade.position * shade_type.xover / 255) + .5)
				end
			else
				percent = math.floor((shade.position * 100 / 255) + .5)
			end
			if percent > 0 then
				status = 1
			end
		end
		luup.variable_set("urn:upnp-org:serviceId:Dimming1",        "LoadLevelStatus", tostring(percent), shade.device, false)
		luup.variable_set("urn:upnp-org:serviceId:WindowCovering1", "LoadLevelStatus", tostring(percent), shade.device, false)
		luup.variable_set("urn:upnp-org:serviceId:SwitchPower1",    "Status",          tostring(status),  shade.device, false)
	end
end

-- Loose string matching used for room names
-- Case and whitespace are ignored in the comparison. n2 can be a prefix of n1
function NameMatch(n1, n2)
	return string.find(string.lower(string.gsub(n1,"%s","")), string.lower(string.gsub(n2,"%s","")), 1, true) == 1
end

function TableLength(T)
  	local count = 0
  	for x in pairs(T) do
  		count = count + 1
	end
  	return count
end

function URLEnclode(s)
	return string.gsub(s, "%A", function(c) return string.format("%%%02X", string.byte(c)) end)
end

-- This is where we synchronize the device database which we received from the bridge with Vera's.
-- Vera will add or delete child devices to match what the bridge gives us.
-- This is not to be confused with a manual shade "sync" operation used when adding new shades.
function SyncDevices()
	local children = luup.chdev.start(PlatinumShade_Device)
	for id, shade in pairs(PlatinumShade_Db.shades) do
		if shade.deleted then
			log( "SyncDevices: Not appending shade " .. id-1 .. ": " .. shade.description .. ".")
			PlatinumShade_Db.rooms[shade.room+1].shades[id] = nil
		  	PlatinumShade_Db.shades[id] = nil
		else	
			log( "SyncDevices: Appending shade " .. id-1 .. ": " .. shade.description .. ".")
			luup.chdev.append(PlatinumShade_Device, children, "S"..id-1, shade.description, "urn:schemas-micasaverde-com:device:WindowCovering:1", "D_WindowCovering1.xml", "", "", false)
		end
	end
	for id, room in pairs(PlatinumShade_Db.rooms) do
		if room.deleted then
			log("SyncDevices: Not appending room " .. id-1 .. ": " .. room.description .. " shades.")
		  	PlatinumShade_Db.rooms[id] = nil
		elseif TableLength(room.shades) > 1 then
			-- Create a device to change all shades in a room if the room has more than one shade
			log("SyncDevices: Appending room " .. id-1 .. ": " .. room.description .. " shades.")
			luup.chdev.append(PlatinumShade_Device, children, "R"..id-1, room.description .. " shades", "urn:schemas-micasaverde-com:device:WindowCovering:1", "D_WindowCovering1.xml", "", "", false)
		end
	end
	for id, scene in pairs(PlatinumShade_Db.scenes) do
		if scene.deleted then
			log( "SyncDevices: Deleting scene " .. id-1 ..".")
		  	PlatinumShade_Db.scenes[id] = nil
		end
	end
	for id, schedule in pairs(PlatinumShade_Db.schedules) do
		if schedule.deleted then
			log( "SyncDevices: Deleting schedule " .. id-1 ..".")
		  	PlatinumShade_Db.schedules[id] = nil
		end
	end
	luup.chdev.sync(PlatinumShade_Device, children)
	-- Now go through all child devices and set the rooms if there is a name match
	for k, v in pairs(luup.devices) do
		if v.device_num_parent == PlatinumShade_Device then
			local id_prefix = v.id:sub(1,1)
		    local id_num = tonumber(v.id:sub(2))
			local room
			if id_prefix == "S" then
				local shade = PlatinumShade_Db.shades[id_num+1]
				if not shade then
					break
				end
				room = PlatinumShade_Db.rooms[shade.room+1]
			else
				room = PlatinumShade_Db.rooms[id_num+1]
			end
			if not room then
				break
			end
			for i = 1, #luup.rooms do
				if NameMatch(room.description, luup.rooms[i]) then
					log("Vera Device " .. k .. ": " .. URLEnclode(v.description) .. " - Bridge room " ..  room.description .. " matches Vera room " .. luup.rooms[i])
					if v.room_num ~= i then
						log("Device=" .. k .. " old room_num=".. v.room_num .. " New room_num=" .. i); 
						-- For some reason, the call to luup.attr below to change the room does not always work, so we use a roundabout approach.
						--luup.attr_set("room_num", tostring(i), k)
						local response, status, headers, statusline = http.request("http://127.0.0.1:3480/data_request?id=device&action=rename&device="..tostring(k).."&name="..URLEnclode(v.description).."&room="..tostring(i))
						log("response="..tostring(response).." status="..tostring(status).." headers="..tableToString(headers).." statusline="..tostring(statusline))
					end
					break
				end
			end			
		end 
	end 
	log("SyncDevices complete")
end

-- This is where we parse any incomming status messages from the bridge
function PlatinumShade_Incoming(data)
	local handled = false
	log("Incoming: " .. string.format("%q",data))
	-- Remove any leading 0 bytes
	while string.byte(data,1) == 0 do
		data = string.sub(data,2)
	end
    -- $act01-00-    	Start action
    -- $act02-<room>-	Action in room
	-- $act00-00-    	End action
	-- $act messages may come due to our own actions or someone elses. We must wait until the action is completed either way.
	-- However, if we don't get the $act00-00- within a given timeout, we will reset the state and allow more commands to go through.
	local act_level_str, act_arg_str = string.match(data, "^%d %$act(%d%d)-(%d%d)-.*$")
	if act_level_str ~= nil then
		PlatinumShade_ActLevel = tonumber(act_level_str)
		PlatinumShade_ActTime = os.time()
		handled = true
	end
	-- see if the data matches a response that we were waiting for previously
	if type(PlatinumShade_WaitingFor) == "string" and string.match(data, PlatinumShade_WaitingFor) then
	   PlatinumShade_WaitingFor = nil	
	elseif string.match(data,"HunterDouglas Shade Controller") then
		PlatinumShade_ActLevel = 0
		PlatinumShade_WaitingFor = nil
		PlatinumShade_Queue = {}
		-- Set the date as $sdt02-21-07-2015-
		-- os.date returns Monday=1...Sunday=7
		-- $sdt needs Sunday=1..Saturday=7
		local dayOfWeek = tonumber(os.date("%u"))+1
		if dayOfWeek > 7 then
			dayOfWeek = 1
		end
		local dateString = os.date("$sdt%m-%d-0"..dayOfWeek.."-%Y-")
		Enqueue(dateString,"^%d %$done")
		local timeString = os.date("$stm%H-%M-%S-")
		-- Set time as $stm06-52-54-
		Enqueue(timeString,"^%d %$done")
		-- Get the first status inquiry
		Enqueue("$dat-", kUPD01)
		PlatinumShade_Connected = 4
	elseif string.match(data, "^%d %$done$") and PlatinumShade_WaitingFor == KShadeActionPending then
		-- $done - returned in response to $sdt (set date) and $stm (set time) and $pss (set shade position) commands
		-- Special handling for multiple pss commands in a scene.
		if #PlatinumShade_Queue > 0 and PlatinumShade_Queue[1].wait == KShadeActionPending then
			Outgoing(PlatinumShade_Queue[1].data)
			table.remove(PlatinumShade_Queue,1)
		else 
			PlatinumShade_WaitingFor = "^%d %$act00-00-"
			Outgoing("$rls")
		end
	elseif string.match(data, "^%d %$reset$") then
		-- $reset - A new database is about to be sent. Mark all objects as deleted for now and we will remove them when we sync
	    for k,v in pairs(PlatinumShade_Db.rooms) do
	    	v.deleted = true
	    end
	    for k,v in pairs(PlatinumShade_Db.shades) do
	    	v.deleted = true
	    end
	    for k,v in pairs(PlatinumShade_Db.scenes) do
	    	v.deleted = true
	    end
	    for k,v in pairs(PlatinumShade_Db.schedules) do
	    	v.deleted = true
	    end	    	  
	else
		-- $cr - Create Room
		-- 2 $cr00-10-0x056F-Dining Room
		local room_id_str, room_type_str, room_hash, room_desc = string.match(data, "^%d %$cr(%d%d)-(%d%d)-(0x%x%x%x%x)-(.*)$")
		if room_id_str ~= nil then
			local room_id = tonumber(room_id_str)
			local room_type = tonumber(room_type_str)
			if platinum_shade_types[room_type+1] == nil then
				log("Room="..room_id..
				    " type="..room_type.."="..ANSI_RED.."ERROR: Unknown type"..ANSI_RESET..
				    " description="..room_desc);
			else 
				local room = PlatinumShade_Db.rooms[room_id+1]
				if room == nil then
					room = {}
					PlatinumShade_Db.rooms[room_id+1] = room
				end
				room.room = room_id
				room.type = room_type
				room.description = room_desc
				room.deleted = nil
				room.shades = {}  
				log("Room="..room_id..
				    " type="..room_type.."="..platinum_shade_types[room_type+1].name..
				    " description="..room_desc);
			end
		else
		    -- $cs - Create Shade
			-- 2 $cs01-01-06-Front Window
			local shade_id_str, room_id_str, hash8, shade_desc = string.match(data, "^%d %$cs(%d%d)-(%d%d)-(%d%d)-(.*)$")
			if shade_id_str ~= nil then
				local shade_id = tonumber(shade_id_str)
				local room_id = tonumber(room_id_str)
				local room = PlatinumShade_Db.rooms[room_id+1]
				if room == nil then
					log("Shade="..shade_id..
					    " room="..room_id.."="..ANSI_RED.."ERROR: Unknown room"..ANSI_RESET.." description="..shade_desc);
				else 
					log("Shade="..shade_id..
					    " room="..room_id.."="..room.description..
					    " description="..shade_desc);
					local shade = PlatinumShade_Db.shades[shade_id+1]
					if shade == nil then
						shade = {}
						PlatinumShade_Db.shades[shade_id+1] = shade
					end
					shade.shade = shade_id
					shade.room = room_id
					shade.description = shade_desc
					shade.deleted = nil
					room.shades[shade_id+1] = true
					if PlatinumShade_Connected >= 5 then -- Do this only when receiving an unsoliscited $cs command
						SyncDevices()
					end  
				end 
			else
			    -- $cp - Report Shade position
				-- 2 $cp06-04-174-
				local shade_id_str,feature_str,position_str = string.match(data, "^%d %$cp(%d%d)-(%d%d)-(%d%d%d)-.*$")
				if shade_id_str ~= nil then
					local shade_id = tonumber(shade_id_str)
					local feature_num = tonumber(feature_str)
					local position = tonumber(position_str)
					if PlatinumShade_Db.shades[shade_id+1] == nil then
						log("Shade="..shade_id.."="..ANSI_RED.."ERROR Unknown shade"..ANSI_RESET)
					else
						local room_id = PlatinumShade_Db.shades[shade_id+1].room
						local room_type = PlatinumShade_Db.rooms[room_id+1].type
						if platinum_shade_types[room_type+1].feature[feature_num] == nil then
							if platinum_shade_types.all.feature[feature_num] == nil then
								log("Shade="..shade_id.."="..PlatinumShade_Db.shades[shade_id+1].description..
								    " room="..PlatinumShade_Db.rooms[room_id+1].description..
									" type="..platinum_shade_types[room_type+1].name..
									" feature="..feature_num.."="..ANSI_RED.."ERROR: Unknown feature for this shade type"..ANSI_RESET)
							else
								log("Shade="..shade_id.."="..PlatinumShade_Db.shades[shade_id+1].description..
								    " room="..PlatinumShade_Db.rooms[room_id+1].description..
									" type="..platinum_shade_types[room_type+1].name..
									" common feature="..feature_num.."="..platinum_shade_types.all.feature[feature_num]..
									" position="..position)
								UpdateShade(shade_id, feature_num, position)
							end
						else
							log("Shade="..shade_id.."="..PlatinumShade_Db.shades[shade_id+1].description..
							    " room="..PlatinumShade_Db.rooms[room_id+1].description..
								" type="..platinum_shade_types[room_type+1].name..
								" feature="..feature_num.."="..platinum_shade_types[room_type+1].feature[feature_num]..
								" position="..position)
							UpdateShade(shade_id, feature_num, position)
						end
					end
				else
				    -- $cm - Declare scene, name
					-- 1 $cm00-First Scene
					local scene_id_str, scene_desc = string.match(data, "^%d %$cm(%d%d)-(.*)$")
					if scene_id_str ~= nil then
						local scene_id = tonumber(scene_id_str)
						log("scene="..scene_id.." description="..scene_desc)
						local scene = PlatinumShade_Db.scenes[scene_id+1]
						if scene == nil then
							scene = {}
							PlatinumShade_Db.scenes[scene_id+1] = scene
						end 
						scene.scene = scene_id
						scene.description = scene_desc
						scene.deleted = nil
						if scene.shades == nil then
							scene.shades = {}
						end
						if scene.rooms == nil then
							scene.rooms = {}
						end
					else
					    -- $cp - declare shade in scene
						-- 1 $cq00-08-01-
						local scene_id_str, shade_id_str, enable_str = string.match(data, "^%d %$cq(%d%d)-(%d%d)-(%d%d)-.*$")
						if scene_id_str ~= nil then
							local scene_id = tonumber(scene_id_str)
							local shade_id = tonumber(shade_id_str)
							local enable = tonumber(enable_str)
							if PlatinumShade_Db.scenes[scene_id+1] == nil then
								log("Scene="..scene_id.."="..ANSI_RED.."ERROR: Unknown Scene"..ANSI_RESET)
							elseif PlatinumShade_Db.shades[shade_id+1] == nil then
								log("Scene="..scene_id.."="..PlatinumShade_Db.scenes[scene_id+1].description..
								    " Shade="..shade_id.."="..ANSI_RED.."ERROR: Unknown shade"..ANSI_RESET)
							else
								log("Scene="..scene_id.."="..PlatinumShade_Db.scenes[scene_id+1].description..
								    " Shade="..shade_id.."="..PlatinumShade_Db.shades[shade_id+1].description..
									" enable="..tostring(enable > 0))
								PlatinumShade_Db.scenes[scene_id+1].shades[shade_id+1] = (enable > 0)
								PlatinumShade_Db.scenes[scene_id+1].deleted = nil
							end
						else
							-- $cx - Set shade position in scene
							-- 1 $cx03-00-04-187-00-
							local scene_id_str, room_id_str, feature_str, position_str, unknown_str = string.match(data, "^%d %$cx(%d%d)-(%d%d)-(%d%d)-(%d%d%d)-(%d%d)-.*$")
							if scene_id_str ~= nil then
								local scene_id = tonumber(scene_id_str)
								local room_id = tonumber(room_id_str)
								local feature_num = tonumber(feature_str)
								local position = tonumber(position_str)
								if PlatinumShade_Db.scenes[scene_id+1] == nil then
									log("Scene="..scene_id.."="..ANSI_RED.."ERROR: Unknown Scene"..ANSI_RESET)
								elseif PlatinumShade_Db.rooms[room_id+1] == nil then
									log("Scene ID="..scene_id.."="..PlatinumShade_Db.scenes[scene_id+1].description..
									    " Room="..room_id.."="..ANSI_RED.."ERROR: Unknown room"..ANSI_RESET)
								else
									local room_type = PlatinumShade_Db.rooms[room_id+1].type
									if platinum_shade_types[room_type+1].feature[feature_num] == nil then
										log("Scene="..scene_id.."="..PlatinumShade_Db.scenes[scene_id+1].description..
										    " Room="..room_id.."="..PlatinumShade_Db.rooms[room_id+1].description..
											" type="..platinum_shade_types[room_type+1].name.." feature="..feature_num.."="..ANSI_RED.."ERROR: Unknown feature for this shade type"..ANSI_RESET)
									else
										log("Scene="..scene_id.."="..PlatinumShade_Db.scenes[scene_id+1].description..
										    " Room="..room_id.."="..PlatinumShade_Db.rooms[room_id+1].description.. 
											" type="..platinum_shade_types[room_type+1].name.." feature="..feature_num.."="..platinum_shade_types[room_type+1].feature[feature_num]..
											" position="..position)
										PlatinumShade_Db.scenes[scene_id+1].rooms[room_id+1] = {feature=feature_num, position=position}
										PlatinumShade_Db.scenes[scene_id+1].deleted = nil
									end
								end
							else
							    -- $ca - Set scene schedule
								-- $ca10-03-144-05-55-
								local schedule_id_str, scene_id_str, days_str, hour_str, minute_str = string.match(data, "^%d %$ca(%d%d)-(%d%d)-(%d%d%d)-(%d%d%)-(%d%d)-.*$")
								if schedule_id_str ~= nil then
									local schedule_id = tonumber(schedule_id_str)
									local scene_id = tonumber(schedule_id_str)
									local days = tonumber(days_str)
									local hour = tonumber(hour)
									local minute = tonumber(minute)
									if PlatinumShade_Db.scenes[scene_id+1] == nil then
									    log("Schedule="..schedule_id..
									        " Scene="..scene_id.."="..ANSI_RED.."ERROR: Unknown Scene"..ANSI_RESET)
									elseif daye < 0 or days > 255 then
										log("Schedule="..schedule_id.. 
										    " scene="..scene_id.."="..PlatinumShade_Db.scenes[scene_id+1].description..
											" "..ANSI_RED.."ERROR: Invalid days="..minute..""..ANSI_RESET)
									elseif hour < 0 or hour > 23 then
										log("Schedule="..schedule_id.. 
										    " scene="..scene_id.."="..PlatinumShade_Db.scenes[scene_id+1].description..
											" "..ANSI_RED.."ERROR: Invalid hour="..minute..""..ANSI_RESET)
									elseif minute < 0 or minute > 59 then
										log("Schedule="..schedule_id.. 
										    " scene="..scene_id.."="..PlatinumShade_Db.scenes[scene_id+1].description..
											" "..ANSI_RED.."ERROR: Invalid minute="..minute..""..ANSI_RESET)
									else
										local enable = bit.band(days, 128) ~= 0
										if PlatinumShade_Scehdules[schedule_id+1] == nil then
										   PlatinumShade_Scehdules[schedule_id+1] = {}
										end
									    local schedule = PlatinumShade_Db.schedules[schedule_id+1]
										schedule.deleted = nil
										local xdays = ""
										if bit.band(days, 128) then
										    local bitshift = 1
										    local first = true
											for i = 1, 7 do
												if bit.band(days, bitshift) ~= 0 then
													if not first then
														xdays = xdays .. ", "
													end
													xdays = xdays .. weekdays[i]
													first = false
												end
												bitshift = bitshift * 2
											end
										else
											xdays = "Disabled"
										end
										log("Schedule="..schedule_id.. 
										    " scene="..scene_id.."="..PlatinumShade_Db.scenes[scene_id+1].description..
											" days="..days.."="..xdays..
											" time="..hour..":"..minute)
									    schedule.id = schedule_id
									    schedule.scene = scene_id
										schedule.days = days
									    schedule.hour = hour
									    schedule.minute = minute		
									end
								else
									-- $upd00- - Start of update
									-- $upd01- - End of update
								    local upd_str = string.match(data, "^%d %$upd(%d+)-.*$")
									if upd_str then
										local upd_num = tonumber(upd_str)
										if upd_num == 0 then
											-- $upd00 -- Start of $dat report
											-- 1 $upd00
											PlatinumShade_Connected = 4
										elseif upd_num == 1 then
											-- $upd01 -- End of $dat report
											-- 1 $upd01-
											printTable(PlatinumShade_Db)
											SyncDevices()
											PlatinumShade_Connected = 5
											if PlatinumShade_WaitingFor ~= kUPD01 then				      
												log("Warning: Received $upd01 but waiting for "..tostring(PlatinumShade_WaitingFor))
											end
											PlatinumShade_WaitingFor = nil
										else
											log("Unknown $upd command:" .. data);
										end
									elseif not handled then
										log(ANSI_MAGENTA.."Ignored message: \"" .. data .. "\""..ANSI_RESET)
									end -- not $upd
								end -- not $ca
							end -- not $cx
						end -- not $cq
					end -- not $cm
				end -- not $cp
			end -- not $cs
		end -- not $cr  
	end	-- not $reset
	Dequeue()
end

-- This is the main function to change a shade position.
-- mode: 0: value is level from 0 (closed/down) to 100 (open/up)
-- mode: 1: value is 0 or 100 for fully closed or fully open
-- mode: 2: Value is 50 - Intermediate stop
function PlatinumShade_SetTarget(device, id, value, mode)
	log("PlatinumShade_SetTarget(device="..device.." id="..id.." value="..value..")")
	local id_prefix = id:sub(1,1)
    local id_num = tonumber(id:sub(2))
	local shade
	local room
	if id_prefix == "S" then
		shade = PlatinumShade_Db.shades[id_num+1]
		room = PlatinumShade_Db.rooms[shade.room+1]
	else
		room = PlatinumShade_Db.rooms[id_num+1]
	end
	local shade_type = platinum_shade_types[room.type+1]
	luup.variable_set("urn:upnp-org:serviceId:Dimming1",        "Target", tostring(value), device, false)
	luup.variable_set("urn:upnp-org:serviceId:WindowCovering1", "Target", tostring(value), device, false)
	local status = 0
	if mode == 0 and shade_type.tdbu then
		-- top-down/bottom-up shades are fully closed in the middle
		if value ~= shade_type.xover then
			status = 1
		end
	elseif value > 0 then
		status = 1
	end
	luup.variable_set("urn:upnp-org:serviceId:SwitchPower1",    "Target", tostring(status), device, false)
	local feature
	local position
	if mode == 2 then
		feature = 10
		position = 7
	elseif mode == 0 and shade_type.tdbu then
		-- Special handling for level targets on top-down/bottom-up shades
		-- 0-xover drives the middle rail. xover-100% drives the bottom rail.
		if value >= shade_type.xover then
			feature = shade_type.order[1]
			position = math.floor(((value - shade_type.xover) * 255 / (100 - shade_type.xover)) + .5)
		else
			feature = shade_type.order[2]
			position = math.floor(((shade_type.xover - value) * 255 / shade_type.xover) + .5)
		end	
	elseif #shade_type.order > 2 then
		if value < shade_type.xover/2 then      -- 0-9 -> feature[3] 0-255
			feature = shade_type.order[3] 
			position = math.floor((value                          * 255 / ((shade_type.xover/2)-1)) + .5)
		elseif value < shade_type.xover then    -- 10-19 -> feature[2] 0-255
			feature = shade_type.order[2] 
			position = math.floor(((value - (shade_type.xover/2)) * 255 / ((shade_type.xover/2)-1)) + .5)
		else                                    -- 20-100 -> feature[1] 0-255
			feature = shade_type.order[1] 
			position = math.floor(((value - shade_type.xover)     * 255 / (100 - shade_type.xover)) + .5)
		end
	elseif #shade_type.order > 1 then
		if value < shade_type.xover then
			feature = shade_type.order[2] 
			position = math.floor((value * 255 / shade_type.xover) + .5)
		else
			feature = shade_type.order[1] 
			position = math.floor(((value - shade_type.xover) * 255 / (100 - shade_type.xover)) + .5)
		end
	else
		feature = shade_type.order[1]
		position = math.floor((value * 255 / 100) + .5)
	end
	if id_prefix == "S" then
		log("Changing shade " .. id_num .. ": " .. shade.description .. " to feature: " .. feature .. " position: "  .. position)
	    return Enqueue("$pss" .. id_num .. "-" .. feature .. "-" .. position .. "-", KShadeActionPending)
	else
		log("Changing room " .. id_num .. ": " .. room.description .. " to feature: " .. feature .. " position: "  .. position)
	    return Enqueue("$psr" .. id_num .. "-" .. feature .. "-" .. position .. "-0-", "^%d %$act00-00-")
	end
end
