--- @since 26.8.15
-- Show the language composition of the current Git repository as a rounded
-- bar in Yazi's status bar. The languages, their chip colors, and their Nerd
-- Font icons all come from onefetch's own output.

local M = {}

local DEFAULTS = {
	side = "right",
	order = 500,
	width = 24,
	languages = 4,
	icons = true,
	percent = true,
	caps = { left = "\u{e0b6}", right = "\u{e0b4}" },
	timeout = 60,
	args = {},
}

-- Every onefetch info field except `languages`; skipping the rest keeps runs
-- fast on large histories (authors and churn walk every commit).
local DISABLED_FIELDS = {
	"project",
	"description",
	"head",
	"pending",
	"version",
	"created",
	"dependencies",
	"authors",
	"last-change",
	"contributors",
	"url",
	"commits",
	"churn",
	"lines-of-code",
	"size",
	"license",
}

-- onefetch prints the "Other" chip with a plain SGR color. Keep such colors as
-- Yazi color names, with an approximate RGB for choosing the label color.
local SGR_COLORS = {
	[30] = { "black", 0, 0, 0 },
	[31] = { "red", 205, 0, 0 },
	[32] = { "green", 0, 205, 0 },
	[33] = { "yellow", 205, 205, 0 },
	[34] = { "blue", 0, 0, 238 },
	[35] = { "magenta", 205, 0, 205 },
	[36] = { "cyan", 0, 205, 205 },
	[37] = { "gray", 229, 229, 229 },
	[90] = { "darkgray", 127, 127, 127 },
	[91] = { "lightred", 255, 0, 0 },
	[92] = { "lightgreen", 0, 255, 0 },
	[93] = { "lightyellow", 255, 255, 0 },
	[94] = { "lightblue", 92, 92, 255 },
	[95] = { "lightmagenta", 255, 0, 255 },
	[96] = { "lightcyan", 0, 255, 255 },
	[97] = { "white", 255, 255, 255 },
}

-- One legend entry of onefetch's languages field:
-- ESC[<chip color>m<icon>ESC[0m ESC[<value color>m<name> (<percent> %)ESC[0m
local LEGEND_ENTRY = "\27%[([%d;]+)m([^\27]-)\27%[0m \27%[[%d;]*m([^\27]-) %(([%d%.]+) %%%)\27%[0m"

local function linear(channel)
	channel = channel / 255
	if channel <= 0.03928 then
		return channel / 12.92
	end
	return ((channel + 0.055) / 1.055) ^ 2.4
end

-- WCAG relative luminance; above 0.179 black text reads better than white.
local function is_light(r, g, b)
	return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b) > 0.179
end

local function hex(r, g, b)
	return string.format("#%02x%02x%02x", r, g, b)
end

-- Neighbouring languages can share a chip color (TSX and TypeScript do), which
-- would merge their segments: move the later one toward white or black.
local function shade(r, g, b)
	local target, amount = 255, 0.25
	if is_light(r, g, b) then
		target, amount = 0, 0.2
	end
	local function mix(c)
		return math.floor(c + (target - c) * amount + 0.5)
	end
	return mix(r), mix(g), mix(b)
end

-- The Yazi color for an SGR color code, plus its (approximate) RGB.
local function chip_color(code)
	local n = {}
	for value in code:gmatch("%d+") do
		n[#n + 1] = tonumber(value)
	end
	if n[1] == 38 and n[2] == 2 and n[5] then
		return hex(n[3], n[4], n[5]), n[3], n[4], n[5]
	end
	for _, value in ipairs(n) do
		local named = SGR_COLORS[value]
		if named then
			return named[1], named[2], named[3], named[4]
		end
	end
	return "gray", 229, 229, 229
end

-- Display width of an icon or label: one cell per code point, which holds for
-- ASCII, Nerd Font icons, and onefetch's default chip.
local function text_width(s)
	local _, n = s:gsub("[^\128-\191]", "")
	return n
end

local function percent_text(percent)
	local rounded = math.floor(percent + 0.5)
	if rounded < 1 then
		return "<1%"
	end
	return rounded .. "%"
end

-- Parse onefetch's colored text output into
-- { name, icon, percent, color, fg } entries, in onefetch's order.
function M.parse(output)
	local languages = {}
	if type(output) ~= "string" then
		return languages
	end
	for code, icon, name, percent in output:gmatch(LEGEND_ENTRY) do
		local color, r, g, b = chip_color(code)
		local previous = languages[#languages]
		if previous and previous.color == color and color:sub(1, 1) == "#" then
			r, g, b = shade(r, g, b)
			color = hex(r, g, b)
		end
		languages[#languages + 1] = {
			name = name,
			icon = icon,
			percent = tonumber(percent) or 0,
			color = color,
			fg = is_light(r, g, b) and "#000000" or "#ffffff",
		}
	end
	return languages
end

-- Split `width` cells between the languages proportionally to their
-- percentages, giving each at least `min` cells when there is room for that.
-- Returns an empty table when the languages cannot all get a cell.
function M.layout(languages, width, min)
	local n = #languages
	local widths = {}
	if n == 0 or width < n then
		return widths
	end
	min = math.max(1, math.min(min, math.floor(width / n)))

	local total = 0
	for _, language in ipairs(languages) do
		total = total + math.max(language.percent, 0)
	end

	local used, rest = 0, {}
	for i, language in ipairs(languages) do
		local exact = width / n
		if total > 0 then
			exact = math.max(language.percent, 0) / total * width
		end
		widths[i] = math.max(min, math.floor(exact))
		rest[i] = exact - widths[i]
		used = used + widths[i]
	end

	-- Minimum widths can overshoot: shrink the widest segments first.
	while used > width do
		local k
		for i = 1, n do
			if widths[i] > min and (not k or widths[i] > widths[k]) then
				k = i
			end
		end
		widths[k] = widths[k] - 1
		rest[k] = rest[k] + 1
		used = used - 1
	end

	-- Rounding down leaves cells over: hand them out by largest remainder.
	while used < width do
		local k = 1
		for i = 2, n do
			if rest[i] > rest[k] then
				k = i
			end
		end
		widths[k] = widths[k] + 1
		rest[k] = rest[k] - 1
		used = used + 1
	end

	return widths
end

-- The text of one segment, centered in `width` cells: "<icon> <percent>" when
-- that fits with a cell of padding on each side, else the icon alone, else
-- nothing.
function M.label(language, width, icons, percent)
	local candidates = {}
	local icon = icons and language.icon ~= "" and language.icon or nil
	local share = percent and percent_text(language.percent) or nil
	if icon and share then
		candidates[#candidates + 1] = icon .. " " .. share
	end
	candidates[#candidates + 1] = icon or share

	for _, text in ipairs(candidates) do
		local w = text_width(text)
		if w + 2 <= width then
			local left = math.floor((width - w) / 2)
			return string.rep(" ", left) .. text .. string.rep(" ", width - w - left)
		end
	end
	return string.rep(" ", width)
end

local function positive(value, default)
	if type(value) == "number" and value > 0 then
		return value
	end
	return default
end

local function boolean(value, default)
	if type(value) == "boolean" then
		return value
	end
	return default
end

local function normalize(opts)
	opts = type(opts) == "table" and opts or {}

	local side = DEFAULTS.side
	if opts.side == "left" or opts.side == "right" then
		side = opts.side
	end

	local caps = { left = DEFAULTS.caps.left, right = DEFAULTS.caps.right }
	if type(opts.caps) == "table" then
		if type(opts.caps.left) == "string" then
			caps.left = opts.caps.left
		end
		if type(opts.caps.right) == "string" then
			caps.right = opts.caps.right
		end
	end

	local args = {}
	if type(opts.args) == "table" then
		for _, arg in ipairs(opts.args) do
			if type(arg) == "string" then
				args[#args + 1] = arg
			end
		end
	end

	return {
		side = side,
		order = type(opts.order) == "number" and opts.order or DEFAULTS.order,
		width = math.floor(positive(opts.width, DEFAULTS.width)),
		languages = math.max(1, math.floor(positive(opts.languages, DEFAULTS.languages))),
		icons = boolean(opts.icons, DEFAULTS.icons),
		percent = boolean(opts.percent, DEFAULTS.percent),
		caps = caps,
		timeout = positive(opts.timeout, DEFAULTS.timeout),
		args = args,
	}
end

-- Search results and remote (SFTP) directories have no local Git checkout.
local function local_cwd(current)
	local cwd = current and current.cwd
	if cwd and cwd.spec.is_regular then
		return tostring(cwd)
	end
	return nil
end

local function bar(st, status)
	local opts = st._opts
	local cwd = local_cwd(status._current)
	local root = cwd and st._dirs[cwd]
	local repo = root and st._repos[root]
	if not repo or #repo.languages == 0 then
		return ""
	end

	local languages = repo.languages
	local width = math.min(opts.width, math.floor(status._area.w / 4))
	local widths = M.layout(languages, width, opts.icons and 3 or 1)
	if #widths == 0 then
		return ""
	end

	local spans = { ui.Span(" ") }
	if opts.caps.left ~= "" then
		spans[#spans + 1] = ui.Span(opts.caps.left):fg(languages[1].color)
	end
	for i, w in ipairs(widths) do
		local language = languages[i]
		spans[#spans + 1] = ui.Span(M.label(language, w, opts.icons, opts.percent))
			:fg(language.fg)
			:bg(language.color)
	end
	if opts.caps.right ~= "" then
		spans[#spans + 1] = ui.Span(opts.caps.right):fg(languages[#widths].color)
	end
	spans[#spans + 1] = ui.Span(" ")
	return ui.Line(spans)
end

-- The active tab's directory, what is known about it, and the options.
local prepare = ya.sync(function(st, force)
	if not st._opts then
		return nil
	end
	local cwd = local_cwd(cx.active.current)
	if not cwd then
		return nil
	end
	local root = st._dirs[cwd]
	if force then
		root = nil
	end
	return { cwd = cwd, root = root, opts = st._opts }
end)

-- Record which repository `cwd` belongs to, and decide whether onefetch has
-- to run for it. At most one run per repository is in flight at a time.
local claim = ya.sync(function(st, cwd, root, force)
	st._dirs[cwd] = root
	if not root or st._pending[root] or (st._repos[root] and not force) then
		ui.render()
		return false
	end
	st._pending[root] = true
	return true
end)

local finish = ya.sync(function(st, root, languages, err)
	st._pending[root] = nil
	st._repos[root] = { languages = languages, error = err }
	ui.render()
end)

local first_time = ya.sync(function(st, key)
	if st._warned[key] then
		return false
	end
	st._warned[key] = true
	return true
end)

local function notify(level, content)
	ya.notify({ title = "onefetch", content = content, timeout = 5, level = level })
end

-- The nearest ancestor of `cwd` (itself included) holding a `.git` entry,
-- which covers regular checkouts, worktrees, and submodules.
local function find_root(cwd)
	local url = Url(cwd)
	while url do
		if fs.cha(url:join(".git")) then
			return tostring(url)
		end
		url = url.parent
	end
	return false
end

local function first_line(text)
	for line in tostring(text or ""):gmatch("[^\r\n]+") do
		local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
		if trimmed ~= "" then
			return trimmed
		end
	end
	return nil
end

-- Run onefetch in `root`. Returns the parsed languages, or nil plus an error
-- kind ("missing", "timeout", "failed") and message.
local function fetch(root, opts)
	local args = {
		"--no-title",
		"--no-art",
		"--no-color-palette",
		"--true-color",
		"always",
		"--number-of-languages",
		tostring(opts.languages),
	}
	if opts.icons then
		args[#args + 1] = "--nerd-fonts"
	end
	for _, arg in ipairs(opts.args) do
		args[#args + 1] = arg
	end
	-- Last, so that the multi-value option cannot swallow other arguments.
	args[#args + 1] = "--disabled-fields"
	for _, field in ipairs(DISABLED_FIELDS) do
		args[#args + 1] = field
	end

	local child, err = Command("onefetch")
		:arg(args)
		:cwd(root)
		:stdout(Command.PIPED)
		:stderr(Command.PIPED)
		:spawn()
	if not child then
		return nil, "missing", tostring(err)
	end

	local stdout, stderr = {}, {}
	local deadline = ya.time() + opts.timeout
	while true do
		local left = math.floor((deadline - ya.time()) * 1000)
		if left <= 0 then
			child:start_kill()
			child:wait()
			return nil, "timeout", string.format("onefetch took longer than %gs in %s", opts.timeout, root)
		end
		local line, event = child:read_line_with({ timeout = left })
		if event == 0 then
			stdout[#stdout + 1] = line
		elseif event == 1 then
			stderr[#stderr + 1] = line
		elseif event == 2 then
			break
		end
	end

	local status = child:wait()
	if not status or not status.success then
		return nil, "failed", first_line(table.concat(stderr, "\n")) or "onefetch failed in " .. root
	end
	return M.parse(table.concat(stdout, "\n"))
end

function M:setup(opts)
	local st = self
	st._opts = normalize(opts)
	st._dirs = st._dirs or {}
	st._repos = st._repos or {}
	st._pending = st._pending or {}
	st._warned = st._warned or {}

	-- Re-register on repeated setup() calls so a new side/order applies.
	if st._child then
		Status:children_remove(st._child, st._child_side)
	end
	st._child_side = st._opts.side == "left" and Status.LEFT or Status.RIGHT
	st._child = Status:children_add(function(status)
		local ok, line = pcall(bar, st, status)
		return ok and line or ""
	end, st._opts.order, st._child_side)

	if st._subscribed then
		return
	end
	-- `cd` covers startup, navigation, and new tabs; `tab` covers switching
	-- to a tab whose directory has not been looked at yet.
	local function request()
		local ok, cwd = pcall(function()
			return local_cwd(cx.active.current)
		end)
		if ok and cwd and st._dirs[cwd] == nil then
			ya.emit("plugin", { st._id or "onefetch" })
		end
	end
	st._subscribed = pcall(function()
		ps.sub("cd", request)
		ps.sub("tab", request)
	end)
end

function M:entry(job)
	local args = job and job.args or {}
	local force = args[1] == "refresh"
	local ctx = prepare(force)
	if not ctx then
		if force then
			notify("warn", "Not a local directory, or setup() was not called")
		end
		return
	end

	local root = ctx.root
	if root == nil then
		root = find_root(ctx.cwd)
	end
	if not claim(ctx.cwd, root, force) then
		if force and not root then
			notify("info", "Not inside a Git repository")
		end
		return
	end

	local languages, kind, message = fetch(root, ctx.opts)
	finish(root, languages or {}, message)
	if kind == "missing" then
		if first_time("missing") then
			notify("error", "Cannot run onefetch (" .. message .. "). Install onefetch 2.22.0 or newer.")
		end
	elseif kind == "failed" and message:find("^error:") then
		-- onefetch rejected its arguments ("Error:" marks runtime failures):
		-- an onefetch older than 2.22.0, or a typo in the `args` option.
		if force or first_time("arguments") then
			notify("error", message)
		end
	elseif kind and force then
		notify("warn", message)
	end
end

return M
