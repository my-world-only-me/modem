	local util = require "luci.util"
	local fs = require "nixio.fs"
	local sys = require "luci.sys"
	local http = require "luci.http"
	local dispatcher = require "luci.dispatcher"
	local http = require "luci.http"
	local sys = require "luci.sys"
	local uci = require "luci.model.uci".cursor()

module("luci.controller.modem.sms", package.seeall)

function index()
	entry({"admin", "network"}, firstchild(), "Modem", 30).dependent=false
	entry({"admin", "network", "sms"}, alias("admin", "network", "sms", "readsms"), translate("短信管理"), 20)
	entry({"admin", "network", "sms", "readsms"},template("network/readsms"),translate("接收信息"), 10)
 	entry({"admin", "network", "sms", "sendsms"},template("network/sendsms"),translate("发送信息"), 20)
 	entry({"admin", "network", "sms", "ussd"},template("network/ussd"),translate("USSD 代码"), 30)
	entry({"admin", "network", "sms", "atcommands"},template("network/atcommands"),translate("AT 命令"), 40)
	entry({"admin", "network", "sms", "smsconfig"},cbi("network/smsconfig"),translate("配置"), 50)
	entry({"admin", "network", "sms", "delete_one"}, call("delete_sms", smsindex), nil).leaf = true
	entry({"admin", "network", "sms", "delete_all"}, call("delete_all_sms"), nil).leaf = true
	entry({"admin", "network", "sms", "run_ussd"}, call("ussd"), nil).leaf = true
	entry({"admin", "network", "sms", "run_at"}, call("at"), nil).leaf = true
	entry({"admin", "network", "sms", "run_sms"}, call("sms"), nil).leaf = true
	entry({"admin", "network", "sms", "readsim"}, call("slots"), nil).leaf = true
	entry({"admin", "network", "sms", "countsms"}, call("count_sms"), nil).leaf = true
	entry({"admin", "network", "sms", "user_ussd"}, call("userussd"), nil).leaf = true
	entry({"admin", "network", "sms", "user_atc"}, call("useratc"), nil).leaf = true
	entry({"admin", "network", "sms", "user_phonebook"}, call("userphb"), nil).leaf = true
end


function delete_sms(smsindex)
local devv = tostring(uci:get("sms_tool", "general", "readport"))
local s = smsindex
for d in s:gmatch("%d+") do 
	os.execute("sms_tool -d " .. devv .. " delete " .. d .. "")
end
end

function delete_all_sms()
	local devv = tostring(uci:get("sms_tool", "general", "readport"))
	os.execute("sms_tool -d " .. devv .. " delete all")
end

function get_ussd()
    local cursor = luci.model.uci.cursor()
    if cursor:get("sms_tool", "general", "ussd") == "1" then
        return " -R"
    else
        return ""
    end
end


function get_pdu()
    local cursor = luci.model.uci.cursor()
    if cursor:get("sms_tool", "general", "pdu") == "1" then
        return " -r"
    else
        return ""
    end
end


function ussd()
    local devv = tostring(uci:get("sms_tool", "general", "ussdport"))

	local ussd = get_ussd()
	local pdu = get_pdu()

    local ussd_code = http.formvalue("code")
    if ussd_code then
	    local odpall = io.popen("sms_tool -d " .. devv .. ussd .. pdu .. " ussd " .. ussd_code .." 2>&1")
	    local odp =  odpall:read("*a")
	    odpall:close()
        http.write(tostring(odp))
    else
        http.write_json(http.formvalue())
    end
end


function at()
    local devv = tostring(uci:get("sms_tool", "general", "atport"))

    local at_code = http.formvalue("code")
    if at_code then
	    local odpall = io.popen("sms_tool -d " .. devv .. " at "  ..at_code:gsub("[$]", "\\\$"):gsub("\"", "\\\"").." 2>&1")
	    local odp =  odpall:read("*a")
	    odpall:close()
        http.write(tostring(odp))
    else
        http.write_json(http.formvalue())
    end
end


function sms()
    local devv = tostring(uci:get("sms_tool", "general", "sendport"))
    local sms_code = http.formvalue("scode")

    nr = (string.sub(sms_code, 1, 20))
    msgall = string.sub(sms_code, 21)
    msg = string.gsub(msgall, "\n", " ")

    if sms_code then
	    local odpall = io.popen("sms_tool -d " .. devv .. " send " .. nr .." '".. msg .."'")
	    local odp =  odpall:read("*a")
	    odpall:close()
        http.write(tostring(odp))
    else
        http.write_json(http.formvalue())
    end

end

function slots()
	local sim = { }
	local devv = tostring(uci:get("sms_tool", "general", "readport"))
	local led = tostring(uci:get("sms_tool", "general", "smsled"))
	local dsled = tostring(uci:get("sms_tool", "general", "ledtype"))
	local ln = tostring(uci:get("sms_tool", "general", "lednotify"))

	local smsmem = tostring(uci:get("sms_tool", "general", "storage"))

	local statusb = luci.util.exec("sms_tool -s" .. smsmem .. " -d ".. devv .. " status")
	local usex = string.sub (statusb, 23, 27)
	local max = statusb:match('[^: ]+$')
	sim["use"] = string.match(usex, '%d+')
	local smscount = string.match(usex, '%d+')
	if ln == "1" then
      		luci.sys.call("echo " .. smscount .. " > /etc/config/sms_count")
		if dsled == "S" then
		luci.util.exec("/etc/init.d/led restart")
		end
		if dsled == "D" then
		luci.sys.call("echo 0 > '/sys/class/leds/" .. led .. "/brightness'")
		end
 	end
	sim["all"] = string.match(max, '%d+')
	luci.http.prepare_content("application/json")
	luci.http.write_json(sim)
end


function count_sms()
    os.execute("sleep 3")
    local cursor = luci.model.uci.cursor()
    if cursor:get("sms_tool", "general", "lednotify") == "1" then
        local devv = tostring(uci:get("sms_tool", "general", "readport"))

	 local smsmem = tostring(uci:get("sms_tool", "general", "storage"))

        local statusb = luci.util.exec("sms_tool -s" .. smsmem .. " -d ".. devv .. " status")
        local smsnum = string.sub (statusb, 23, 27)
        local smscount = string.match(smsnum, '%d+')
        os.execute("echo " .. smscount .. " > /etc/config/sms_count")
    end
end


function uussd(rv)
	local c = nixio.fs.access("/etc/config/ussd.user") and
		io.popen("cat /etc/config/ussd.user")

	if c then
		for l in c:lines() do
			local i = l
			if i then
				rv[#rv + 1] = {
					usd = i
				}
			end
		end
		c:close()
	end
end



function userussd()
	local usd = { }
	uussd(usd)
	luci.http.prepare_content("application/json")
	luci.http.write_json(usd)
end


function uat(rv)
	local c = nixio.fs.access("/etc/config/atcmds.user") and
		io.popen("cat /etc/config/atcmds.user")

	if c then
		for l in c:lines() do
			local i = l
			if i then
				rv[#rv + 1] = {
					atu = i
				}
			end
		end
		c:close()
	end
end



function useratc()
	local atu = { }
	uat(atu)
	luci.http.prepare_content("application/json")
	luci.http.write_json(atu)
end



function uphb(rv)
	local c = nixio.fs.access("/etc/config/phonebook.user") and
		io.popen("cat /etc/config/phonebook.user")

	if c then
		for l in c:lines() do
			local i = l
			if i then
				rv[#rv + 1] = {
					phb = i
				}
			end
		end
		c:close()
	end
end



function userphb()
	local phb = { }
	uphb(phb)
	luci.http.prepare_content("application/json")
	luci.http.write_json(phb)
end
