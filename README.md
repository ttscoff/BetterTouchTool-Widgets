# BetterTouchTool Widgets

A collection of tools for creating Touch Bar and Menu Bar widgets using BetterTouchTool.

### Installation

You can put the `btt_stats.rb` script anywhere you like. It doesn't necessarily even need to be in your `$PATH`, as you'll need to hardcode it's absolute path in BetterTouchTool anyway. All the same, I personally keep mine in `~/scripts`, which happens to be in my PATH, thus it's easy to run from the command line.

Make the script executable by running `chmod a+x /path/to/btt_stats.rb`.

### Configuration

To create a configuration file, run `btt_stats.rb -h`. This will show the help screen, and also create an initial configuration file at `~/.config/bttstats.yml`. Open that file in any text editor and edit the options as you see fit. They're described in comments below for reference.

```
---
:bar_width: 8 # Default width of bar graphs for CPU and memory usage display
:colors:
  :activity:
    :active:
      :fg: "#000000" # Foreground color for "active". Only applies to `doing`, active means a task is currently running
      :bg: rgba(165, 218, 120, 1.00) # Background color. You can use hex or RGBA.
    :inactive:
      :fg: "#ffffff" # Colors for when no task was returned by the `doing` subcommand
      :bg: rgba(67, 76, 95, 1.00)
  :severity:
  # Severity levels define the foreground and background colors for 
  # a percentage at or below a certain threshold.
  # They must be in numerical order from lowest to highest, but you 
  # can use any breakpoints you want.
  - :max: 60
    :fg: "#000000"
    :bg: rgba(162, 191, 138, 1.00)
  - :max: 75
    :fg: "#000000"
    :bg: rgba(181, 141, 174, 1.00)
  - :max: 90
    :fg: "#000000"
    :bg: rgba(210, 135, 109, 1.00)
  - :max: 1000
    :fg: "#000000"
    :bg: rgba(197, 85, 98, 1.00)
  :zoom: # Colors for Zoom buttons
    :on: # Used for unmuted, video on, and sharing on
      :fg: "#000000"
      :bg: rgba(171, 242, 19, 1.00)
    :off: # Used for muted, video off, and sharing off
      :fg: "#ffffff"
      :bg: rgba(255, 0, 0, 1.00)
    :record: # Color when recording is inactive
      :fg: "#ffffff"
      :bg: rgba(18, 203, 221, 1.00)
    :recording: # Color when recording is active
      :fg: "#ffffff"
      :bg: rgba(182, 21, 15, 1.00)
    :leave: # Color for "Leave" button
      :fg: "#ffffff"
      :bg: rgba(255, 0, 0, 1.00)
:refresh:
# Refresh settings are shortcuts to refreshing widgets using 
# `btt_stats.rb refresh KEY`. You can define any key name you want,
# and keys can be nested and called like `btt_stats.rb refresh bunch:comms`
# The content of the key is the widget's UUID, which you can get by right
# clicking a widget and selecting "Copy UUID"
  doing: 6431A469-F09E-412C-9946-5FEB31CB8368
  cpu1: C8F8D01F-0AB3-4261-AE77-91994F211421
  cpu2: D2B01D67-CB14-4A68-B333-EF7D308E26B8
  bunch:
    comms: 3392D549-15D8-47BA-AC8D-DC9A4741B8FC
# ... etc.
# Keys can also be arrays, so calling the below with 
# `btt_stats.rb refresh doing` would refresh both widgets listed.
  doing:
  - 6431A469-F09E-412C-9946-5FEB31CB8368
  - 1A085A05-95E0-4D3C-A9D8-B87115EE819E
# If you want to use `btt_stats.rb` to just return plain text without
# the JSON formatting it uses for BetterTouchTool widgets, set :raw to true
:raw: false
```

### Add Widgets

You can use `btt_stats.rb` to automatically add selected widgets to either your Touch Bar or your menu bar. (Or, hey, maybe both. Weirdo.) To see a list of available widgets, just run `btt_stats.rb add` with no arguments.

```
$ btt_stats.rb add
First argument must be 'touch' or 'menu'
Example: btt_stats.rb add touch ip lan
Available commands:
cpu bar - CPU Bar
cpu double - CPU Split Bar
cpu percent - CPU Percent, 1m avg
memory bar - Memory
memory percent - Memory
ip lan - LAN IP
ip wan - WAN IP
network location - Network Location
network interface - Network Interface
doing - Doing
close - Touch Bar Close Button
bunch - Bunch Group
```

As noted in the output above, the first argument after `add` must be either `touch` or `menu`, which tells the script whether to add the widget to the Touch Bar or the menu bar. A complete command that adds a CPU meter to your Touch Bar would look like:

```
btt_stats.rb add touch cpu bar
```

When you add a widget via external script, BetterTouchTool does not show the new widget in the config right away. You need to switch to a different page of the configuration window and then back to see the new widget(s). And if they don't immediately show up in your Touch/menu bar, you may need to then hide and show them to get them to stick. Still saves you some time.

The location of the `btt_stats.rb` script is hardcoded into the new widgets based on where the script is when you run it. Make sure the script is saved to a permanent location before creating widgets with it.


### Available Commands

Use `btt_stats.rb SUBCOMMAND` to output various widgets. All commands respond to the following switches:

- `--prefix PREFIX` outputs the specified text before the content
- `--suffix SUFFIX` outputs the specified text after the content
- `--width WIDTH` applies to any command that outputs a graph. This overrides the `:bar_width` setting in the config for just the current command
- `--raw` outputs only the text without the JSON that's used by BetterTouchTool to add things like background colors to the widget

Available subcommands are:

- `btt_stats.rb cpu` outputs a graph of current CPU load. It has a few options available:
    - `cpu --averages` can limit it to certain averages (1, 5, or 15m). To show just the 5 and 15m averages, you would use `cpu --averages 5,15`. In regular graph mode averages are overlapping, with the lowest average (default 1 minute) in a dark bar on top.
    - You can output a percentage instead of a graph with `cpu --percent`.
    - `-i` determines whether a background color is included indicating severity.
    - `--color_from` tells the widget where to pull its severity indicator color from. By default this is 1, but if you wanted to only show background colors for the 15 minute average, you would use `cpu --color_from 15`.
    - `--split_cpu` will output a two-line chart, with the lowest average on top, and the additional 1 or 2 averages overlapping on the bottom.    
- `btt_stats.rb memory` outputs the current amount of used memory. 
    - Like `cpu`, you can use `--percent` to output it as just `56%` instead of a graph. 
    - Use `--free` to show the graph or percentage as free memory instead of used memory
    - If `--top` is included and the used memory is at 100%, the name of the app or process using the most memory will be displayed after the graph.
- `btt_stats.rb ip` outputs the current local IP address
    - use `ip wan` to output the public (WAN) IP address
- `btt_stats.rb network` outputs the current Network Location
    - use `network interface` to output the active network interface (Ethernet, Wi-fi, etc.), that currently has priority.
- `btt_stats.rb zoom status` outputs status reports for zoom states
  - All states return empty if Zoom is not running or no meeting is active. If active, an icon and color are returned indicating each state
  - `status mic` (muted or unmuted)
  - `status video` (video on or off)
  - `status sharing` (desktop sharing active or inactive)
  - `status recording` (local or cloud recording active) 
- `btt_stats.rb zoom` can also perform actions
  - `zoom mute` toggles mic mute
  - `zoom video` toggles camera
  - `zoom share` toggles desktop sharing
  - `zoom leave` leaves the current meeting
  - `zoom record` toggles local recording
  - `zoom cloud` toggles cloud recording
- `btt_stats.rb doing` will output any active `doing` task (only the most recent). This requires having a `btt` view in `.doingrc` (see below)
- `refresh [key:path ...]` is a shortcut to trigger a refresh of a configured widget

### Zoom setup

Zoom buttons only work well with the Touch Bar --- in their current implementation they're a bit frustrating as menu bar widgets.

You can add buttons for mic, video, leave, share, and record.

```
btt_stats.rb add zoom mic
btt_stats.rb add zoom video
btt_stats.rb add zoom leave
btt_stats.rb add zoom share
btt_stats.rb add zoom record
```

Buttons will disappear if a Zoom meeting isn't active. Buttons added using the script also have associated actions assigned for toggling their related function (mute, video, etc.).

You can customize the colors for various buttons and states in `:colors:` config in `~/.config/bttstats.yml`.

#### Faster Refreshing

The buttons take up to 5 seconds to update after a setting changes. If you'd like a faster response when toggling from the Touch Bar, add the UUIDs for the buttons to your `:refresh` config. You can hit ⌘C on each widget and then run `btt_stats.rb uuids install` to add them to your config.

Then add a refresh command to the button's shell script action (modifying for each type):

```
btt_stats.rb zoom toggle mute
sleep 1
btt_stats.rb refresh "Zoom Mute"
```

The `sleep` delay is needed because the script uses AppleScript UI scripting to toggle the buttons, so it takes a second for the change to register.

The refresh will only be triggered when toggling from the Touch Bar. If you toggle the feature from the app or elsewhere, there will still be a 5-second delay.

#### Language Specific

Because the Zoom functions use UI scripting and are only set up for English, if you're using a non-English system, you'll need to modify the menu strings it's looking for. In `~/.config/bttstats.yml`, edit the `:ui_strings` section with appropriate names for the menu items in your language.

### Doing setup

You can include an active [doing](http://brettterpstra.com/projects/doing) task by configuring a `btt` view in your `.doingrc`. To access the config file, just run `doing config` and it will open in your default editor.

Under `views`, add the following:

```yaml
views:
  btt:
    section: Currently
    count: 1
    order: desc
    template: "%title"
    tags_bool: NONE
    tags: done
```
You can test the output by running `doing view btt` on the command line. Add the widget with `btt_stats.rb add touch doing` (or `add menu doing`). Configure the background colors used in the `~/.config/bttstats.yml` configuration file.

### Bunch Setup

You can add a touch bar group for Bunch using `btt_stats.rb add touch bunch`. It will get a list of all your Bunches and create a widget for each one. Clicking the widget will toggle that Bunch, and its background will be determined by the open/closed state of its bunch. Setting up the necessary scripts is [detailed here](https://bunchapp.co/docs/integration/advanced-scripting/bunch-status-board/).

### Refresh Widget Shortcuts

In a lot of cases it's more efficient to "push" updates to the widgets rather than having them poll repeatedly. Bunch buttons and the `doing` widgets are prime examples. They only need to change when there's a change to the Bunch state or the doing file.

In both cases, it's worthwhile to set up a "hook" to refresh the widgets on change.

When setting up the refresh command, `btt_stats.rb` can simplify the configuration process. Just select the widget you want to refresh in the BetterTouchTool configuration panel, type ⌘C to copy the widget's info, then immediately run `btt_stats.rb uuids`. The clipboard will be parsed and a block of YAML will be output, ready to be added to your configuration file (`~/.config/bttstats.yml`). If you run `btt_stats.rb uuids install`, the resulting config options will automatically be added to your config file, merging with any current refresh items (existing items with the same name will be overwritten).

If you select a group, a YAML dictionary will be created with the group name as the key, containing entries for each widget in the group. These can be accessed using a key:path: `btt_stats.rb refresh GROUP:WIDGET`.

#### Doing

The latest version of the doing gem has a configuration option that will run a script any time the doing file is updated. To make use of this, you need to do the following:

1. Add a `doing` key to the refresh section of the `~/.config/bttstats.yml` file with the UUID of the doing widget (right click the widget and select "Copy UUID")
2. In your `.doingrc` (run `doing config`), add the following line:
    
        run_after: /path/to/btt_stats.rb refresh doing

Now whenever you run a command that alters the doing file, the widget will automatically be refreshed.

#### Bunch

If you've added Bunch buttons, you can have Bunch update your widgets whenever it opens or closes a Bunch. 

1. Add the UUIDs for the Bunch buttons to your config using the instructions above (select the Bunch group, copy, and run `btt_stats.rb uuids`)
2. Add a `folder.frontmatter` file to your root Bunch Folder with `run after` and `run after close` frontmatter keys set to `btt_stats.rb refresh "bunch:${title}"`.

This is detailed in the "Optimization" section of [this page](https://bunchapp.co/docs/integration/advanced-scripting/bunch-status-board/).
