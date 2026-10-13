# onefetch.yazi

A [Yazi](https://github.com/sxyazi/yazi) plugin that shows the language
composition of the current Git repository in the status bar, using
[onefetch](https://github.com/o2sh/onefetch).

The bar is a rounded pill split into one segment per language. Each segment
uses the language's onefetch chip color and shows its Nerd Font icon, plus its
percentage when the segment is wide enough. Languages beyond the configured
count are grouped into onefetch's gray "Other" segment.

## Requirements

- [onefetch](https://github.com/o2sh/onefetch) 2.22.0 or newer on `PATH`
  (`brew install onefetch`, `cargo install onefetch`, ...). Version 2.22.0
  added the `--nerd-fonts` icons this plugin displays.
- A [Nerd Font](https://www.nerdfonts.com/) in your terminal for the language
  icons and the rounded caps. Without one, set `icons = false` and plain
  `caps`.

## Compatibility

Maintained against Yazi/Ya `26.8.15`.

Requires Yazi 26.8.15 or newer.

## Installation

With `ya pkg`:

```sh
ya pkg add stellarjmr/onefetch
```

Or clone manually into your plugins directory:

```sh
git clone https://github.com/stellarjmr/onefetch.yazi.git \
  ~/.config/yazi/plugins/onefetch.yazi
```

## Usage

Add to `~/.config/yazi/init.lua`:

```lua
require("onefetch"):setup()
```

The bar appears on the right side of the status bar, just before the file
permissions, whenever the current directory is inside a Git repository.

All options are optional; these are the defaults:

```lua
require("onefetch"):setup({
	side      = "right", -- "left" or "right" half of the status bar
	order     = 500,     -- position among that half's items (permissions are 1000)
	width     = 24,      -- bar width in cells, caps excluded
	languages = 4,       -- languages shown before the rest become "Other"
	icons     = true,    -- Nerd Font language icons
	percent   = true,    -- percentages in segments wide enough for them
	caps      = { left = "\u{e0b6}", right = "\u{e0b4}" }, -- rounded ends; "" for none
	timeout   = 60,      -- seconds before a slow onefetch run is stopped
	args      = {},      -- extra onefetch arguments
})
```

On narrow terminals the bar shrinks to at most a quarter of the status bar.

`args` is passed to onefetch as-is. For example, `{ "--include-hidden" }`
counts hidden files, `{ "--exclude", "vendor" }` skips a directory, and
`{ "--type", "programming", "markup", "data" }` also counts data files such as
JSON and YAML. Leave out options the plugin sets itself, such as
`--number-of-languages` (use `languages`) and `--nerd-fonts` (use `icons`).

Results are cached per repository for the Yazi session. To re-run onefetch for
the current repository, for example after adding files, bind the `refresh`
argument in `~/.config/yazi/keymap.toml`:

```toml
[[mgr.prepend_keymap]]
on   = [ "g", "o" ]
run  = "plugin onefetch -- refresh"
desc = "Refresh the onefetch language bar"
```

## How it works

- On every directory change and tab switch, the plugin looks for the nearest
  ancestor containing `.git`, which covers regular checkouts, worktrees, and
  submodules.
- onefetch runs in the background once per repository, with every info field
  except languages disabled. Its colored output provides each language's chip
  color, Nerd Font icon, and percentage, so the bar matches onefetch itself.
- Segment widths follow the percentages. Each segment keeps at least room for
  its icon, and labels use black or white text, whichever reads better on the
  segment color. Neighboring languages that share a chip color, such as TSX
  and TypeScript, get slightly different shades.
- The bar is hidden outside Git repositories, in repositories onefetch cannot
  analyze (for example, ones without commits yet), and in search results and
  remote (SFTP) directories.
- A run that exceeds `timeout` is stopped, and that repository is not retried
  until you refresh it. This guards against very large working trees, such as
  a home directory tracked by Git.
- If onefetch cannot be started, or rejects its arguments, the plugin notifies
  once per session. Other failures are reported only when you refresh
  manually.

## License

MIT License - see [LICENSE](LICENSE) file for details.
