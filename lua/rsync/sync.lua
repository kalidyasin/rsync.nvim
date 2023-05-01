---
-- Syncing functionality

local project = require("rsync.project")

local sync = {}

local run_sync = function(command, project_path, on_start)
    local res = vim.fn.jobstart(command, {
        on_stderr = function(_, output, _)
            -- skip when function reports no error
            if vim.inspect(output) ~= vim.inspect({ "" }) then
                -- TODO print save output to temporary log file
                vim.api.nvim_err_writeln("Error executing: " .. command)
            end
        end,

        -- job done executing
        on_exit = function(_, code, _)
            _RsyncProjectConfigs[project_path]["sync_status"] = { code = code, progress = "exit" }
            if code ~= 0 then
                vim.api.nvim_err_writeln("rsync execute with result code: " .. code)
            end
        end,
        stdout_buffered = true,
        stderr_buffered = true,
    })

    if res == -1 then
        error("Could not execute rsync. Make sure that rsync in on your path")
    elseif res == 0 then
        print("Invalid command: " .. command)
    else
        on_start(res)
    end
end

local sync_project = function(source_path, destination_path, project_path)
    local command = "rsync -varz -f':- .gitignore' -f'- .nvim' " .. source_path .. " " .. destination_path
    run_sync(command, project_path, function(res)
        _RsyncProjectConfigs[project_path]["sync_status"] = { progress = "start", state = "sync_up", job_id = res }
    end)
end

local sync_remote = function(source_path, destination_path, include_extra, project_path)
    local filters = ""
    if type(include_extra) == "table" then
        local filter_template = "-f'+ %s' "
        for _, value in pairs(include_extra) do
            filters = filters .. filter_template:format(value)
        end
    elseif type(include_extra) == "string" then
        filters = "-f'+ " .. include_extra .. "' "
    end
    local command = "rsync -varz "
        .. filters
        .. "-f':- .gitignore' -f'- .nvim' "
        .. source_path
        .. " "
        .. destination_path
    run_sync(command, project_path, function(res)
        _RsyncProjectConfigs[project_path]["sync_status"] = { progress = "start", state = "sync_down", job_id = res }
    end)
end

sync.sync_up = function()
    local config_table = project.get_config_table()
    if config_table ~= nil then
        if config_table["sync_status"]["progress"] == "start" then
            if config_table["sync_status"]["state"] ~= "sync_up" then
                vim.api.nvim_err_writeln("Could not sync down, due to sync down still running")
                return
            else
                -- todo convert to jobwait + lua coroutines
                vim.fn.jobstop(config_table["sync_status"]["job_id"])
            end
        end
        sync_project(config_table["project_path"], config_table["remote_path"], config_table["project_path"])
    else
        vim.api.nvim_err_writeln("Could not find rsync.toml")
    end
end

sync.sync_down = function()
    local config_table = project.get_config_table()

    if config_table ~= nil then
        if config_table["sync_status"]["progress"] == "start" then
            if config_table["sync_status"]["state"] ~= "sync_down" then
                vim.api.nvim_err_writeln("Could not sync down, due to sync still running")
                return
            else
                -- todo convert to jobwait + lua coroutines
                vim.fn.jobstop(config_table["sync_status"]["job_id"])
            end
        end
        sync_remote(
            config_table["remote_path"],
            config_table["project_path"],
            config_table["remote_includes"],
            config_table["project_path"]
        )
    else
        vim.api.nvim_err_writeln("Could not find rsync.toml")
    end
end

return sync
