local state_file = "/opt/phase3c/performance/latest"

local function read_state()
  local values = {}
  local file = io.open(state_file, "r")
  if not file then
    return values
  end

  for line in file:lines() do
    local key, value = line:match("^([a-z_]+)=([0-9.]+)$")
    if key and value then
      values[key] = tonumber(value)
    end
  end
  file:close()
  return values
end

local function scrape()
  local values = read_state()
  metric("router_performance_last_run_timestamp_seconds", "gauge", nil, values.last_run_timestamp_seconds)
  metric("router_performance_download_valid", "gauge", nil, values.download_valid)
  metric("router_performance_upload_valid", "gauge", nil, values.upload_valid)
  metric("router_performance_download_valid_samples", "gauge", nil, values.download_valid_samples)
  metric("router_performance_upload_valid_samples", "gauge", nil, values.upload_valid_samples)
  metric("router_performance_run_success", "gauge", nil, values.run_success)
  metric("router_performance_download_aggregate_mbps", "gauge", nil, values.download_aggregate_mbps)
  metric("router_performance_upload_aggregate_mbps", "gauge", nil, values.upload_aggregate_mbps)
  metric("router_performance_download_single_mbps", "gauge", nil, values.download_single_mbps)
  metric("router_performance_upload_single_mbps", "gauge", nil, values.upload_single_mbps)
end

return { scrape = scrape }
