
local WAYPOINT_FILE ="./scripts/waypoints.csv"

--  Vehicle Mode for quadplane 
AUTO = 10
GUIDED = 15
RTL = 11
QRTL =21

-- Flags to control
AUTO_MODE = false
ARMED =false
FLYING = false
MISSION =false
SAFE = false
GUIDED_MODE =false
VTOL_TAKEOFF = false
RTL_MODE = false
WP_INDEX = 1
WP_RADIUS =100
WP_DONE = nil




-- Function to split a string by a given separator
function split(str, sep)
    local fields = {}
    local pattern = string.format("([^%s]+)", sep)
    str:gsub(pattern, function(c) fields[#fields + 1] = c end)
    return fields
end

-- Function to read a CSV file and store it in a table
function readCSV(filename)
    local file = io.open(filename, "r")
    local data = {}
    
    for line in file:lines() do
        local fields = split(line, ",")
        table.insert(data, fields)
    end
    
    file:close()
    return data
end


-- Function to extract lat, lon, and alt into an array
function extractCoordinates(data)
    local array = {}
    -- Start processing from the second row (skip the header)
    for i = 1, #data do
        local lat = math.floor(tonumber(data[i][1])*1e7)
        local lng = math.floor(tonumber(data[i][2])*1e7)
        local alt = math.floor(tonumber(data[i][3]))
        if lat and lng and alt then
            table.insert(array, {lat = lat, lng = lng, alt = alt})
        end
    end
    return array
end

-- Function to print the array values
function printArray(array)
    for i, coords in ipairs(array) do
        print(string.format("Coordinates %d: lat = %f, lng = %f, alt = %f", i, coords.lat, coords.lng, coords.alt))
    end
end


function isSafe()
    if not arming:is_armed() then 
        if not vehicle:get_likely_flying() then
            if not ahrs:healthy() then
                gcs:send_text(6, "Prearm Check failed")
                return isSafe,1000
            else 
                gcs:send_text(6,"Prearm is Healthy")
                vehicle:set_mode(19)
                return true
            
            end
        else
            gcs:send_text(6,"Plane is Already Flying..")
            return false
        end
    else
        gcs:send_text(6,"Already Armed")
        arming:disarm()
        return false
    end
    return true


end
function compareAltitude(home_position, current_position)
    local home_altitude = math.floor(tonumber(home_position:alt())*0.01)
    local current_altitude = math.floor(tonumber(current_position:alt())*0.01)
    if current_altitude >= home_altitude + 30 then
        return true
    end
end

function update()
    local csvData = readCSV(WAYPOINT_FILE)
    local wp_point_arr = extractCoordinates(csvData)
    local home = ahrs:get_home()
    local mode = vehicle:get_mode()
    WP_DONE = mission:get_current_nav_index()
    gcs:send_text(6,string.format("Way Point Now: %d",WP_DONE))
    
    if not SAFE then
        if isSafe() then
            SAFE = true
            return update,1000
        end
    end

    if arming:is_armed() and SAFE and not ARMED and not MISSION and not AUTO_MODE and not GUIDED_MODE then
        ARMED =true
        gcs:send_text(6,"Plane is Armed Successful")
        return update,1000
    end

    if mode == AUTO and SAFE and not AUTO_MODE and not MISSION and ARMED and not VTOL_TAKEOFF and not GUIDED_MODE then
        gcs:send_text(6,"Plane Changed to AUTO")
        AUTO_MODE = true
        VTOL_TAKEOFF = true
        return update,1000
    end

    local current_position = ahrs:get_position()
    if current_position == nil then
        return update,1000
    end
    
    

    if SAFE and not MISSION and AUTO_MODE and VTOL_TAKEOFF and compareAltitude(home,current_position) and not GUIDED_MODE then 
        gcs:send_text(6,"Flying Stage..")
        AUTO_MODE =false
        VTOL_TAKEOFF = false
        if vehicle:set_mode(GUIDED) then
            gcs:send_text(6,"Plane Changed to GUIDED")
            GUIDED_MODE = true
        else 
            gcs:send_text(6,"Unable to Change vehicle mode to GUIDED")
        end
        
    end

    if mode == GUIDED and SAFE and not VTOL_OFF and GUIDED_MODE then
        gcs:send_text(6,"Let's Start Mission")
        printArray(wp_point_arr)
        
        MISSION = true
    end

    if MISSION and SAFE and GUIDED_MODE then
        gcs:send_text(6,"Way Point")
        
        local wp_next = Location() wp_next:lat(wp_point_arr[WP_INDEX].lat) wp_next:lng(wp_point_arr[WP_INDEX].lng) wp_next:alt((wp_point_arr[WP_INDEX].alt*100)+home:alt())
        local distance = current_position:get_distance(wp_next)
        local typedistance = tostring(distance)
   

        gcs:send_text(6,string.format("distance %s",typedistance))
        if distance <= WP_RADIUS then
            if #wp_point_arr == WP_INDEX and not RTL_MODE then
                if vehicle:set_mode(RTL) then
                    gcs:send_text(6,"Plane Changed to RTL")
                    RTL_MODE = true
                    GUIDED_MODE =false
                else 
                    gcs:send_text(6,"Unable to Change vehicle mode to RTL")

                end
            else
                WP_INDEX = WP_INDEX+1
            end
        end
        vehicle:set_target_location(wp_next)
        gcs:send_text(6,string.format("wp_index %d",WP_INDEX))
    end
    return update,1000
end
return update,1000
