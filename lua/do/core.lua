local C = {}
local kaomoji = require("do.kaomojis")
local view = require("do.view")
local edit = require("do.edit")
local store = require("do.store")
local state = require("do.state").state
local default_opts = require("do.state").default_opts
local utils = require("do.utils")

---Show a message for the duration of `options.message_timeout`
---@param str string Text to display
---@param hl? string Highlight group
function C.show_message(str, hl)
	state.message = "%#" .. (hl or "TablineSel") .. "#" .. str

	vim.defer_fn(function()
		state.message = nil
	end, default_opts.message_timeout)
end

---add a task to the list
---@param str string task to add
---@param to_front boolean whether to add task to front of list
function C.add(str, to_front)
	state.tasks:add(str, to_front)
	utils.redraw_winbar()
	utils.exec_task_modified_autocmd()
end

--- Finish the first task
function C.done()
	if state.tasks:count() == 0 then
		C.show_message(kaomoji.confused() .. " There was nothing left to do…", "InfoMsg")
		utils.exec_task_modified_autocmd()
		return
	end

	state.tasks:shift()

	if state.tasks:count() == 0 then
		C.show_message(kaomoji.joy() .. " ALL DONE! " .. kaomoji.joy(), "TablineSel")
	else
		C.show_message(kaomoji.joy() .. " Great! Only " .. state.tasks:count() .. " to go.", "MoreMsg")
	end
	utils.redraw_winbar()
	utils.exec_task_modified_autocmd()
end

--- Edit the tasks in a floating window
function C.edit()
	edit.toggle_edit(state.tasks:get(), function(new_todos)
		state.tasks:set(new_todos)
		utils.exec_task_modified_autocmd()
	end)
end

--- save the tasks
function C.save()
	state.tasks:sync(true)
	utils.redraw_winbar()
end

--- sets up the plugin
---@param opts DoOptions
function C.setup(opts)
	state.options = vim.tbl_deep_extend("force", default_opts, opts or {})
	state.tasks = store.init(state.options.store)
	state.auGroupID = vim.api.nvim_create_augroup("do_nvim", { clear = true })

	if state.options.use_winbar then
		C.setup_winbar()
	end
	C.create_user_commands()

	C.shouldDisablePlugin()
	return C
end

--- configure displaying current to do item in winbar
function C.setup_winbar()
	utils.redraw_winbar()
	vim.o.winbar = nil
	vim.api.nvim_create_autocmd({ "WinEnter", "BufEnter" }, {
		group = state.auGroupID,
		callback = function()
			utils.redraw_winbar()
		end,
	})

	-- winbar should not be displayed in windows the cursor is not in
	vim.api.nvim_create_autocmd({ "WinLeave", "BufLeave" }, {
		group = state.auGroupID,
		callback = function()
			vim.wo.winbar = ""
		end,
	})
end

--- toggle the visibility of the winbar
function C.toggle()
	-- disable winbar completely when not visible
	vim.wo.winbar = vim.wo.winbar == "" and view.stl or ""
	state.view_enabled = not state.view_enabled
end

function C.view(variant)
	if variant == "active" then
		return view.render(state)
	end

	if variant == "inactive" then
		return view.render_inactive(state)
	end
end

---for things like lualine
function C.view_inactive()
	return view.render_inactive(state)
end

--- If there are currently tasks in the list
---@return boolean
function C.has_items()
	return state.tasks:count() > 0
end

--- determines if the taskbar should be visible
---@return boolean
function C.is_visible()
	return state.view_enabled and C.has_items()
end

--- checks if the plugin should be disabled based on the current filetype
function C.shouldDisablePlugin()
	vim.api.nvim_create_autocmd({ "BufEnter" }, {
		group = state.auGroupID,
		callback = function()
			local ft = vim.opt.filetype:get()
			-- if this is a filetype we disable, then delete the autocmds set by this plugin
			if vim.tbl_contains(state.options.disabled_ft, ft) then
				-- vim.api.nvim_del_autocmd(state.auGroupID)
				C.delete_user_commands()
			end
		end,
	})
end

--- create user commands for this plugin
function C.create_user_commands()
	local create = vim.api.nvim_create_user_command
	create("Do", function(args)
		C.add(args.args, args.bang)
	end, { nargs = 1, bang = true })

	create("Done", function(args)
		-- not sure if I like this.
		if not args.bang then
			C.show_message(kaomoji.doubt() .. " Really? If so, use `Done!`", "ErrorMsg")
			return
		end

		C.done()
	end, { bang = true })

	create("DoToggle", C.toggle, {})
	create("DoEdit", C.edit, {})
	create("DoSave", C.save, { bang = true })
end

--- delete the user commands defined by this plugin
function C.delete_user_commands()
	local delete = vim.api.nvim_del_user_command
	delete("Do")
	delete("Done")
	delete("DoToggle")
	delete("DoEdit")
	delete("DoSave")
end

return C
