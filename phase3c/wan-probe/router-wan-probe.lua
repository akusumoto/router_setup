-- Router-originated WAN reachability probe. This intentionally uses one fixed
-- public IP address so the metric has no client-identity or payload data.
local target = "1.1.1.1"
local packet_count = 3
local timeout_seconds = 1

local function probe()
  local command = io.popen(
    "/bin/ping -n -c " .. packet_count .. " -W " .. timeout_seconds .. " " .. target .. " 2>&1"
  )
  if not command then
    return 0, packet_count, nil
  end

  local output = command:read("*a")
  command:close()

  local transmitted, received = output:match("(%d+) packets transmitted, (%d+) packets received")
  local average_ms = output:match("round%-trip min/avg/max = [%d.]+/([%d.]+)/[%d.]+ ms")
  return tonumber(received) or 0, tonumber(transmitted) or packet_count, tonumber(average_ms)
end

local function scrape()
  local received, transmitted, average_ms = probe()
  local labels = { target = target }

  metric("router_wan_probe_success", "gauge", labels, received > 0 and 1 or 0)
  metric("router_wan_probe_packet_loss_ratio", "gauge", labels, 1 - (received / transmitted))
  if average_ms then
    metric("router_wan_probe_rtt_seconds", "gauge", labels, average_ms / 1000)
  end
end

return { scrape = scrape }
