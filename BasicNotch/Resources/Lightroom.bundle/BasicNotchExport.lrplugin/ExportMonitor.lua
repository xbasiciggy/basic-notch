local LrFileUtils = import 'LrFileUtils'
local LrPathUtils = import 'LrPathUtils'
local LrTasks = import 'LrTasks'
local LrUUID = import 'LrUUID'
local LrView = import 'LrView'
local Monitor = {}

local function xml(value)
    return tostring(value):gsub('[%z\1-\8\11\12\14-\31]', ''):gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;'):gsub('"', '&quot;'):gsub("'", '&apos;')
end

local function writeSnapshot(folder, job)
    LrFileUtils.createAllDirectories(folder)
    local entries = { '<?xml version="1.0" encoding="UTF-8"?>', '<plist version="1.0"><dict>' }
    for _, key in ipairs({ 'version', 'id', 'state', 'total', 'completed', 'failed', 'startedAt', 'updatedAt', 'currentFile', 'outputFolder', 'message' }) do
        local value = job[key]
        if value ~= nil then
            local tag = type(value) == 'number' and 'integer' or 'string'
            entries[#entries + 1] = '<key>' .. key .. '</key><' .. tag .. '>' .. xml(value) .. '</' .. tag .. '>'
        end
    end
    entries[#entries + 1] = '</dict></plist>'
    local target = LrPathUtils.child(folder, job.id .. '.plist')
    local temp = LrPathUtils.child(folder, '.' .. job.id .. '.tmp')
    local handle, message = io.open(temp, 'wb')
    if not handle then error(message or 'Cannot write monitor snapshot') end
    local ok, writeError = handle:write(table.concat(entries, '\n'))
    handle:close()
    if not ok then error(writeError or 'Cannot write monitor snapshot') end
    -- macOS atomically replaces the previous snapshot, so the app never reads half a file.
    local moved, moveError = os.rename(temp, target)
    if not moved then error(moveError or 'Cannot replace monitor snapshot') end
end

function Monitor.sectionForFilterInDialog(f, propertyTable)
    return {
        title = 'BasicNotch Export Monitor',
        f:static_text { title = 'Shows rendering progress in BasicNotch on this Mac. Keep this action last in the list.', fill_horizontal = 1, wrap = true },
        f:static_text { title = 'Your export settings and image files are unchanged. Later upload/publish steps are not tracked.', fill_horizontal = 1, wrap = true },
    }
end

function Monitor.postProcessRenderedPhotos(context, filterContext)
    local folder = LrPathUtils.child(LrPathUtils.getStandardFilePath('appData'), 'BasicNotch/LightroomExports')
    local now = os.time()
    local job = {
        version = 1, id = LrUUID.generateUUID(), state = 'running',
        total = #filterContext.renditionsToSatisfy, completed = 0, failed = 0,
        startedAt = now, updatedAt = now,
    }
    local stopped = false
    local function emit()
        job.updatedAt = os.time()
        -- Monitoring failures must never interrupt the user's export.
        LrTasks.pcall(writeSnapshot, folder, job)
    end
    context:addCleanupHandler(function()
        if not stopped then
            stopped = true
            job.state = 'cancelled'
            job.message = 'The monitored export ended before all photos were rendered.'
            emit()
        end
    end)
    emit()
    LrTasks.startAsyncTask(function()
        while not stopped do
            LrTasks.sleep(2)
            if not stopped then emit() end
        end
    end)
    local ok, message = LrTasks.pcall(function()
        for source, destination in filterContext:renditions() do
            local success, pathOrMessage = source:waitForRender()
            if success then
                job.completed = job.completed + 1
                job.currentFile = LrPathUtils.leafName(pathOrMessage)
                job.outputFolder = LrPathUtils.parent(destination.destinationPath or pathOrMessage)
            else
                job.failed = job.failed + 1
                job.message = tostring(pathOrMessage or 'Lightroom could not render a photo.'):sub(1, 1000)
                destination:renditionIsDone(false, pathOrMessage)
            end
            emit()
            -- The SDK iterator satisfies unchanged successful renditions automatically.
        end
    end)
    stopped = true
    if not ok then
        job.state = 'failed'
        job.message = tostring(message):sub(1, 1000)
    elseif job.completed + job.failed < job.total then
        job.state = 'cancelled'
    elseif job.failed > 0 then
        job.state = 'failed'
    else
        job.state = 'completed'
    end
    emit()
    if not ok then error(message) end
end

return Monitor
