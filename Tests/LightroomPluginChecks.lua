-- SDK doubles exercise the export action without touching a user's Lightroom catalog.
local plugin, base = arg[1], arg[2]
local sequence, checks, failedDestinations = 0, 0, 0
local function check(value, message) assert(value, message); checks = checks + 1 end
local modules = {
    LrFileUtils = { createAllDirectories = function() end },
    LrPathUtils = {
        child = function(a, b) return a .. '/' .. b end,
        getStandardFilePath = function() return base end,
        leafName = function(path) return path:match('([^/]+)$') end,
        parent = function(path) return path:match('^(.*)/[^/]+$') end,
    },
    LrTasks = { pcall = pcall, startAsyncTask = function(fn) end, sleep = function() end },
    LrUUID = { generateUUID = function() sequence = sequence + 1; return 'lua-test-' .. sequence end },
    LrView = {},
}
function import(name) assert(modules[name], name); return modules[name] end
local info = assert(loadfile(plugin .. '/Info.lua'))()
check(info.LrToolkitIdentifier == 'com.basiciggy.basicnotch.exportmonitor', 'plug-in identifier')
local monitor = assert(loadfile(plugin .. '/ExportMonitor.lua'))()
local function run(total, outcomes, raiseError)
    local cleanup
    local context = { addCleanupHandler = function(self, handler) cleanup = handler end }
    local filter = { renditionsToSatisfy = {} }
    for i = 1, total do filter.renditionsToSatisfy[i] = true end
    filter.renditions = function()
        local i = 0
        return function()
            i = i + 1
            if i > #outcomes then return nil end
            local index = i
            return {
                waitForRender = function()
                    if raiseError then error('Render task failed') end
                    if outcomes[index] then return true, '/tmp/exports/A & B <photo>.jpg' end
                    return false, 'Test render failure'
                end,
            }, {
                destinationPath = '/tmp/exports/A & B <photo>.jpg',
                renditionIsDone = function(self, success, message)
                    check(success == false, 'only explicitly fail failed renditions')
                    failedDestinations = failedDestinations + 1
                end,
            }
        end
    end
    local ok = pcall(monitor.postProcessRenderedPhotos, context, filter)
    if cleanup then cleanup() end
    local file = assert(io.open(base .. '/BasicNotch/LightroomExports/lua-test-' .. sequence .. '.plist', 'rb'))
    local text = file:read('*a'); file:close()
    return text, ok
end
local text, ok = run(3, { true, true, true })
check(ok and text:find('<string>completed</string>', 1, true), 'successful export')
check(text:find('A &amp; B &lt;photo&gt;.jpg', 1, true), 'escaped XML metadata')
text, ok = run(2, { true, false })
check(ok and text:find('<string>failed</string>', 1, true), 'render failure snapshot')
check(failedDestinations == 1, 'render failure propagated to Lightroom')
text, ok = run(3, { true })
check(ok and text:find('<string>cancelled</string>', 1, true), 'cancelled/incomplete export')
text, ok = run(1, { true }, true)
check(not ok and text:find('<string>failed</string>', 1, true), 'task exceptions recorded and rethrown')
-- Telemetry must not break exports when the monitor directory is unavailable.
local originalOpen = io.open
io.open = function() return nil, 'simulated permission denial' end
local context = { addCleanupHandler = function() end }
local filter = { renditionsToSatisfy = {}, renditions = function() return function() return nil end end }
ok = pcall(monitor.postProcessRenderedPhotos, context, filter)
io.open = originalOpen
check(ok, 'monitor write failures do not fail the export')
print('Passed ' .. checks .. ' Lightroom plug-in checks; generated real plist fixtures for Swift.')
