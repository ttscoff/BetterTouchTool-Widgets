#!/usr/bin/env ruby -W1
# frozen_string_literal: true

# Memory, CPU, and other stats formatted to use in a BetterTouchTool touch bar
# script widget Also works in menu bar (Other Triggers), but be sure to select
# "Use mono space font."
require 'optparse'
require 'yaml'
require 'fileutils'
require 'json'
require 'shellwords'
$config_file = '~/.config/bttstats.yml'

# Hash methods
class ::Hash
  # Check that second hash contains all the keys of the first (nested compare)
  def compare_keys(second)
    res = true

    each do |k, v|
      if second.key?(k) && second[k].is_a?(v.class)
        next unless v.is_a? Hash

        res = v.compare_keys(second[k])
        break unless res
      else
        res = false
        break
      end
    end

    res
  end

  def deep_merge(second)
    merger = proc { |_, v1, v2| Hash === v1 && Hash === v2 ? v1.merge(v2, &merger) : Array === v1 && Array === v2 ? v1 | v2 : [:undefined, nil, :nil].include?(v2) ? v1 : v2 }
    merge(second.to_h, &merger)
  end

  def to_btt_url(method)
    query = CGI.escape(to_json).gsub(/\+/, '%20')
    %(btt://#{method}/?json=#{query})
  end

  def to_btt_as(method)
    query = to_json.gsub(/\\"/, '\\\\\\\\"').gsub(/"/, '\\\\"')
    %(tell application "BetterTouchTool" to #{method} "#{query}")
  end
end

class ::Array
  def to_btt_as(method)
    query = to_json.gsub(/\\"/, '\\\\\\\\"').gsub(/"/, '\\\\"')
    %(tell application "BetterTouchTool" to #{method} "#{query}")
  end
end

# String methods
class ::String
  def rgba_to_btt
    elements = match(/rgba?\((?<r>\d+), *(?<g>\d+), *(?<b>\d+)(?:, *(?<a>[\d.]+))?\)/)
    alpha = elements['a'] ? 255 * elements['a'].to_f : 255
    %(#{elements['r']},#{elements['g']},#{elements['b']},#{alpha.to_i})
  end

  def hex_to_btt
    rgb = match(/^#?(..)(..)(..)$/).captures.map(&:hex)
    "#{rgb.join(',')},255"
  end

  def btt_color
    color = strip.gsub(/ +/, '').downcase
    case color
    when /^rgba?\(\d+,\d+,\d+(,(0?\.\d+|1(\.0+)?))?\)$/
      color.rgba_to_btt
    when /^#?[a-f0-9]{6}$/
      color.hex_to_btt
    else
      '25,25,25,255'
    end
  end
end

# Settings
defaults = {
  raw: false,
  bar_width: 8,
  colors: {
    zoom: {
      on: {
        fg: '#000000',
        bg: 'rgba(171, 242, 19, 1.00)'
      },
      off: {
        fg: '#ffffff',
        bg: 'rgba(255, 0, 0, 1.00)'
      },
      record: {
        fg: '#ffffff',
        bg: 'rgba(18, 203, 221, 1.00)'
      },
      recording: {
        fg: '#ffffff',
        bg: 'rgba(182, 21, 15, 1.00)'
      },
      leave: {
        fg: '#ffffff',
        bg: 'rgba(255, 0, 0, 1.00)'
      }
    },
    # Default bar width
    activity: {
      active: {
        fg: '#333333',
        bg: 'rgba(165, 218, 120, 1.00)'
      },
      inactive: {
        fg: '#ffffff',
        bg: 'rgba(95, 106, 129, 1.00)'
      }
    },
    # Colors for level indicator, can be hex or rgb(a)
    # max is cutoff percentage for indicator level
    charge: [
      {
        max: 20,
        fg: '#000000',
        bg: 'rgba(197, 85, 98, 1.00)'
      },
      {
        max: 50,
        fg: '#000000',
        bg: 'rgba(210, 135, 109, 1.00)'
      },
      {
        max: 75,
        fg: '#000000',
        bg: 'rgba(210, 135, 109, 1.00)'
      },
      {
        max: 1000,
        fg: '#000000',
        bg: 'rgba(162, 191, 138, 1.00)'
      }
    ],
    severity: [
      {
        max: 60,
        fg: '#000000',
        bg: 'rgba(162, 191, 138, 1.00)'
      },
      {
        max: 75,
        fg: '#000000',
        bg: 'rgba(236, 204, 135, 1.00)'
      },
      {
        max: 90,
        fg: '#000000',
        bg: 'rgba(210, 135, 109, 1.00)'
      },
      {
        max: 1000,
        fg: '#000000',
        bg: 'rgba(197, 85, 98, 1.00)'
      }
    ]
  },
  ui_strings: {
    window_menu: 'Window',
    meeting_menu: 'Meeting',
    close: 'Close',
    unmute_audio: 'Unmute Audio',
    mute_audio: 'Mute Audio',
    start_video: 'Start Video',
    stop_video: 'Stop Video',
    start_share: 'Start Share',
    stop_share: 'Stop Share',
    record: 'Record',
    stop_record: 'Stop Recording',
    record_to_cloud: 'Record to the Cloud'
  }
}
config = File.expand_path($config_file)
if File.exist?(config)
  user_config = YAML.load(IO.read(config))
  if user_config.is_a? Hash
    settings = defaults.deep_merge(user_config)
    # unless defaults.compare_keys(user_config)
    #   warn "Adding new keys to #{config}"
    #   File.open(config, 'w') do |f|
    #     f.puts YAML.dump(settings)
    #   end
    # end
  else
    warn "Invalid user configuration in #{config}"
    settings = defaults
  end
else
  settings = defaults
  yaml = YAML.dump(settings)
  FileUtils.mkdir_p(File.dirname(config)) unless File.directory?(File.dirname(config))
  File.open(config, 'w') do |f|
    f.puts yaml
  end
  warn "Configuration file written to #{config}"
end

$ui_strings = settings[:ui_strings]

# defaults
options = {
  averages: [1, 5, 15],
  background: false,
  color_indicator: 1,
  mem_free: false,
  percent: false,
  prefix: '',
  spacer: nil,
  split_cpu: false,
  suffix: '',
  top: false,
  truncate: 0,
  width: settings[:bar_width]
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: #{File.basename(__FILE__)} [options] [subcommand]"
  opts.separator 'Subcommands (* = default):'
  opts.separator '    cpu*'
  opts.separator '    memory'
  opts.separator '    ip [lan|wan*]'
  opts.separator '    network [interface|speed|location*]'
  opts.separator '    doing'
  opts.separator '    refresh [key:path ...]'
  opts.separator '    trigger [key:path ...]'
  opts.separator '    add [touch|menu|streamdeck] COMMAND'
  opts.separator '    uuids [install]'
  opts.separator ''
  opts.separator "To add widgets automatically, use: #{File.basename(__FILE__)} add [touch|menu|streamdeck] [command]"
  opts.separator '    where command is one of cpu, memory, lan, wan, interface, audio, location, doing, or bunch'
  opts.separator 'To quickly get widget UUIDs for use with the refresh command, select a widget or group in'
  opts.separator "    BetterTouchTool configuration, press ⌘C to copy it, then run: #{File.basename(__FILE__)} uuids"
  opts.separator "    (run `#{File.basename(__FILE__)} uuids install` to have them added to your config automatically.)"
  opts.separator ''
  opts.separator 'Options:'

  opts.on('-a', '--averages AVERAGES',
          'Comma separated list of CPU averages to display (1, 5, 15), default all') do |c|
    options[:averages] = c.split(/,/).map(&:to_i)
  end

  opts.on('-c', '--color_from AVERAGE',
          'Which CPU average to get level indicator color from (1, 5, 15), default 1') do |c|
    options[:color_indicator] = c.to_i
  end

  opts.on('-f', '--free', 'Display free memory instead of used memory') do
    options[:mem_free] = true
  end

  opts.on('-i', '--indicator', 'Include background color indicating severity or activity') do
    options[:background] = true
  end

  opts.on('-p', '--percent', 'Display percentages instead of bar graph') do
    options[:percent] = true
  end

  opts.on('--split_cpu', 'Display CPU graph on multiple lines (ignores --averages)') do
    options[:split_cpu] = true
  end

  opts.on('--prefix PREFIX', 'Include text before output, [PREFIX][CHART/%]') do |c|
    options[:prefix] = c
  end

  opts.on('--suffix SUFFIX', 'Include text after output, [CHART/%][SUFFIX]') do |c|
    options[:suffix] = c
  end

  opts.on('-w', '--width WIDTH', 'Width of bar graph (default 8)') do |c|
    options[:width] = c.to_i
  end

  opts.on('--empty CHARACTER', 'Include character when output is empty to prevent widget from collapsing') do |c|
    options[:spacer] = c
  end

  opts.on('--raw', 'Output raw text without BetterTouchTool formatting') do
    settings[:raw] = true
  end

  opts.on('--top', 'If CPU is maxed, include top process in output') do
    options[:top] = true
  end

  opts.on('--truncate LENGTH', 'Truncate output') do |c|
    options[:truncate] = c.to_i
  end

  opts.on('-h', '--help', 'Display this screen') do
    puts opts
    exit
  end
end

parser.parse!

# Utility methods
def app_running?(app)
  not `ps ax|grep -i "#{app}.app"|grep -v grep`.empty?
end

def ui(key)
  key = key.to_sym unless key.is_a? Symbol
  $ui_strings[key]
end

def exit_empty(raw = false)
  print raw ? '' : '{}'
  Process.exit 0
end

def btt_action(action)
  warn action
  `/usr/bin/osascript -e 'tell app "BetterTouchTool" to #{action}'`
end

def osascript(script)
  `/usr/bin/osascript -e #{Shellwords.escape(script)}`
end

def match_key(table, key)
  result = [key, nil]
  table.each do |k, v|
    next unless k =~ /^#{key.downcase}/

    result = [k, v]
    break
  end
  result
end

def available_commands(table, key = nil)
  type = key.nil? ? '' : "#{key} "
  puts "Available #{type}commands:"
  output = []
  table.each do |k, v|
    if v.key?(:title)
      output << ["#{type}#{k}", v[:title]]
    else
      v.each { |subk, subv| output << ["#{type}#{k} #{subk}", subv[:title]] }
    end
  end
  max = output.max {|a,b| a[0].length <=> b[0].length }
  pad = max[0].length + 2
  output.each do |line|
    cmd = line[0] + " " + ("." * (pad - line[0].length))
    puts "#{cmd} #{line[1]}"
  end
end

def data_for_command(cmd)
  table = {}
  table['battery'] = {
    'source' => { title: 'Power Source', command: 'battery source', fontsize: 10, monospace: 1 },
    'bar' => { title: 'Battery Bar', command: 'battery', fontsize: 10, monospace: 1 },
    'percent' => { title: 'Battery Percent', command: 'battery -p', fontsize: 15 }
  }
  table['cpu'] = {
    'bar' => { title: 'CPU Bar', command: 'cpu -c 1 --top -i', fontsize: 10, monospace: 1 },
    'double' => { title: 'CPU Split Bar', command: 'cpu -c 1 --top -i --split_cpu', fontsize: 8, monospace: 1,
                  baseline: -4 },
    'percent' => { title: 'CPU Percent, 1m avg', command: 'cpu -c 1 --top -i -p -a 1', fontsize: 15 }
  }
  table['memory'] = {
    'bar': { title: 'Memory', command: 'mem -i', fontsize: 10, monospace: 1 },
    'percent': { title: 'Memory', command: 'mem -ip', fontsize: 10, monospace: 1 }
  }
  table['ip'] = {
    'lan' => { title: 'LAN IP', command: 'ip lan' },
    'wan' => { title: 'WAN IP', command: 'ip wan' }
  }
  table['network'] = {
    'location' => { title: 'Network Location', command: 'network location' },
    'interface' => { title: 'Network Interface', command: 'network interface' },
    'speed' => {
      'up' => { title: 'Internet Upload Speed', command: 'network speed up' },
      'down' => { title: 'Internet Download Speed', command: 'network speed down' },
      'both' => { title: 'Internet Speed', command: 'network speed both' }
    }
  }
  table['doing'] = {
    title: 'Doing',
    command: 'doing --truncate 45 --prefix " " -i --empty "…"',
    sfsymbol: 'checkmark.circle'
  }
  table['zoom'] = {
    'mic' => { title: 'Zoom Mute', icon_only: true, command: 'zoom stat mute', action: 'zoom toggle mute' },
    'video' => { title: 'Zoom Video', icon_only: true, command: 'zoom stat video', action: 'zoom toggle video' },
    'leave' => { title: 'Zoom Leave', icon_only: true, command: 'zoom stat leave', action: 'zoom leave' },
    'share' => { title: 'Zoom Share', icon_only: true, command: 'zoom stat share', action: 'zoom toggle share' },
    'record' => { title: 'Zoom Record', icon_only: true, command: 'zoom stat record', action: 'zoom toggle record' }
  }
  table['close'] = {
    title: 'Touch Bar Close Button'
  }
  table['bunch'] = {
    title: 'Bunch Group'
  }

  if cmd.nil? || cmd.empty?
    available_commands(table)
    Process.exit 0
  end
  key = ''
  data = table.dup
  cmd = cmd.split(' ') if cmd.is_a? String
  cmd.each do |c|
    key_name, data = match_key(data, c)
    key += key_name.to_s
  end

  unless data.key?(:title)
    available_commands(data, key)
    Process.exit 1
  end

  warn "Button type not found: #{cmd.join(' ')}" if data.nil?

  data
end

def add_touch_bar_button(specs)
  specs[:fontsize] ||= 15
  specs[:sfsymbol] ||= ''
  specs[:icon_only] ||= false
  data = {
    'BTTWidgetName' => specs[:title],
    'BTTTriggerType' => 642,
    'BTTTriggerTypeDescription' => 'Shell Script / Task Widget',
    'BTTTriggerClass' => 'BTTTriggerTypeTouchBar',
    'BTTShellScriptWidgetGestureConfig' => '/bin/sh:::-c:::-:::',
    'BTTEnabled2' => 1,
    'BTTEnabled' => 1,
    'BTTMergeIntoTouchBarGroups' => 0,
    'BTTTriggerConfig' => {
      'BTTTouchBarItemSFSymbolWeight' => 1,
      'BTTTouchBarItemIconType' => 2,
      'BTTTouchBarItemSFSymbolDefaultIcon' => specs[:sfsymbol],
      'BTTTouchBarButtonFontSize' => specs[:fontsize].to_i,
      'BTTTouchBarScriptUpdateInterval' => 5,
      'BTTTouchBarShellScriptString' => "#{__FILE__} #{specs[:command]}",
      'BTTTouchBarAppleScriptStringRunOnInit' => true,
      'BTTTouchBarButtonName' => specs[:title],
      'BTTTouchBarOnlyShowIcon' => specs[:icon_only]
    }
  }
  if specs[:action]
    action = {
      'BTTPredefinedActionType' => 206,
      'BTTPredefinedActionName' => 'Execute Shell Script / Task',
      'BTTShellTaskActionScript' => "#{__FILE__} #{specs[:action]}",
      'BTTShellTaskActionConfig' => '/bin/bash:::-c:::-:::'
    }
    data = data.merge(action)
  end
  script = data.to_btt_as('add_new_trigger')
  osascript(script)
  warn "Added #{specs[:title]} Touch Bar widget"
end

def add_stream_deck_button(specs)
  specs[:fontsize] ||= 15
  specs[:sfsymbol] ||= ''
  specs[:icon_only] ||= false
  data = {
    'BTTStreamDeckButtonName' => specs[:title],
    'BTTTriggerType' => 730,
    'BTTTriggerTypeDescription' => 'Shell Script / Task Widget',
    'BTTTriggerClass' => 'BTTTriggerTypeStreamDeck',
    'BTTShellScriptWidgetGestureConfig' => '/bin/sh:::-c:::-:::',
    'BTTEnabled2' => 1,
    'BTTEnabled' => 1,
    'BTTTriggerConfig' => {
      'BTTStreamDeckImageHeight' => 50,
      'BTTStreamDeckCornerRadius' => 12,
      'BTTStreamDeckTextOffsetY' => 0,
      'BTTStreamDeckBackgroundColor' => '170.000005, 170.000005, 170.000005, 255.000000',
      'BTTStreamDeckSFSymbolStyle' => 1,
      'BTTScriptSettings' => {
        'BTTShellScriptString' => "#{__FILE__} #{specs[:command]}",
        'BTTShellScriptConfig' => '\/bin\/bash:::-c:::-:::',
        'BTTShellScriptEnvironmentVars' => ''
      },
      'BTTScriptUpdateInterval' => 5,
      'BTTStreamDeckIconColor1' => '255, 255, 255, 255',
      'BTTStreamDeckAlternateImageHeight' => 50,
      # 'BTTStreamDeckFixedIdentifier' => "btt-#{specs[:command].gsub(/ /, '-')}",
      'BTTStreamDeckDisplayOrder' => 0,
      'BTTStreamDeckMainTab' => 1,
      'BTTStreamDeckAlternateIconColor1' => '255, 255, 255, 255',
      'BTTStreamDeckIconColor2' => '255, 255, 255, 255',
      'BTTStreamDeckAlternateIconColor2' => '255, 255, 255, 255',
      'BTTStreamDeckIconType' => 2,
      'BTTStreamDeckAlternateBackgroundColor' => '255.000000, 224.000002, 97.000002, 255.000000',
      'BTTStreamDeckAlternateIconColor3' => '255, 255, 255, 255',
      'BTTStreamDeckAlternateCornerRadius' => 12,
      'BTTStreamDeckSFSymbolName' => specs[:sfsymbol].to_s,
      'BTTStreamDeckUseFixedRowCol' => 1
    }
  }
  if specs[:action]
    action = {
      'BTTPredefinedActionType' => 206,
      'BTTPredefinedActionName' => 'Execute Shell Script / Task',
      'BTTShellTaskActionScript' => "#{__FILE__} #{specs[:action]}",
      'BTTShellTaskActionConfig' => '/bin/bash:::-c:::-:::'
    }
    data = data.merge(action)
  end
  script = data.to_btt_as('add_new_trigger')
  osascript(script)
  warn "Added #{specs[:title]} Touch Bar widget"
end

def add_menu_bar_button(specs)
  specs[:fontsize] ||= 15
  specs[:monospace] ||= 0
  specs[:sfsymbol] ||= ''
  specs[:baseline] ||= 0
  data = {
    'BTTGestureNotes' => specs[:title],
    'BTTTriggerType' => 681,
    'BTTTriggerTypeDescription' => "Menubar Item: #{specs[:title]}",
    'BTTTriggerClass' => 'BTTTriggerTypeOtherTriggers',
    'BTTAdditionalConfiguration' => '\/bin\/bash:::-c:::-:::',
    'BTTEnabled2' => 1,
    'BTTEnabled' => 1,
    'BTTTriggerConfig' => {
      'BTTTouchBarItemSFSymbolWeight' => 1,
      'BTTTouchBarItemIconType' => 2,
      'BTTTouchBarItemSFSymbolDefaultIcon' => (specs[:sfsymbol]).to_s,
      'BTTTouchBarScriptUpdateInterval' => 5,
      'BTTTouchBarButtonFontSize' => specs[:fontsize].to_i,
      'BTTTouchBarButtonMonoSpace' => specs[:monospace].to_i,
      'BTTTouchBarAppleScriptStringRunOnInit' => true,
      'BTTTouchBarShellScriptString' => "#{__FILE__} #{specs[:command]}",
      'BTTTouchBarButtonBaselineOffset' => specs[:baseline].to_i
    }
  }
  script = data.to_btt_as('add_new_trigger')
  osascript(script)
  warn "Added #{specs[:title]} menu bar widget"
end

def add_touch_bar_close_button
  json = JSON.parse(DATA.read)

  raise 'Error reading preset data' if json.nil? || !json.key?('close_button')

  button = json['close_button']
  script = button.to_btt_as('add_new_trigger')
  osascript(script)
  warn 'Added Touch Bar button to close current group.'
end

def add_named_trigger(specs)
  data = {
    'BTTTriggerType' => 643,
    'BTTTriggerTypeDescription' => "Named Trigger: #{specs[:title]}",
    'BTTTriggerClass' => 'BTTTriggerTypeOtherTriggers',
    'BTTPredefinedActionType' => 206,
    'BTTPredefinedActionName' => 'Execute Shell Script / Task',
    'BTTShellTaskActionScript' => "#{__FILE__} #{specs[:action]}",
    'BTTShellTaskActionConfig' => '/bin/bash:::-c:::-:::',
    'BTTTriggerName' => specs[:title],
    'BTTEnabled2' => 1,
    'BTTEnabled' => 1
  }
  script = data.to_btt_as('add_new_trigger')
  osascript(script)
  warn "Added #{specs[:title]} named trigger"
end

def bunch_status_script
  stats_dir = File.dirname(__FILE__)
  status_script = File.join(stats_dir, 'bunch_status_check.rb')
  unless File.exist?(status_script)
    script =<<~'EOSCRIPT'
      #!/usr/bin/env ruby
      # frozen_string_literal: true

      require 'json'

      # Usage in a BetterTouchTool Shell Script Widget
      #
      # For a Stream Deck widget:
      # /path/to/bunch_status.rb sd title "Bunch Name"
      #
      # For a Touch Bar widget:
      # /path/to/bunch_status.rb "Bunch Name"

      # Define open and closed background colors
      open_color = '165,218,120,255'
      closed_color = '95,106,129,255'

      # To return Stream Deck button background, use "sd" as the first argument

      if ARGV[0] =~ /(sd|stream(deck)?)/i
        streamdeck = true
        ARGV.shift
      end

      # If the next argument is "title", text with the Bunch name
      # will be returned in addition to the background color. If
      # not, only a background color is returned.

      if ARGV[0] =~ /title/
        title = true
        ARGV.shift
      end

      bunch = `ps ax | grep -v grep | grep -c 'Bunch Beta'`.strip.to_i == 1 ? 'Bunch Beta' : 'Bunch'

      warn "Targeting #{bunch}"

      open_bunches = `/usr/bin/osascript -e 'tell app "#{bunch}" to list open bunches'`.strip.downcase.split(/, /)
      bunch = ARGV.join(' ').strip.downcase

      color = open_bunches.include?(bunch.downcase) ? open_color : closed_color

      if streamdeck
        print "{ \"text\":\"#{title ? bunch : ''}\",\"BTTStreamDeckBackgroundColor\": \"#{color}\"}"
      else
        print "{\"background_color\":\"#{color}\"}"
      end
    EOSCRIPT
    File.open(status_script, 'w') do |f|
      f.puts script
      warn "Created #{status_script}"
    end
  end
  unless File.executable?(status_script)
    File.chmod(0777, status_script)
    warn "Made #{status_script} executable"
  end
  status_script
end

def bunch_app_name
  beta = File.exist?('/Applications/Bunch Beta.app')
  release = File.exist?('/Applications/Bunch.app')
  if beta && !release
    'Bunch Beta'
  else
    'Bunch'
  end
end

def add_touch_bar_bunch_group
  status_script = bunch_status_script
  bunch_app = bunch_app_name
  json = JSON.parse(DATA.read)['touchbar']

  raise "Error reading preset data" if json.nil? || !json.key?('bunch_group')

  group = json['bunch_group']
  close_button = json['close_button']

  group['BTTAdditionalActions'].push(close_button)

  bunches = osascript(%(tell application "#{bunch_app}" to list bunches)).strip.split(/, /)
  raise "Error retrieving Bunch list, is Bunch.app installed and configured?" if bunches.empty?

  bunches.each do |bunch|
    data = {
      'BTTWidgetName' => bunch.to_s,
      'BTTTriggerType' => 642,
      'BTTTriggerClass' => 'BTTTriggerTypeTouchBar',
      'BTTPredefinedActionType' => 206,
      'BTTShellTaskActionScript' => "open 'x-bunch://toggle/?bunch=#{bunch.gsub(/ /, '%20')}'",
      'BTTShellTaskActionConfig' => '/bin/bash:::-c:::-:::',
      'BTTShellScriptWidgetGestureConfig' => '/bin/bash:::-c:::-:::',
      'BTTEnabled2' => 1,
      'BTTTriggerConfig' => {
        'BTTTouchBarShellScriptString' => %(#{status_script} "#{bunch}"),
        'BTTTouchBarAppleScriptStringRunOnInit' => true,
        'BTTTouchBarScriptUpdateInterval' => 0,
        'BTTTouchBarButtonName' => bunch.to_s
      }
    }
    group['BTTAdditionalActions'].push(data)
  end
  script = group.to_btt_as('add_new_trigger')
  osascript(script)
  warn "Added Bunch group to Touch Bar with #{bunches.count} bunches."
  warn "To complete the setup, right click the new group in BetterTouchTool and select 'Copy',
    then run `#{File.basename(__FILE__)} uuids` while the group data is still in your clipboard.
    The script will output a configuration block you can add to your configuration in #{File.expand_path($config_file)}.
    This can then be used to refresh the widget states without polling. See <http://ckyp.us/jcBxaM> for more info."
end

def add_stream_deck_bunch_group
  status_script = bunch_status_script
  bunch_app = bunch_app_name
  group = JSON.parse(DATA.read)['streamdeck']

  raise "Error reading preset data" if group.nil?

  bunches = osascript(%(tell application "#{bunch_app}" to list bunches)).strip.split(/, /)
  raise "Error retrieving Bunch list, is Bunch.app installed and configured?" if bunches.empty?

  bunches.each do |bunch|
    data = {
      'BTTStreamDeckButtonName' => bunch.to_s,
      'BTTTriggerType' => 730,
      'BTTTriggerClass' => 'BTTTriggerTypeStreamDeck',
      'BTTPredefinedActionType' => 206,
      'BTTShellTaskActionScript' => "open 'x-bunch://toggle/?bunch=#{bunch.gsub(/ /, '%20')}'",
      'BTTShellTaskActionConfig' => '/bin/bash:::-c:::-:::',
      'BTTAdditionalConfiguration' => '/bin/bash:::-c:::-:::',
      'BTTEnabled' => 1,
      'BTTEnabled2' => 1,
      'BTTOrder' => 0,
      'BTTDisplayOrder' => 0,
      'BTTMergeIntoTouchBarGroups' => 0,
      'BTTRepeatDelay' => 0,
      'BTTTriggerConfig' => {
        'BTTStreamDeckImageHeight' => 46,
        'BTTStreamDeckCornerRadius' => 12,
        'BTTStreamDeckBackgroundColor' => '127.500000, 127.500000, 127.500000, 255.000000',
        'BTTStreamDeckSFSymbolStyle' => 1,
        'BTTTouchBarAppleScriptStringRunOnInit' => true,
        'BTTScriptSettings' => {
          'BTTShellScriptString' =>  %(#{status_script} sd title "#{bunch}"),
          'BTTShellScriptConfig' => '/bin/bash:::-c:::-:::',
          'BTTShellScriptEnvironmentVars' => ''
        },
        'BTTScriptUpdateInterval' => 30,
        'BTTStreamDeckIconType' => 2,
        'BTTTouchBarScriptUpdateInterval' => 0,
        'BTTStreamDeckAlternateImageHeight' => 50,
        'BTTStreamDeckIconColor1' => '255, 255, 255, 255',
        'BTTStreamDeckMainTab' => 3,
        'BTTStreamDeckAlternateIconColor1' => '255, 255, 255, 255',
        'BTTStreamDeckDisplayOrder' => 0,
        'BTTStreamDeckIconColor2' => '255, 255, 255, 255',
        'BTTStreamDeckAlternateIconColor2' => '255, 255, 255, 255',
        'BTTStreamDeckAttributedTitle' => 'cnRmZAAAAAADAAAAAgAAAAcAAABUWFQucnRmAQAAAC6VAQAAKwAAAAEAAACNAQAAe1xydGYxXGFuc2lcYW5zaWNwZzEyNTJcY29jb2FydGYyNjM5Clxjb2NvYXRleHRzY2FsaW5nMFxjb2NvYXBsYXRmb3JtMHtcZm9udHRibFxmMFxmbmlsXGZjaGFyc2V0MCBBdmVuaXJOZXh0LVJlZ3VsYXI7fQp7XGNvbG9ydGJsO1xyZWQyNTVcZ3JlZW4yNTVcYmx1ZTI1NTtccmVkMjU1XGdyZWVuMjU1XGJsdWUyNTU7fQp7XCpcZXhwYW5kZWRjb2xvcnRibDs7XGNzZ2VuZXJpY3JnYlxjMTAwMDAwXGMxMDAwMDBcYzEwMDAwMDt9ClxwYXJkXHR4NTYwXHR4MTEyMFx0eDE2ODBcdHgyMjQwXHR4MjgwMFx0eDMzNjBcdHgzOTIwXHR4NDQ4MFx0eDUwNDBcdHg1NjAwXHR4NjE2MFx0eDY3MjBccGFyZGlybmF0dXJhbFxxY1xwYXJ0aWdodGVuZmFjdG9yMAoKXGYwXGZzMzYgXGNmMiBTaGVsbFwKU2NyaXB0fQEAAAAjAAAAAQAAAAcAAABUWFQucnRmEAAAAIinwWK2AQAAAAAAAAAAAAA=',
        'BTTStreamDeckAlternateIconColor3' => '255, 255, 255, 255',
        'BTTStreamDeckAlternateBackgroundColor' => '255.000000, 224.000002, 97.000002, 255.000000',
        'BTTStreamDeckAlternateCornerRadius' => 12,
        'BTTScriptAlwaysRunOnInit' => 1,
        'BTTStreamDeckIconColor3' => '255, 255, 255, 255',
        'BTTTouchBarShellScriptString' => %(#{status_script} sd title "#{bunch}"),
        'BTTStreamDeckAppearanceTab' => 1,
        'BTTStreamDeckUseFixedRowCol' => 0
      }
    }
    group[0]['BTTAdditionalActions'].push(data)
  end
  script = group.to_btt_as('add_new_trigger')
  osascript(script)
  warn "Added Bunch group to Stream Deck with #{bunches.count} bunches."
  warn "To complete the setup, right click the new group in BetterTouchTool and select 'Copy',
    then run `#{File.basename(__FILE__)} uuids` while the group data is still in your clipboard.
    The script will output a configuration block you can add to your configuration in #{File.expand_path($config_file)}.
    This can then be used to refresh the widget states without polling. See <http://ckyp.us/jcBxaM> for more info."
end

def uuids_from_clipboard(install = false)
  input = `pbpaste`.strip.force_encoding('utf-8')

  begin
    data = JSON.parse(input)
  rescue
    warn 'Invalid clipboard data, please copy a widget from BetterTouchTool before running' if data.nil?
    Process.exit 1
  end

  results = {}
  data.each do |trigger|
    case trigger['BTTTriggerType']
    when 630
      widgets = {}
      if trigger.key?('BTTTouchBarButtonName')
        group_name = trigger['BTTTouchBarButtonName']
      else
        group_name = trigger['BTTStreamDeckButtonName']
      end
      trigger['BTTAdditionalActions'].each do |button|
        next unless button['BTTTriggerType'] == 642 || button['BTTTriggerType'] == 730

        if button.key?('BTTWidgetName')
          widgets[button['BTTWidgetName']] = button['BTTUUID']
        else
          widgets[button['BTTStreamDeckButtonName']] = button['BTTUUID']
        end
      end
      results[group_name] = widgets
    when 732
      results[trigger['BTTStreamDeckButtonName']] = trigger['BTTUUID']
    when 730
      results[trigger['BTTStreamDeckButtonName']] = trigger['BTTUUID']
    else
      results[trigger['BTTWidgetName']] = trigger['BTTUUID']
    end
  end

  if (install)
    file = File.expand_path($config_file)
    config = YAML.load(IO.read(file))
    refresh = config[:refresh] || {}
    refresh = refresh.merge(results)
    config[:refresh] = refresh
    File.open(file, 'w') do |f|
      f.puts YAML.dump(config)
    end
    warn "New keys added to #{file} for use with the `refresh` command."
  else
    warn "Add the following to #{File.expand_path($config_file)} for use with the `refresh` command:"
    puts YAML.dump({refresh: results})
  end
  Process.exit 0
end

# Status methods

def audio_settings
  data = `osascript -e 'get volume settings'`
  settings = data.scan(/(?<=^| )([\w ]+):(\S+)(?=,|$)/)

  status = {}
  settings.each { |s| status[s[0].gsub(/ /, '_').to_sym] = s[1] }
  status.transform_values! do |v|
    case v
    when /true/
      true
    when /false/
      false
    when /\d+/
      v.to_i
    end
  end
  status
end

def cpu(options, loads, cores)
  unit = (options[:width].to_f / 100)
  chart_arr = Array.new(options[:width], '░')
  fills = %w[▒ ▓ █].reverse.slice(0, loads.length).reverse
  loads.reverse.each_with_index do |ld, idx|
    this_load = (ld.to_f / cores)
    this_load = 100 if this_load > 100
    chart_arr.fill(fills[idx], 0, (unit * this_load).to_i)
  end

  chart_arr.join('')
end

def split_cpu(options, loads, cores)
  unit = (options[:width].to_f / 100)
  chart1 = Array.new(options[:width], '░')
  this_load = (loads[0].to_f / cores)
  this_load = 100 if this_load > 100
  chart1.fill('█', 0, (unit * this_load).to_i)

  avg5_load = ((loads[1].to_f / cores) * unit).to_i
  avg5_load = 100 if avg5_load > 100
  avg15_load = ((loads[2].to_f / cores) * unit).to_i
  avg15_load = 100 if avg15_load > 100
  chart2 = []
  options[:width].times do |i|
    if i <= avg5_load && i <= avg15_load
      chart2.push('▇')
    elsif i <= avg5_load
      chart2.push('▀')
    elsif i <= avg15_load
      chart2.push('▄')
    else
      chart2.push('░')
    end
  end
  # Attempt to indent second line based on title width and font size difference
  indent = ' ' * (options[:prefix].length * 2.4).ceil
  %(#{chart1.join('')}\\n#{indent}#{chart2.join('')})
end

def zoom_status
  result = `osascript <<'APPLESCRIPT'
    set zoomStatus to false
    set callStatus to false
    set micStatus to false
    set videoStatus to false
    set shareStatus to false
    set recordStatus to false
    tell application "System Events"
      if exists (window 1 of process "zoom.us") then
        set zoomStatus to true

        tell application process "zoom.us"
          if exists (menu bar item "#{ui(:meeting_menu)}" of menu bar 1) then
            set callStatus to true
            if exists (menu item "#{ui(:mute_audio)}" of menu 1 of menu bar item "#{ui(:meeting_menu)}" of menu bar 1) then
              set micStatus to true
            else
              set micStatus to false
            end if
            if exists (menu item "#{ui(:start_video)}" of menu 1 of menu bar item "#{ui(:meeting_menu)}" of menu bar 1) then
              set videoStatus to false
            else
              set videoStatus to true
            end if
            if exists (menu item "#{ui(:start_share)}" of menu 1 of menu bar item "#{ui(:meeting_menu)}" of menu bar 1) then
              set shareStatus to false
            else
              set shareStatus to true
            end if
            if exists (menu item "#{ui(:record_to_cloud)}" of menu 1 of menu bar item "#{ui(:meeting_menu)}" of menu bar 1) then
              set recordStatus to false
            else if exists (menu item "#{ui(:record)}" of menu 1 of menu bar item "#{ui(:meeting_menu)}" of menu bar 1) then
              set recordStatus to false
            else
              set recordStatus to true
            end if
          end if
        end tell
      end if
    end tell

    return {zoom:zoomStatus, inMeeting:callStatus, micOn:micStatus, videoOn:videoStatus, isSharing:shareStatus, isRecording:recordStatus}
  APPLESCRIPT`.strip.split(/, /)
  status = {}
  result.each do |stat|
    parts = stat.split(/:/)
    status[parts[0].to_sym] = parts[1] == 'true' ? true : false
  end
  status
end

class ::String
  def to_rx
    downcase.gsub(/ /, '').split(//).join('.{0,3}')
  end
end

# Actions
def find_keypath(arg, settings)
  keypath = arg.split(/[:.]/)
  new_keypath = []

  while keypath.length.positive?
    key = keypath[0]
    break if settings.is_a? String

    if settings.respond_to?(:key?)
      new_setting = nil
      settings.each_key do |k|
        if k.gsub(/ /, '') =~ /#{key.to_rx}/i
          new_setting = settings[k]
          new_keypath.push(k)
          break
        end
      end
      if new_setting
        settings = new_setting
      else
        warn %(Config does not contain key path "#{arg}")
        Process.exit 0
      end
    else
      warn %(Config does not contain key path "#{arg}")
      Process.exit 0
    end

    keypath.shift
  end

  [settings, new_keypath.join(':')]
end

def trigger_key(settings, args)
  raise 'Trigger requires a keypath' if args.length.zero?

  args.each do |arg|
    settings, keypath = find_keypath(arg, settings)

    trigger_widget(keypath, settings)
  end
end

def trigger_widget(key, uuid)
  raise "Trigger only works with a single widget" unless uuid.is_a? String

  warn "Triggering #{key}: #{uuid}"
  btt_action(%(execute_assigned_actions_for_trigger "#{uuid}"))
end

def refresh_key(settings, args)
  if args.length.zero?
    warn '--- Refreshing all widgets'
    settings.each { |k, v| refresh_widget(k, v) }
  else
    args.each do |arg|
      settings, keypath = find_keypath(arg, settings)

      refresh_widget(keypath, settings)
    end
  end
end

def refresh_widget(key, settings)
  if settings.is_a? Hash
    warn "--- Refreshing all widgets in #{key}"
    settings.each do |k, val|
      refresh_widget("#{key}:#{k}", val)
    end
  elsif settings.is_a? Array
    settings.each do |uuid|
      warn "Refreshing #{key}: #{uuid}"
      btt_action(%(refresh_widget "#{uuid}"))
    end
  else
    warn "Refreshing #{key}: #{settings}"
    btt_action(%(refresh_widget "#{settings}"))
  end
end

def zoom_leave
  `osascript <<'APPLESCRIPT'
  tell application "zoom.us" to activate
  tell application "System Events" to tell application process "zoom.us"
      if exists (menu bar item "#{ui(:window_menu)}" of menu bar 1) then
        click (menu item "#{ui(:close)}" of menu 1 of menu bar item "#{ui(:window_menu)}" of menu bar 1)
        delay 0.5
        click button 1 of window 1
      end if
  end tell
  APPLESCRIPT`
end

def zoom_toggle(type)
  case type
  when /^(mut|mic)/i
    menu_off = ui(:unmute_audio)
    menu_on = ui(:mute_audio)
  when /^(vid|cam)/i
    menu_off = ui(:stop_video)
    menu_on = ui(:start_video)
  when /^share/i
    menu_off = ui(:stop_share)
    menu_on = ui(:start_share)
  when /^rec/
    menu_off = ui(:stop_record)
    menu_on = ui(:record)
  when /^cloud/
    menu_off = ui(:stop_record)
    menu_on = ui(:record_to_cloud)
  else
    raise "Invalid toggle type: #{type}"
  end

  `osascript <<'APPLESCRIPT'
  tell application "System Events" to tell application process "zoom.us"
    if exists (menu item "#{menu_off}" of menu 1 of menu bar item "#{ui(:meeting_menu)}" of menu bar 1) then
      click (menu item "#{menu_off}" of menu 1 of menu bar item "#{ui(:meeting_menu)}" of menu bar 1)
    else
      click (menu item "#{menu_on}" of menu 1 of menu bar item "#{ui(:meeting_menu)}" of menu bar 1)
    end if
  end tell
  APPLESCRIPT`
end

def mute_audio
  `osascript -e "set volume with output muted"`
end

def unmute_audio
  `osascript -e "set volume without output muted"`
end

def toggle_mute
  status = audio_settings
  if status[:output_muted]
    unmute_audio
  else
    mute_audio
  end
end

def volume_up(inc)
  `osascript -e "set volume output volume (output volume of (get volume settings) + #{inc.to_i})"`
end

def volume_down(inc)
  `osascript -e "set volume output volume (output volume of (get volume settings) - #{inc.to_i})"`
end

def speed_test
  res = `networkQuality`

  up = res.match(/Up(?:load|link) capacity: (\d+\.\d+) Mbps/)[1].to_i
  down = res.match(/Down(?:load|link) capacity: (\d+\.\d+) Mbps/)[1].to_i

  { up: up, down: down }
end

color = ''
font_color = ''
chart = ''

case ARGV[0]
when /^uuid/
  ARGV.shift
  uuids_from_clipboard(ARGV[0] && ARGV[0] =~ /^install/)
when /^stat(us)?/
  ARGV.shift

  if ARGV[0] =~ /c(lear)?/
    file = File.expand_path(ARGV[1])
    if File.exist?(file)
      File.open(file, 'w') {|f| f.puts ''}
      Process.exit 0
    else
      warn "File #{file} does not exist"
      Process.exit 1
    end
  elsif ARGV[0] =~ /^g(et)?$/
    file = File.expand_path(ARGV[1])
    if File.exist?(file)
      out = IO.read(file)
      print out.strip
      Process.exit 0
    else
      warn "File #{file} does not exist"
      Process.exit 1
    end
  elsif ARGV[0] =~ /^s(et)?$/
    ARGV.shift

    file = File.expand_path(ARGV[0])
    unless File.exist?(file)
      FileUtils.touch(file)
    end
    ARGV.shift

    params = []

    ARGV.each do |i|
      arg = i.strip

      case arg
      when /^i(con)?:/
        icon = arg.sub(/^i(con)?:/, '')
        params.push(%(\"sf_symbol_name\":\"#{icon}\"))
      when /^t(ext|itle)?:/
        text = arg.sub(/^t(ext|itle)?:/, '')
        params.push(%(\"text\":\"#{text}\"))
      when /^(c(olor)?|f(g|oreground)?):/
        color = arg.sub(/^(c(olor)?|f(g|oreground)?):/, '')
        params.push(%(\"font_color\":\"#{color.btt_color}\"))
      when /^b(g|ackground)?:/
        background = arg.sub(/^b(g|ackground)?:/, '')
        params.push(%(\"background_color\":\"#{background.btt_color}\"))
        params.push(%(\"BTTStreamDeckBackgroundColor\":\"#{background.btt_color}\"))
      end
    end

    out = %({#{params.join(',')}})
    File.open(file, 'w') do |f|
      f.puts out
    end
    Process.exit 0
  else
    warn "Invalid command, must be get FILE or set FILE ARGS"
    Process.exit 1
  end
when /^add/
  ARGV.shift
  unless ARGV[0] =~ /^(touch|menu|stream|sd)/i
    warn "First argument must be 'touch', 'menu', or 'streamdeck'"
    warn "Example: #{File.basename(__FILE__)} add touch ip lan"
    data_for_command(nil)
    Process.exit 1
  end
  type = case ARGV[0]
         when /^touch/i
           'touchbar'
         when /^s(d|tream)/i
           'streamdeck'
         else
           'menubar'
         end
  ARGV.shift

  if ARGV[0] =~ /^(close|bunch)/i
    if type =~ /(touchbar|streamdeck)/i
      case ARGV[0]
      when /^close/i
        add_touch_bar_close_button
      when /^bunch/i
        type =~ /^s[td]/ ? add_stream_deck_bunch_group : add_touch_bar_bunch_group
      end
      warn 'You may need to restart BetterTouchTool to see the button in your configuration.'
      Process.exit 0
    else
      warn '#{ARGV[0]} is only available for Touch Bar or Stream Deck'
      Process.exit 1
    end
  end

  if ARGV[0] =~ /^stat(us)?$/i
    file = ARGV[1]
    unless File.exist?(File.expand_path(file))
      FileUtils.touch File.expand_path(file)
    end

    data = { title: "Status Report: #{File.basename(file)}", command: %(status get "#{File.expand_path(file)}")}
    if type == 'touchbar'
      add_touch_bar_button(data)
    elsif type == 'streamdeck'
      add_stream_deck_button(data)
    else
      add_menu_bar_button(data)
    end

    warn 'You may need to restart BetterTouchTool to see the button in your configuration.'
    Process.exit 0
  end

  data = data_for_command(ARGV)
  Process.exit 1 if data.nil?

  if type == 'touchbar'
    add_touch_bar_button(data)
  elsif type == 'streamdeck'
    add_stream_deck_button(data)
  else
    add_menu_bar_button(data)
  end
  # puts "#{type == 'touchbar' ? 'Touch Bar' : 'Menu Bar'} widget added."
  warn 'You may need to restart BetterTouchTool to see the button in your configuration.'
  Process.exit 0
when /^refresh/
  unless settings.key?(:refresh)
    warn 'No :refresh key in config'
    warn 'Config must contain \':refresh\' section with key/value pairs'
    Process.exit 0
  end

  ARGV.shift
  warn 'No key provided' unless ARGV.length.positive?

  refresh_key(settings[:refresh], ARGV)
  Process.exit 0
when /^trig/
  unless settings.key?(:refresh)
    warn 'No :refresh key in config'
    warn 'Config must contain \':refresh\' setction with key/value pairs'
    Process.exit 0
  end

  ARGV.shift
  warn 'No key provided' unless ARGV.length.positive?

  trigger_key(settings[:refresh], ARGV)
  Process.exit 0
when /^zoom/
  ARGV.shift

  case ARGV[0]
  when /^stat/
    exit_empty(options[:raw]) unless app_running?('zoom.us')

    status = zoom_status

    exit_empty(options[:raw]) unless status[:inMeeting]

    ARGV.shift
    colors = settings[:colors][:zoom]

    case ARGV[0]
    when /^(mic|mute)/
      icon = status[:micOn] ? 'mic.fill' : 'mic.slash.fill'
      c = status[:micOn] ? colors[:on] : colors[:off]
      text = status[:micOn] ? 'Unmuted' : 'Muted'
    when /^(vid|cam)/
      icon = status[:videoOn] ? 'video.fill' : 'video.slash.fill'
      c = status[:videoOn] ? colors[:on] : colors[:off]
      text = status[:videoOn] ? 'Video On' : 'Video Off'
    when /^(shar|desk)/
      icon = status[:isSharing] ? 'rectangle.fill.on.rectangle.fill' : 'rectangle.fill.on.rectangle.fill.slash.fill'
      c = status[:isSharing] ? colors[:on] : colors[:off]
      text = status[:isSharing] ? 'Sharing' : 'Not Sharing'
    when /^rec/
      icon = status[:isRecording] ? 'record.circle.fill' : 'stop.circle'
      c = status[:isRecording] ? colors[:recording] : colors[:record]
      text = status[:isRecording] ? 'Recording' : 'Not Recording'
    when /^leave/
      exit_empty(options[:raw]) unless status[:inMeeting]
      icon = 'figure.walk.circle'
      text = 'Leave'
      c = colors[:leave]
    end

    color, font_color = [c[:bg].btt_color, c[:fg].btt_color]

    out = %({\"text\":\"#{text}\",\"BTTStreamDeckSFSymbolName\":\"#{icon}\",\"sf_symbol_name\":\"#{icon}\",\"BTTStreamDeckBackgroundColor\": \"#{color}\",\"background_color\":\"#{color}\",\"font_color\":\"#{font_color}\"})
    print out
    Process.exit 0
  when /^leave/
    zoom_leave
    Process.exit 0
  when /^t/
    # Toggle Actions mute, video, leave
    ARGV.shift
    case ARGV[0]
    when /^(rec|cloud)/
      zoom_toggle(ARGV[0] =~ /^c/ || ARGV[1] =~ /^c/ ? 'cloud' : 'record')
    when /^(mic|mute)/
      zoom_toggle('mic')
    when /^(vid|cam)/
      zoom_toggle('video')
    when /^sh/
      zoom_toggle('share')
    else
      raise "Unknown toggle: #{ARGV[0]}"
    end
    Process.exit 0
  else
    raise "Unknown zoom command: #{ARGV[0]}"
  end
when /^net/
  options[:background] = false
  chart = case ARGV[1]
          when /^s/
            res = speed_test
            text = case ARGV[2]
                   when /^u/
                     "↑#{res[:up]}Mbps"
                   when /^d/
                     "↓#{res[:down]}Mbps"
                   else
                     "↓#{res[:down]}\\n↑#{res[:up]}"
                   end
                   bg = settings[:colors][:activity][:active][:bg].btt_color
                   fg = settings[:colors][:activity][:active][:fg].btt_color
            out = %({\"text\":\"#{text}\",\"BTTStreamDeckBackgroundColor\": \"#{bg}\",\"background_color\":\"#{bg}\",\"font_color\":\"#{fg}\"})
            print out
            Process.exit 0
          when /^i/ # Interface
            osascript('tell app "System Events" to tell current location of network preferences to get name of first service whose active is true').strip
          else # Location
            osascript('tell app "System Events" to get name of current location of network preferences').strip
          end
when /^ip/
  options[:background] = false
  chart = case ARGV[1]
          when /^lan/ # LAN IP
            `ifconfig | grep "inet " | awk '{ print $2 }' | tail -n 1`.strip
          else # WAN IP
            `curl -SsL icanhazip.com`.strip
          end
when /^doing/
  ## Add in .doingrc (`doing config`)
  # views:
  #   btt:
  #     section: Currently
  #     count: 1
  #     order: desc
  #     template: "%title"
  #     tags_bool: NONE
  #     tags: done
  chart = `/usr/local/bin/doing view btt`.strip.gsub(/(\e\[[\d;]*m)/, '')
  colors = settings[:colors][:activity]
  color = chart.length.positive? ? colors[:active][:bg].btt_color : colors[:inactive][:bg].btt_color
  font_color = chart.length.positive? ? colors[:active][:fg].btt_color : colors[:inactive][:fg].btt_color
when /^batt/
  batt_info = `pmset -g batt`.strip
  source = batt_info =~ /'Battery Power'/ ? 'Battery' : 'AC'
  percent = batt_info =~ /\d+%/ ? batt_info.match(/(\d+)%/)[1].to_i : 0
  color = ''
  font_color = ''
  chart = case ARGV[1]
          when /source/
            chart = source
          else
            settings[:colors][:charge].each do |c|
              next unless percent <= c[:max]

              color = c[:bg].btt_color
              font_color = c[:fg].btt_color
              break
            end

            if options[:percent]
              "#{percent}%"
            else
              unit = (options[:width].to_f / 100)

              chart_arr = Array.new(options[:width], '░')
              chart_arr.fill('█', 0, (unit * percent).to_i)

              chart_arr.join('')
            end
          end
when /^mem/
  mem_free = `memory_pressure | tail -n 1 | awk '{ print $NF; }' | tr -d '%'`.to_i
  mem_used = 100 - mem_free
  memory = options[:mem_free] ? mem_free : mem_used

  if options[:percent]
    chart = "MEM\\n#{memory}%"
  else
    unit = (options[:width].to_f / 100)

    chart_arr = Array.new(options[:width], '░')
    chart_arr.fill('█', 0, (unit * memory).to_i)

    chart = chart_arr.join('')
  end

  color = ''
  settings[:colors][:severity].each do |c|
    next unless mem_used <= c[:max]

    font_color = c[:fg].btt_color
    color = c[:bg].btt_color
    break
  end
when /^audio/
  status = audio_settings
  colors = settings[:colors][:zoom]

  if ARGV[1] =~ /^s(?:tat(?:us)?)?$/
    ARGV.shift
    case ARGV[1]
    when /mute/
      icon = status[:output_muted] ? 'speaker.slash.fill' : 'speaker.fill'
      c = status[:output_muted] ? colors[:off] : colors[:on]
      text = status[:output_muted] ? 'Muted' : 'Unmuted'
      color, font_color = [c[:bg].btt_color, c[:fg].btt_color]
      out = %({\"text\":\"#{text}\",\"BTTStreamDeckSFSymbolName\":\"#{icon}\",\"sf_symbol_name\":\"#{icon}\",\"BTTStreamDeckBackgroundColor\": \"#{color}\",\"background_color\":\"#{color}\",\"font_color\":\"#{font_color}\"})
      print out
      Process.exit 0
    else
      color, font_color = nil
      v = ARGV[1] =~ /input/ ? status[:input_volume] : status[:output_volume]
      settings[:colors][:severity].each do |c|
        next unless v <= c[:max]

        color = c[:bg].btt_color
        font_color = c[:fg].btt_color
        break
      end
      icon = if v < 33
               'speaker.wave.1'
             elsif v >= 33 && v < 66
               'speaker.wave.2'
             else
               'speaker.wave.3'
             end

      out = %({\"text\":\"#{v}%\",\"BTTStreamDeckSFSymbolName\":\"#{icon}\",\"sf_symbol_name\":\"#{icon}\",\"BTTStreamDeckBackgroundColor\": \"#{color}\",\"background_color\":\"#{color}\",\"font_color\":\"#{font_color}\"})
      print out
      Process.exit 0
    end
  else
    case ARGV[1]
    when /mute/
      case ARGV[2]
      when /on/
        mute_audio
      when /off/
        unmute_audio
      else
        toggle_mute
      end
    when /volume/
      case ARGV[2]
      when /up/
        volume_up(ARGV[3] || 10)
      when /down/
        volume_down(ARGV[3] || 10)
      else
        raise "volume requires up or down"
      end
    else
      raise "requires mute [on|off|toggle] or volume [up|down]"
    end

    Process.exit 0
  end
else
  cores = `sysctl -n hw.ncpu`.to_i / 3
  all_loads = `sysctl -n vm.loadavg`.split(/ /)[1..3]

  loads = []
  if options[:split_cpu]
    loads = all_loads
  else
    loads.push(all_loads[0]) if options[:averages].include?(1)
    loads.push(all_loads[1]) if options[:averages].include?(5)
    loads.push(all_loads[2]) if options[:averages].include?(15)
  end

  indicator = case options[:color_indicator]
              when 5
                all_loads[1]
              when 15
                all_loads[2]
              else
                all_loads[0]
              end

  curr_load = (indicator.to_f / cores).to_i
  curr_load = 100 if curr_load > 100

  chart = if options[:percent]
            "CPU\\n" + loads.map { |ld| "#{(ld.to_f / cores).to_i}%" }.join('|')
          elsif options[:split_cpu]
            split_cpu(options, loads, cores)
          else
            cpu(options, loads, cores)
          end

  if options[:background]
    settings[:colors][:severity].each do |c|
      next unless curr_load <= c[:max]

      color = c[:bg].btt_color
      font_color = c[:fg].btt_color
      break
    end
  end

  if options[:top] && curr_load >= 100
    top_process = `ps -arcwwwxo "command"|iconv -c -f utf-8 -t ascii|head -n 2|tail -n 1`.strip
    chart += " (#{top_process})"
  end
end
chart = chart[0..options[:truncate] - 1] if options[:truncate].positive? && chart.length > options[:truncate]
chart = options[:spacer] if chart.empty? && options[:spacer]
chart = "#{options[:prefix]}#{chart}#{options[:suffix]}"
if settings[:raw]
  print chart
else
  out = %({\"text\":\"#{chart}\")
  out += options[:background] ? %(,\"BTTStreamDeckBackgroundColor\":\"#{color}\",\"background_color\":\"#{color}\",\"font_color\":\"#{font_color}\"}) : '}'
  print out
end

__END__
{
  "touchbar": {
    "close_button": {
      "BTTTouchBarButtonName": "X",
      "BTTTriggerType": 629,
      "BTTTriggerTypeDescription": "Touch Bar button",
      "BTTTriggerClass": "BTTTriggerTypeTouchBar",
      "BTTPredefinedActionType": 191,
      "BTTPredefinedActionName": "Close currently open Touch Bar group",
      "BTTEnabled2": 1,
      "BTTRepeatDelay": 0,
      "BTTUUID": "34F06CC0-503A-49AE-BF35-0C2309AB3619",
      "BTTNotesInsteadOfDescription": 0,
      "BTTEnabled": 1,
      "BTTModifierMode": 0,
      "BTTOrder": 0,
      "BTTDisplayOrder": -1,
      "BTTMergeIntoTouchBarGroups": 0,
      "BTTIconData": "iVBORw0KGgoAAAANSUhEUgAAAIAAAACACAYAAADDPmHLAAAK4GlDQ1BJQ0MgUHJvZmlsZQAASImVlwdUU8kagOfe9JDQEiKd0JsgnQBSQg+9N1EJSSChhJAQVOzI4gquIiIiqAi4KqLg6grIWhALFkSxYV+QRUFZFws2VPYCj7C777z3zvvvmTvf+fPPX+bM5PwXAHIQWyTKgBUByBTmiCP8POlx8Ql03CDAARjgARHoszkSETMsLAggMjP_Xd7fBdDkfMti0te___5fRZnLk3AAgBIRTuZKOJkItyPjFUckzgEAdQTR6y_JEU3ybYSpYiRBhIcmOXWav0xy8hSjFadsoiK8EDYAAE9is8WpAJCsED09l5OK+CGFIWwl5AqECK9B2I3DZ3MRRuKCuZmZWZM8grAJYi8CgExFmJH8F5+pf_OfLPPPZqfKeLquKcF7CySiDPay_3Nr_rdkZkhnYhghg8QX+0cgMw3Zv3vpWYEyFiaHhM6wgDtlP8V8qX_0DHMkXgkzzGV7B8rWZoQEzXCKwJcl85PDipphnsQncobFWRGyWCliL+YMs8WzcaXp0TI9n8eS+c_jR8XOcK4gJmSGJemRgbM2XjK9WBohy58n9POcjesrqz1T8pd6BSzZ2hx+lL+sdvZs_jwhc9anJE6WG5fn7TNrEy2zF+V4ymKJMsJk9rwMP5lekhspW5uDHM7ZtWGyPUxjB4TNMPAGPiAIeeggGtgCG2ANnEA4ADm8pTmTxXhliZaJBan8HDoTuXE8OkvIsZxLt7GysQZg8v5OH4m34VP3EqJ1zeqy9iBHeQy5MyWzuuTtALSsB0D1_qzOoBoAhQIAms9xpOLcaR168oVB_hMUABWoAW2gD0yABZKdA3ABHkjGASAURIF4sAhwAB9kAjFYAlaAtaAQFIMSsA1UgmpQBw6Aw+AoaAEnwVlwEVwFN8Ad8BD0gUHwEoyC92AcgiAcRIYokBqkAxlC5pANxIDcIB8oCIqA4qEkKBUSQlJoBbQOKoZKoUqoBqqHfoJOQGehy1APdB_qh4ahN9BnGAWTYCqsBRvB82AGzIQD4Sh4IZwKZ8N5cAG8Ca6Aa+FDcDN8Fr4K34H74JfwGAqg5FA0lC7KAsVAeaFCUQmoFJQYtQpVhCpH1aIaUW2oTtQtVB9qBPUJjUVT0HS0BdoF7Y+ORnPQ2ehV6I3oSvQBdDP6PPoWuh89iv6GIWM0MeYYZwwLE4dJxSzBFGLKMfswxzEXMHcwg5j3WCyWhjXGOmL9sfHYNOxy7EbsLmwTth3bgx3AjuFwODWcOc4VF4pj43JwhbgduEO4M7ibuEHcR7wcXgdvg_fFJ+CF+Hx8Of4g_jT+Jv45fpygSDAkOBNCCVzCMsJmwl5CG+E6YZAwTlQiGhNdiVHENOJaYgWxkXiB+Ij4Vk5OTk_OSS5cTiC3Rq5C7ojcJbl+uU8kZZIZyYuUSJKSNpH2k9pJ90lvyWSyEdmDnEDOIW8i15PPkZ+QP8pT5C3lWfJc+dXyVfLN8jflXykQFAwVmAqLFPIUyhWOKVxXGFEkKBopeimyFVcpVimeUOxVHFOiKFkrhSplKm1UOqh0WWlIGadspOyjzFUuUK5TPqc8QEFR9CleFA5lHWUv5QJlkIqlGlNZ1DRqMfUwtZs6qqKsYqcSo7JUpUrllEofDUUzorFoGbTNtKO0u7TPc7TmMOfw5myY0zjn5pwPqhqqHqo81SLVJtU7qp_V6Go+aulqW9Ra1B6ro9XN1MPVl6jvVr+gPqJB1XDR4GgUaRzVeKAJa5ppRmgu16zT7NIc09LW8tMSae3QOqc1ok3T9tBO0y7TPq09rEPRcdMR6JTpnNF5QVehM+kZ9Ar6efqorqauv65Ut0a3W3dcz1gvWi9fr0nvsT5Rn6Gfol+m36E_aqBjEGywwqDB4IEhwZBhyDfcbthp+MHI2CjWaL1Ri9GQsaoxyzjPuMH4kQnZxN0k26TW5LYp1pRhmm66y_SGGWxmb8Y3qzK7bg6bO5gLzHeZ98zFzHWaK5xbO7fXgmTBtMi1aLDot6RZBlnmW7ZYvppnMC9h3pZ5nfO+WdlbZVjttXporWwdYJ1v3Wb9xsbMhmNTZXPblmzra7vattX2tZ25Hc9ut909e4p9sP16+w77rw6ODmKHRodhRwPHJMedjr0MKiOMsZFxyQnj5Om02umk0ydnB+cc56POf7hYuKS7HHQZmm88nzd_7_wBVz1XtmuNa58b3S3JbY9bn7uuO9u91v2ph74H12Ofx3OmKTONeYj5ytPKU+x53PODl7PXSq92b5S3n3eRd7ePsk+0T6XPE18931TfBt9RP3u_5X7t_hj_QP8t_r0sLRaHVc8aDXAMWBlwPpAUGBlYGfg0yCxIHNQWDAcHBG8NfhRiGCIMaQkFoazQraGPw4zDssN+CceGh4VXhT+LsI5YEdEZSYlcHHkw8n2UZ9TmqIfRJtHS6I4YhZjEmPqYD7HesaWxfXHz4lbGXY1XjxfEtybgEmIS9iWMLfBZsG3BYKJ9YmHi3YXGC5cuvLxIfVHGolOLFRazFx9LwiTFJh1M+sIOZdeyx5JZyTuTRzlenO2cl1wPbhl3mOfKK+U9T3FNKU0ZSnVN3Zo6zHfnl_NHBF6CSsHrNP+06rQP6aHp+9MnMmIzmjLxmUmZJ4TKwnTh+SztrKVZPSJzUaGoL9s5e1v2qDhQvE8CSRZKWnOoSKPUJTWRfiftz3XLrcr9uCRmybGlSkuFS7uWmS3bsOx5nm_ej8vRyznLO1borli7on8lc2XNKmhV8qqO1fqrC1YPrvFbc2AtcW362mv5Vvml+e_Wxa5rK9AqWFMw8J3fdw2F8oXiwt71Luurv0d_L_i+e4Pthh0bvhVxi64UWxWXF3_ZyNl45QfrHyp+mNiUsql7s8Pm3SXYEmHJ3S3uWw6UKpXmlQ5sDd7aXEYvKyp7t23xtsvlduXV24nbpdv7KoIqWncY7CjZ8aWSX3mnyrOqaafmzg07P+zi7rq522N3Y7VWdXH15z2CPfdq_Gqaa41qy+uwdbl1z_bG7O38kfFj_T71fcX7vu4X7u87EHHgfL1jff1BzYObG+AGacPwocRDNw57H25ttGisaaI1FR8BR6RHXvyU9NPdo4FHO44xjjX+bPjzzuOU40XNUPOy5tEWfktfa3xrz4mAEx1tLm3Hf7H8Zf9J3ZNVp1RObT5NPF1weuJM3pmxdlH7yNnUswMdizsenos7d_t8+PnuC4EXLl30vXiuk9l55pLrpZOXnS+fuMK40nLV4Wpzl33X8Wv21453O3Q3X3e83nrD6UZbz_ye0zfdb5695X3r4m3W7at3Qu703I2+e683sbfvHvfe0P2M+68f5D4Yf7jmEeZR0WPFx+VPNJ_U_mr6a1OfQ9+pfu_+rqeRTx8OcAZe_ib57ctgwTPys_LnOs_rh2yGTg77Dt94seDF4EvRy_GRwt+Vft_5yuTVz394_NE1Gjc6+Fr8euLNxrdqb_e_s3vXMRY29uR95vvxD0Uf1T4e+MT41Pk59vPz8SVfcF8qvpp+bfsW+O3RRObEhIgtZk+1AihkwCkpALzZj_TH8QBQbgBAXDDdX08JNP1NMEXgP_F0Dz4lDgDU9QIQtRyAoGsA7KhEWlrEvwLyXRBGRvROALa1lY1_iSTF1mbaFwnp_TBPJibeIn0wbisAX0smJsZrJya+1iHJPgKgXTjd10+K4iEAamyt7G2CHmhdBf+U6Z7_LzX+cwaTGdiBf85_AjAQG5JmGvd9AAAAbGVYSWZNTQAqAAAACAAEARoABQAAAAEAAAA+ARsABQAAAAEAAABGASgAAwAAAAEAAgAAh2kABAAAAAEAAABOAAAAAAAAAJAAAAABAAAAkAAAAAEAAqACAAQAAAABAAAAgKADAAQAAAABAAAAgAAAAAAipO1xAAAACXBIWXMAABYlAAAWJQFJUiTwAAAcvklEQVR4Ae3baaxtZX3HcbVVKg6ADPfCHc5RKoJorUUK2AqJNg7VpPquidHa+qJKTNPalsbXTYe0aewLgzaxbVobm_RF00QM2NEKLSDWOjB4FfScOwMXRAQcO_w+++7_zXMX+wz77LX3Oeey_8n3rmevtfZ6nuf3H55n7QNPe9rc5grMFZgrMFdgrsBcgbkCcwXmCswVmCswV2CuwFyBuQJzBeYKzBWYKzBX4BRX4OmnyPzM40fCM8KzhscfzdH5Orruc0s+nrD_S6vlf4aff9gc_zft7wfHup7m9jXinArGubvCc8JLw3PDQnh2OD_8WDg3PDO4x7xPCwKGcej3Amc_Fn4QjoXvhiPhibAcXLs7PB4OB_dva9tuAVAZzeGcWkdZvydw_OLwuFoA1PfaAOBsWV0B4FnOefZ3gr5dEwyOnqEa1PfcI5CqYqS59c2ktpPJ4BeGM8LV4exwZXheOC8I6HYJ4GCOMs86ltO7c1f+GSdqV4kvhzq6xukqxAPh2+G2oFp8JnwrLAfXt4Vt9QrASZXpSre2zD4zLAYB4ChbXxA4eaOmL1YBIthWMsFxehAAR4P+94dHAuerCqqE+ywtFVxpbi2rSW+tUR0fjbFx+GVBdr81nBMuDtZ2cJZ7HCdxfr4+tnGuitAuAdr2CCrCPwRV4r+D81syCLZaBeB0mceZyrzMkvECYDHI+F1BmV_LOIe1JZwTWgY3DP_RdwttfC6NqjIMbx+M0TirUqhKlgcbRONeDIL0_uCc5UHQqBBbJhhMcCsZx14YdoRfGR4vyZGQloASfK1xc75NGYfYxctAR59HlWbP81bg+ZxnHPX24OizMXSDIKdOMo7lYI7mdGO4KwiCvwgqwteDcWwJq+jezMEQn7A2ctbVvWFnWAwyXzCslPElOIdzMuGJ6_josH04x40EgLXb8uJ5+n9+ECDajrX0qAAVkI41VgFTAefeheBoXE8E+wfj3tRqUAPPODbFSjDl8+1hd_j5oPxjrYwn8H3hkXBr+GaQcbJ8KbheJbeWAoIXaZ4wY2mpJYCDOXUxCNJLw1nh1cEYXxTK6WmeZPqpimCMloFPhoPh48G5Gl+as7fNqgCELueem7bN3UIQABcE5b5bbstpymqVWJm9FAjZHgXA_kBcWTaJGUdlueXB2DjSOM8MpwWZXUuUzG8DqYLDfe4xT3PfFZx7MAhOczLHmZqBboYJPAIo778eiHlpIKRlYJTziaR03hysqTeEh8NS+H5olwBOr4xPc2KjkzEbF4dyoLFy4GLwCvqWYMl6TTAH93f1NS5zEMR3hsPhT4P5HAnGPFObdQUgCAGJJwA4XkbsDMpp7ajTHJiM4FjCcLZ1cykQzFHJJ+K0hTMO1YTZG5RVZbCuLwWOXQz2C5YJ+pprBYIAUkVOC7uD63uHR1XFXPUzs0pQA0ufMzETvzhw_AeCHbY2IUdlDEFvD0fCx8KxcCDI+MeDsrkppTP9MvoZN8cq74J7T7CsvSMI7CvCs0NrHCxoOftQML8_GLb35Wh+MzGDn4URivOJJPKJpAIomTKkLfnKJKfKCBm_HGS540NBELi+FaxbGSwNTJlfChy5EGweVTjXzZUegt5nQeKcSuC8gPB9lWbqlUCHszBOfmXg_OuCSXN+ZU+aA+N8jufkjwRi3BZs6gQDx28V52coI41TwenK_VVBsL8nnBMsD92AVw0sa0fDH4WD4Qvhu2GqNu0KIMCUxTbzlX1CyIAKwMokGSPbibHctKcuRPrqyypIVSvLlHko9QeC+dGcJjV_waBt2aDHnsC+GiSE7069EqSPqZiy_4rw5nBHENlEMDGTKpS7L4WbwuvDTwSZonJUkKS57czYzUH5p8MbwqfCl4M51_wdaUIbgfLZ8Kbw8iBYpmbTqgAmrgya_AVBVO8MMl+f5VQTl93WPMEBAjwQapOX5ra1mp8stpw57g+qhErodbGCnCa0oZHv0cxxOQgO3_F5W5iJLIRXh8+E+4KI72Y+x98c_ja8Kpi0qiF4TjUzJ3MzR3M1Z3OnAccWNKLVveHTwVuEvRNNe7dpPFQkW9N2BNkv0mvD1838x3LtYJAVh4N1UxncNpGesa7XZDDnqm7a5sxecvzwpEpgT+A+Gtok1tvPltaGg0X53vDx8B+hSnlFuGOb+dZ7wSIYK0DSPGXNHM3VnM19pUrA+RJEBf1Y2BPsB3rVqO8K8IwM0O_j5wSRa91XDZxnnG8dFACV+Xb8Fd1pnvJGg8pok61KcEnalgl6cTLNOJyG7qeppUGVFBy9mA77NLvdXwrXhNeFbunn_H3hnvD74Z_DU8n5me4JEwgceueQi3Lk6LNC+UUQeBuCtspKOxvnXqyvCiBiRa5d7e4hdrfOlVn_rO+Hg+yX+b1Gc5633Uwm04DDaeK4MDxql67PTpuu7qexCiqZBNGWMKXq4vD68JXgjyMGa4DQ_ma4K7whKHf2Cr2uZ3nedjQa0OIl4eeC30MEhWrQ6ucXUtlf+tF8YuurAohW5d56pVz55U_JKhMASr2sPxoeDDXBNJ_Sxsm0oImK6S1BQDwv0JXR8rnB_orGloClMLFVB5M8SASfHX4nvDa8KHSjU_Z_MPxT+HyoCpHm3KKAILA8fifQ6r5weVDuy+jMXzaDi+GWYCmYyCatAAZlrRedO4Iq0AaViYlWf8g5FA4HGx8VYW4nK0CT2iOpBI8FlZS+dGa0pTFNaS6RtOm8IWudtZEH2JxcFi4NvxhsVAy+Bmxwt4Uvhr8J9wYBMLfRCggCS4EqcGHwG4rEoimzFFgGVIa7A_3dbwnZkE1aASoiRaXBtKW_1rYjOS_zRbSAmNvKClTF5Hi62QtwrvOSCjSmNc2fCBMl8aQBoES9NSwG7bJy_sM5IfOXg2VgGkYUps9TxZT2j4WFcFXgcI6uuSr_bwtL4fYgYDZkGw0AA_Fd65NNiU1gG4mcYVCcfiz09b6vX1mh7zOCkuic0uk1yXGiNTHfX830Zc7mWj_OuN9vHJwmWy1xkwaj59FMqfdcc+V0_TP9011VNR5LRFWKNNdvGw0A33thEKEXh12h1qk0B7vZm3NcCgeCIOCcSY3zXxnOD9eGswKxrJl_Hiw1nwt209MwYr8q6P+Xg_WYs_X_0XAkfCFMutTRytrOPhPofE2oKkvri4afL8yRP_YHPw6NZRsNABEoKgnQXfsNwATuH2Jn24fz85jBRIm_NyyGCgBjIZJx7QsyRRBwTh_meeYpC_eE3UF_5s9UA+fYnccPE_1r3DL6e+FoEHithsZjL+C8Mah+B8PYttEA0PFrwmLQ7pry_8mwFDa8PuW7XePo9wTit1WHA94fHgiygxi3BpukPozzrwqc_JvBBkzwWYIYJ_xqWAq3B6W5D6PdDWExvDGYZ2vGdXVYCvcFATOWbTQAZNo5Q7TLRK4ypAQ+HJTGNnLzcSIjOOFfEDi6+q7xuC44mF_S2CSVoDLfsyrrd6at_+o7zYEZl0ysoDh+drJ_a3njeJrSls+Mi9W8BVx3PIMb1vpnowEg668Mi6GtAAYoEpeHHMqxrwAw6Zp4mk8yAnDM+8L9w6uTVoI2838rz_ROPsr5uhP86NMsA+YgEO4N9H1hEPyM9lcEQdn6IR_XZ+MGAAcQ2vojK6yJbcQbqCx4JChHJtCnCSbPVllkRTfqKwhyaaJKYJ6c32b+as6vcRkbDfqyqqi09Owzg74qAGhvjOAT_nR93YE4bgAQ+IKgHJ4butmgTP1nWArafZpJPRo+GhbD+0P39TOnBkFhXJNUgnEyv5z_V+lzORhj30bLW8OR8OJQ2c4flmLXdwUV4mhYd+KNGwAizquIzBeF3QwsMUSrdt9mYkQw7irznN2dR7cSyOg7A1ttT+A+4o6T+fY6XtkOBWObxrxrL2AT3K0w5soX_IK2Iufj6tYVbvW7j5eZS3PTYlByuuaV766wFLT7NpF+R_hKMNG94dfCWpXA2wGhDoRbwkpvB5xvTd0T1lrzyykfzr0y_1+C7DfGvq109VYwSle+4BcBIBBH3ZPTT7ZxA4Dosr+79nsyQUS_X_8eG37OoVezDMhgxpmMc9lKlUBwyGzBwuwdWFsJ2sznfPd61fNMgdM187QP0ff+cDCYd40tzV6Ntp4PVZAOxlzW+qU9X9dXPI4bAO5fGNJ+1wBNXgYsBaKsex3KveOaLLs93D38IoetVAmI4xXt2lDB0q0EbeZfl_tWc765cv71wTw_Gcx7Ws7Powdr+1KOFQj6sk8pZ5dfBIblYN3WOnE9X9KhjkHY1pSdwmbEYKZlnl2Cr7cSyGYmWJhKUAIqnW3mqxrryXx9c_4TYZpmvqVtHQVtjb_8cnpzbl3jGTcA3H_BkFYg2X44WH84X6TOwiatBMcySOPl8K2Y+a2GNOV8G83TAmfXPoxfzg9eF8fy6Vg35+EiTeS10ZePg2znDEwz8_XV2kqVwDhlfBukvudzWwlkvuC1RCj7q2X+w7luCVH2Z5X56eokq_mqfq3OK_nlpC+P+jBuABCQUH4DaMUl4tEh01z708VIq0pwT65amhbC+8KoIHCdw98bbOYIWYHRzimnB+Yezv9Q4Pwbg81YLUFpzsxKZwn4kqZX494RjGnUHJpbT26OGwAizSZD6dEuI2KtTW1k1vVpH_Vp8sZ0cNjZ_Tk6Lwi68yyHD28dHEYJV86X+cvBszl_2mt+uljRRulcfuGb1i8rPqQudIWp8ysdPXzUJpDQhMGs1v909SQTBLcGP+QYx96w0tvBKIfn9hPm+3b7Hw6cf1PYrMxP1wMzplE6t36ZegAQriueAFCeZMxmmnHITscDw4HIXjaqEhy_8uR_zWPUe_5mZr5Rls601i7j9PLL1APA+mMX2nZkMHags94EpsuRVnuCu4dXV6sE3QdU5l+fC9b8Wbznd8ew0mc6m1tXZ77gF9W59Us+rm7jLgGepgMbqa4RDlvBCGU5MM6Hgl8u11udfLfWft9Vcjc78zOEE7aSzuY6lvM9cZQjT_Q0b5z6CmykAsiQUZkumLZKQFVJ9J5_dhj1OpjTI813rae+428aNpRVURw321bSmU_GHt+4AaAD64_1vn3lIJp9gXVo7DKU7_RtxnFF2BOuC+eF9QYBgdf620Fu2RSjbb2FtTqXXyx7YwXBRgLA+thdTw3Gs7pvBzk1UyuBZC3n7w2crwqMM7aqAPna4BlE9Uw2tsjHv9bLv63O3QAov0w9AGyIQJAq+Qbjc3suH2dusuOqsDv4e_5qmd8N4m6AVCV4b57jVdL9B4PfGcx_M8yYbGi7OnO6wBw7ODdSAfzxpPvXPgHg18HuL4Q5NRPTv7JPGM5fCDvCSmWfM_2860i8yviuHnU+twyeqZ+7fIiNLfbxr0387yidzWGUX9bsrDvhtb5AsAeDzdXOYB_APMdn+4Nxn5mvTGycf2XYE2T+as63Wapf+B5K248q1vzVfjEUSP62YO6C4kC4Jcy6EpTOtDaOMn65f4j2um1cZ4k0ToZ2WWXgrDeB1e_zMxDOrzV_tcxvf+E7lu_IHO_6q_1iSGz7CP0tBKZPNstKoP_VNoFdvwwGuNo_4waAbDkclKE20jzHfydATFXBWiXTpm1t5v92Olttza_Mvz737Q9+4eN4pqIxAbRSJejuCdw_y0qgf7qfH1SA1nf8cmSI9rqtfch6viTrlT10HVxrk6Mg8FertkrkY2+2UuavtNsXrG3mc9yjwTyYuTjH1qoEqgubZSUw31ZfbefKWr+Mpfm4ASC6loPO20gTnUqTsrgYXP9GUBGmYZNmPucr3WVK5+3h7uGJrVYJJNTiEBtdWtO4jM7LQWUbS_NxA0Cm+HUM3QogCKyVBuhVxee+zaQ5Xx_tmr9a5j+ce2U1cbqZn1MDkzUVEG0l0N+o_YR5ViUQLMyYPGfsddiX1zBaej74rHV+Pg765RNL2lQrgLIuS5RO7a4pTZcGa+rXgl8M+zTOvzxw_lq7fWWf8z8UOP_GQKBydJpPsqoE9+QK0ReC3f+oIHC9_sui+9P2XMHzuWE7h96Mri8Li0G7a3zh9XQ5jPJL9_4TnzdSAR7Pt0WbUkNk2VCmTZRvhfZ8XZ_06Jk2QbvDjrBW5nMMUQ4Gzq81P82RVpVAhvkO8ww2KgiMx3nV0Jgsi9OYdwUbbbVb4wO+4Bd0K3NOrWzjBoDODgeTVFZPD60wMvTV4YLwd6FvOyMPfHdYDP5HyVFit5nP+TeFtTI_t5xkstkvfkouW60SGAPHvCvo75YgQfo0uvqFczFY_8vM1W8TR8Oh4dG5ddu4ASBDRLkyQ1S0jhCdnOScPw7ZvLjf9_qwNhNWc_64md8dm_FWtVhPJTAuc1b5uhmaUxu2p+ebfERLutpkt8+X7eUHVYDWY9m4AVAPt1beFkTeuYGjmeOLggEvBhMQmQY3qXkWVrI+Mr_77HEqge_2Feg1Dv7ZExbCi8Ou0Pqs_LCU89pjW_uwcb5M7GPhuaEtORxkk6JkWRoeDUdCX6Yv7_MyQd8luExw3rK0HA4GmVFZnOaGbFQlEPT6a9djAW7DaQxjrcG5fzWT7fqhZVXU9n56PDSk9UN7z6rtUWV01S8MLxJGxHHw6wNntOY6Uc4LXwwyqQ_zXELvCxcGYnOyILs+3Bj+MXw99NVnHjUorRy_P9gD3Rn2BqJb7537s_DpcHfoo+LlMYOy_44cfzq8IgiC1gTcR8KXgjGMHQQbrQCEt949EghtT6D8V4kWWDuCa88KPo89uHyna9a4qigyXQAKCuPw2TWZ36fz87hBHwJNXweCcSwF675zHKHq6L+PedKRZqcFOqL1lT4FmSQ0d77gk5mZAXL4QrghfDl8LxgYiGBgzl8edgYTmtT0a3lRcbxp7B6i7ZwdsnumZZ6tj1H9++3D2Pron7PN6cpwV+Bgmpa+tJb1nwgqUZt8+bh+a6Nq_d86PpCKwGP5IkHayCeCV0RrtU2i7FG623vycWwjgKhnfb9qHX_q6v_qv6rLNPu39p8daOdVlJZtYNGR7l4BBcOGl5w+slLn1kfRaqDMYE3C82WMKP2vUOKlObdVFDgr164N14SXhW5lUV0_Em4L+8KGA2CjFSB9DkwkPhA4mXPbvYAg8Pydw_OqxOOhloo059ZRgGbWfVpZAs4PNKzsV4E4m9Z0x0RVddIKUKXIZuzyYCNyRqjnVgAoZ18NAkXZGvsHi3znqWAy_bLw8vCu4N2_zX7OpyM+Gu4NEmrDpkxPYrUmy+z7h7QRKXI53Tq2K4hqEV4BkubchgrQhDY0opUqQLvK_jQHiUPno4Hm9kN8sOlmoK8J7wj1PmpgxffT_lr41+B99pwwD4KIMDRanBt+MvxbkNk0K_0cJdah8PbwM0FlmNgm3QPUAAzOemRQNiheiURwVRgT5HSTsif4Qfh2sGSY3FPZZDg_CADa7AjdBKETvbwOyn7LKM0ntr6y0ADtA7waGfyxsBj8CMRMUvv0sDu8NHwuKGG++1S10uW8CPCB8MZwaWiTJx8H5f7GHD8bPhFU2R+Gia2vCiCLZbfdqTLludrWNG0TVQ0EwQVB9Ir0qhy9TCbP224mAc8OtNgV7PppVJWTrqql31HoejDQ1blerK8KUIMxsPvCN8Irg+z2Y1D1Y2LecZU7k74kfDFsmc1MxjIro4lq+f7wpnB1EADPDBKG0ZOWXwt_HG4NlgGB0Yv1VQFqMBxuDyDzlSnP3xVMlvOr5NVSkFODQHB8KKgIvU3OQ7eg0YAelfl70rYs0kT2l9FSAFjzaUkf2jrfm1Vm9vbAPMgAvZt+PdwTrggCoo1sgWHdM3EBYk9wZ7CM9DrBPG8rWSWACijz3xxeFxYDjVxnNLDp4_jfDZ8K+4OA6DVB+q4AGd9ggNZ076uefyTIfpFeQWCiXh2ZIGD2BgLygeD7qsGpZOZWgW_52xvM3W8k3p7KONj87fRpJwhKk16dn+eeWJu1+zQDfTwoWctBdl8WRDkhKtJLEGJcFH4q7AsyQBXpfcJ55maYOb8gcPgHwi+Eq8NCaDPffM1b8vxeuCHYI9FxKgkxjQqQsZ6oAjZ3hwKHW8scRb9+taESEEiFqKNKodwRYzsHgvlxMCx13vMF+_nBq96zQhnny3yv0LQ6GGQ_DZ2fihngNM3zOdNkXxs42dpn99uNfA63B7DWyYDrAwE+H4iwHU1pV_ksb9cGwU8DjqdL6V+Zz_l_Emjw6fBY6H3dzzNP2LQqQHVgYpzqPVZEsyPB+aoE9geEIIrxEEt7MRDpULCcPBosDUqh729FMw9VzJy8_gr8hSD7OV7gnx5cLzMnGW6dl_mcTyua0W6qVhE41U7ycP3IeJO_IhDjunBeeE7oCsLJ3ndlwM1B0HwseBWyOZpaScyzJzEBbIfvFe+dQan_2SAQ6q+k3bna7ZvTHwaOvyNw_kyWPgOehclYZVy0m6TPMpujZUdlv0AhEGSL4JBBgsdRADHiqAqVPZ63GWa8NDReYzXOvUEQGK8AUOnqjSfNgRmv0g5ZL8D3h8NB0E8989PHwGZVAdr+lHVr4yVBuf+NYHO0GFxrjVC1CbITtgz8e7BHuCF8MwgoQm6GGa9qdlZ4S+Dsa4JXuzOD4DDXrs4c_I3A+R8MHL8vmKu5mPdMzABnaSZm8jJXBVDKl4dHgsmUdo0knHO+56iMLgzbizlaZz1LRagKU8_vU0jj4GyZrlo5cmxVJq94i0EA7A7mYC_ge60Zq_KOA4HjZf4DwbmZL23dAWYMMzH9EkgAKpfK_TvDrvCGYM0kcmuCAN8Jlg5LAKffG1SHW4OKcFewri6FCoY0N2zl9MU8QWa_LMj4q4KAfHEQCJaANuO72nK+cd0UBP9fB3uaY4Hjzcn8ZmqzrgA1OROtSSvnMnh5eI44qgFxjU_mEbMgNJP9shzuPxJ8R2AQmuACANWfY0s+nrB6fgWevp2T8VgMAsBRADgag6A1xlGmL+MzV0H6rbAcDgbZ75xr7tsUe_qm9Hpyp8ZAdOIq8zJMKX13OC_8eOCAUUa4CqR2CXBOEHA+oV0TID7bZMk250p4Y1DSOV310d_OYDznDz8bn+uuGa9rjs6tpKP+vhoE+V8Ga_7dQRWrIK0x5NTszeA32wjAIbLBOrg_cM5SIBSHENvRslEVIc2B8D6DA8s803c5gMO0lem1AsDzOboNAIHgszGs5OhcGph+Zbz5CDT9LgeOXwoPhmPBPVvC1prQrAdpPJzJEfVDyuVpqwRvC_YKFwUOWcs4A1ViHZmloa4NTgz_0TdktaMxOFaGa69lAmxf4OS_DzZ3dwTLkjcYgVHjSXPzbStUgFYFjiEiUwWIthxUhqUgq+wBZLuM5CRtTtNujcNQwaIC9GmcKZiMU1u2axuvTHcUAEeC81vSCLSVzfg4jnMtAZx9YbDpuzqoCFcEZVu7GwQ5NRXjcE4WkLcFGX9z8BZyX7Cpdc192gJ7S9pWqwBdkQhX2aOMWh6M2W56KRB5ZxAA7nNdxrebsyrhgkNAteTjCatloY6cp10l27HeLKzhR4ON3FIQAI72MUfCllnjM5ZVbatXgO7gjZdDObhdAjh9V7A8vDQIiIVwerCLVzlUCAGiknjGacFzGMfKVE4WVJYhThVUHFqbOQ6_KwjGQ4Gj3SNY3OM5FTBpbn0jxHYyGVnZxWFl5uG8AOB0AeBebfcJAI4VKO5xv3OVAO7lyFEBINPtQZaDAHAUAM67f1tbCbCtJ5HBm4cSL6M52WfZ7sjZdd2xJR9PmCBo6S4BAsx11UGm1_U05zZXYK7AXIG5AnMF5grMFZgrMFdgrsBcgbkCcwXmCswVmCswV2CuwFyBuQJzBbasAv8Ph4K7Pz+1GwoAAAAASUVORK5CYII=",
      "BTTTriggerConfig": {
        "BTTTouchBarButtonColor": "0.000000, 0.000000, 0.000000, 255.000000",
        "BTTTouchBarItemIconWidth": 22,
        "BTTTouchBarButtonTextAlignment": 0,
        "BTTTouchBarItemPlacement": 1,
        "BTTTouchBarButtonFontSize": 15,
        "BTTTouchBarButtonCornerRadius": 15,
        "BTTTouchBarAlternateBackgroundColor": "75.323769, 75.323769, 75.323769, 255.000000",
        "BTTTouchBarAlwaysShowButton": false,
        "BTTTBWidgetWidth": 400,
        "BTTTouchBarItemSFSymbolDefaultIcon": "",
        "BTTTouchBarIconTextOffset": 5,
        "BTTTouchBarButtonWidth": 100,
        "BTTTouchBarOnlyShowIcon": true,
        "BTTTouchBarFreeSpaceAfterButton": 5,
        "BTTTouchBarButtonName": "X",
        "BTTTouchBarItemIconType": 1,
        "BTTTouchBarItemIconHeight": 22,
        "BTTTouchBarItemPadding": 0
      }
    },
    "bunch_group": {
      "BTTTouchBarButtonName": "Bunch",
      "BTTTriggerType": 630,
      "BTTTriggerTypeDescription": "Group",
      "BTTTriggerClass": "BTTTriggerTypeTouchBar",
      "BTTPredefinedActionType": -1,
      "BTTPredefinedActionName": "No Action",
      "BTTEnabled2": 1,
      "BTTEnabled": 1,
      "BTTMergeIntoTouchBarGroups": 0,
      "BTTAdditionalActions": [],
      "BTTIconData": "TU0AKgAAEAgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA____Bv___wMAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA____Dv___wUAAAAAAAAAAAAAAAD___8H____Hf___1f____k____BQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD___+R____hgAAAAAAAAAA____Lv___7P______________yQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP___wX___+4____DP___wX____x____7____+3___9v____AQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP___x____+D____N____9f____H____TgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP___2f___9k____Uv___yD___9C____nv___7_____L____xf___yoAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD___8G____Kv___xz___8_____XP___wX___9h____jP___7L____8____3P___2YAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP___zz___8N____iv____3___+a____R_______________ygAAAAD___9q____1P___8H____7____7v___1oAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA____9f___13____q_________+____+T_______________4____AgAAAAD___8O____pv___+z_________4v___yEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP___xP___9Q____Iv___4_____t____of___0P____7_________84AAAAAAAAAAAAAAAAAAAAAAAAAAP___z7___+C____jf___wYAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD___8d____9_______________fwAAAAAAAAAAAAAAAP___xH___84AAAAAP___wf___8K____BAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP___9L____________________8____E____2T___9xAAAAAAAAAAD___9w____9v____r____z____LgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA____3v________________________+2______________+5____Lv_________________________1____GAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD___+M____________________1P___8L______________93___+d______________________________9FAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP___wH___9_____zP___6b___8j____Wf____3____9____d____5n______________________________0QAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP___zv___9B____AwAAAAD___8G____Yf___23___8G____LP_________________________v____FAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD___9x______________+A____CP___7v______________9X___8G____af___+H____z____0f___y4AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP___9j______________9n___9g_________________________3oAAAAA____G____yH___8BAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA____jv____7_________j____3z_________________________qv___xX____+_________04AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD___8B____KP___yr___8D____NP________________________8z____bv______________vwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA____tv___+v___8t____S____+r____x____WwAAAAD___8O____9_________8wAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD____T_________z4AAAAA____A____5z____c____rwAAAAD___8J____EQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP___x3___9H____JAAAAAD___9F____________________WwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA____E____+b____+____bP___07___________________9zAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD___9D______________+v____DP___8X____7____0P___wMAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD___+3____3P___0D___8k____Sf___xYAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA____Mv______________5QAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD___9p____________________AwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP___yT____7_________9oAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP___xz___86____DgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABIBAAADAAAAAQAgAAABAQADAAAAAQAgAAABAgADAAAABAAAEPYBAwADAAAAAQABAAABBgADAAAAAQACAAABCgADAAAAAQABAAABEQAEAAAAAQAAAAgBEgADAAAAAQABAAABFQADAAAAAQAEAAABFgADAAAAAQAgAAABFwAEAAAAAQAAEAABGgAFAAAAAQAAEOYBGwAFAAAAAQAAEO4BHAADAAAAAQABAAABKAADAAAAAQACAAABUgADAAAAAQACAAABUwADAAAABAAAEP6HcwAHAAACVAAAEQYAAAAAAAAAkAAAAAEAAACQAAAAAQAIAAgACAAIAAEAAQABAAEAAAJUbGNtcwQwAABtbnRyUkdCIFhZWiAH5QAGABgAFAApAAVhY3NwQVBQTAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA9tYAAQAAAADTLWxjbXMAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAtkZXNjAAABCAAAAD5jcHJ0AAABSAAAAEx3dHB0AAABlAAAABRjaGFkAAABqAAAACxyWFlaAAAB1AAAABRiWFlaAAAB6AAAABRnWFlaAAAB_AAAABRyVFJDAAACEAAAACBnVFJDAAACEAAAACBiVFJDAAACEAAAACBjaHJtAAACMAAAACRtbHVjAAAAAAAAAAEAAAAMZW5VUwAAACIAAAAcAHMAUgBHAEIAIABJAEUAQwA2ADEAOQA2ADYALQAyAC4AMQAAbWx1YwAAAAAAAAABAAAADGVuVVMAAAAwAAAAHABOAG8AIABjAG8AcAB5AHIAaQBnAGgAdAAsACAAdQBzAGUAIABmAHIAZQBlAGwAeVhZWiAAAAAAAAD21gABAAAAANMtc2YzMgAAAAAAAQxCAAAF3v__8yUAAAeTAAD9kP__+6H___2iAAAD3AAAwG5YWVogAAAAAAAAb6AAADj1AAADkFhZWiAAAAAAAAAknwAAD4QAALbDWFlaIAAAAAAAAGKXAAC3hwAAGNlwYXJhAAAAAAADAAAAAmZmAADypwAADVkAABPQAAAKW2Nocm0AAAAAAAMAAAAAo9cAAFR7AABMzQAAmZoAACZmAAAPXA==",
      "BTTTriggerConfig": {
        "BTTTouchBarButtonColor": "75.323769, 75.323769, 75.323769, 255.000000",
        "BTTTouchBarItemIconWidth": 22,
        "BTTTouchBarButtonTextAlignment": 0,
        "BTTTouchBarItemPlacement": 1,
        "BTTTouchBarButtonFontSize": 15,
        "BTTTouchBarAlternateBackgroundColor": "75.323769, 75.323769, 75.323769, 255.000000",
        "BTTTouchBarAlwaysShowButton": false,
        "BTTTBWidgetWidth": 400,
        "BTTTouchBarIconTextOffset": 5,
        "BTTTouchBarButtonWidth": 100,
        "BTTTouchBarOnlyShowIcon": 1,
        "BTTTouchBarFreeSpaceAfterButton": 5,
        "BTTTouchBarItemIconHeight": 22,
        "BTTTouchBarItemPadding": 0,
        "BTTKeepGroupOpenWhileSwitchingApps": true
      }
    }
  },
  "streamdeck": [{
    "BTTStreamDeckButtonName": "Bunch",
    "BTTTriggerType": 630,
    "BTTTriggerTypeDescription": "Group",
    "BTTTriggerClass": "BTTTriggerTypeStreamDeck",
    "BTTPredefinedActionType": -1,
    "BTTPredefinedActionName": "No Action",
    "BTTEnabled2": 1,
    "BTTAlternateModifierKeys": 0,
    "BTTRepeatDelay": 0,
    "BTTUUID": "22D57E02-1601-4CC8-8C28-BDAAE2BD8345",
    "BTTNotesInsteadOfDescription": 0,
    "BTTEnabled": 1,
    "BTTModifierMode": 0,
    "BTTOrder": 12,
    "BTTDisplayOrder": 0,
    "BTTMergeIntoTouchBarGroups": 0,
    "BTTAdditionalActions": [{
      "BTTStreamDeckButtonName": "Close Group",
      "BTTTriggerType": 719,
      "BTTTriggerTypeDescription": "Stream Deck Button",
      "BTTTriggerClass": "BTTTriggerTypeStreamDeck",
      "BTTPredefinedActionType": 340,
      "BTTPredefinedActionName": "Close currently open Stream Deck group",
      "BTTEnabled2": 1,
      "BTTAlternateModifierKeys": 0,
      "BTTRepeatDelay": 0,
      "BTTUUID": "F270727F-2968-4D54-BAEB-1707EB9479F0",
      "BTTNotesInsteadOfDescription": 0,
      "BTTEnabled": 1,
      "BTTModifierMode": 0,
      "BTTOrder": 0,
      "BTTDisplayOrder": 0,
      "BTTMergeIntoTouchBarGroups": 0,
      "BTTTriggerConfig": {
        "BTTStreamDeckImageHeight": 49,
        "BTTStreamDeckCornerRadius": 12,
        "BTTStreamDeckBackgroundColor": "0.000000, 0.000000, 0.000000, 255.000000",
        "BTTStreamDeckSFSymbolStyle": 3,
        "BTTStreamDeckIconType": 2,
        "BTTStreamDeckAlternateImageHeight": 50,
        "BTTStreamDeckIconColor1": "255.000000, 255.000000, 255.000000, 255.000000",
        "BTTStreamDeckFixedIdentifier": "grouped-0",
        "BTTStreamDeckDisplayOrder": 0,
        "BTTStreamDeckMainTab": 2,
        "BTTStreamDeckAlternateIconColor1": "255, 255, 255, 255",
        "BTTStreamDeckIconColor2": "255.000000, 255.000000, 255.000000, 255.000000",
        "BTTStreamDeckAlternateIconColor2": "255, 255, 255, 255",
        "BTTStreamDeckAlternateIconColor3": "255, 255, 255, 255",
        "BTTStreamDeckAlternateBackgroundColor": "255.000000, 224.000002, 97.000002, 255.000000",
        "BTTStreamDeckAlternateCornerRadius": 12,
        "BTTStreamDeckSFSymbolName": "xmark.circle.fill",
        "BTTStreamDeckIconColor3": "255, 255, 255, 255",
        "BTTStreamDeckUseFixedRowCol": 1,
        "BTTNotchBarItemVisibleOnStandardScreen": true
      }
    }],
    "BTTTriggerConfig": {
      "BTTStreamDeckImageHeight": 46,
      "BTTStreamDeckCornerRadius": 12,
      "BTTStreamDeckTextOffsetY": -82,
      "BTTStreamDeckBackgroundColor": "85.000003, 85.000003, 85.000003, 255.000000",
      "BTTStreamDeckSFSymbolStyle": 1,
      "BTTStreamDeckImage": "iVBORw0KGgoAAAANSUhEUgAAAYAAAAGACAYAAACkx7W\/AAAAAXNSR0IArs4c6QAAAHhlWElmTU0AKgAAAAgABAEaAAUAAAABAAAAPgEbAAUAAAABAAAARgEoAAMAAAABAAIAAIdpAAQAAAABAAAATgAAAAAAAACQAAAAAQAAAJAAAAABAAOgAQADAAAAAQABAACgAgAEAAAAAQAAAYCgAwAEAAAAAQAAAYAAAAAAvg3ZkgAAAAlwSFlzAAAWJQAAFiUBSVIk8AAANDlJREFUeAHtnQe8JWV9v1kVaVJVUOoiAioioohEwEgxtqCCEYiioP6JNYaoWIjdmBBBxYaiRrGgERFECCpRUCyIoCAdpC596X1Z2v\/5Xu\/Bs\/eeMnPOzCn3PL\/P57szZ+Zt88zd3zvztllqKU0CEpCABCQgAQlIQAISkIAEJCABCUhAAhKQgAQkIAEJSEACEpCABCQgAQlIQAISkIAEJCABCUhAAhKQgAQkIAEJSEACEpCABCQgAQlIQAISkIAEJCABCUhAAhKQgAQkIAEJSEACEpCABCQgAQlIQAISkIAEJCABCUhAAhKQgAQkIAEJSEACEpCABCQgAQlIQAISkIAEJCABCUhAAhKQgAQkIAEJSEACEpCABCQgAQlIQAISkIAEJCABCUhAAhKQgAQkIAEJSEACEpCABCQgAQlIQAISkIAEJCABCUhAAhKQgAQkIAEJSEACEpCABCQgAQlIQAISkIAEJCABCUhAAhKQgAQkIAEJSEACEpCABCQgAQlIQAISkIAEJCABCUhAAhKQgAQkIAEJSEACEpCABCQgAQlIQAISkIAEJCABCUhAAhKQgAQkIAEJSEACEpCABCQgAQlIQAISkIAEJCABCUhAAhKQgAQkIAEJSEACEpCABCQgAQlIQAISkIAEJCABCUhAAhKQgAQkIAEJSEACEpCABCQgAQlIQAISkIAEJCABCUhAAhKQgAQkIAEJSEACEpCABCQgAQlIQAISkIAEJCABCUhAAhKQgAQkIAEJSEACEpCABCQgAQlIQAISkIAEJCABCUhAAhKQgAQkIAEJSEACEpCABCQgAQlIQAISkIAEJCABCUhAAhKQgAQkIAEJSEACEpCABCQgAQlIQAISkIAEJCABCUhAAhKQgAQkIAEJSEACEpCABCQgAQlIQAISkIAEJCABCUhAAhKQgAQkIAEJSEACEpCABCQgAQlIQAISkIAEJCABCUhAAhKQgAQkIAEJSEACEpCABCQgAQlIQAISkIAEJCABCUhAAhKQgAQkIAEJSEACEpCABCTQD4EHH3xwPfSoftIwrgQeJgIJSGC8COD4t6HEu6CHj1fJLe2oEbACGLU7Ynkk0IYAjv+xaF9O\/wDdPG\/evFvbBPWwBCQgAQmMOwEc\/sPQBmg\/dCm6H12O1hn3a7P8EpCABCTQggAOPo7\/OehAdA1qti+3iOIhCUhAAhIYZwJ4+RXQP6H\/Q7egmXYHB542ztdo2SUgAQlMBIE4a\/SkbhdLmI3Qu9F56F7Uzo7ihH133YB6XgISkMCwCOCkl0FvQSegDdqVg3Mboveha1E3u48AL22XlsclIAEJSGDIBHDSj0Jfm\/bmH2xVHM6thQ5Cl6Ki9iMCrtgqPY9JQAISmPMEcIBxrm9Fh6Ovo79DIzMePmVBn0SxNOVsn5vCdh5aEW2K9kdXozJ2D4GfP+dvsBcoAQlIoBUBHOCj0fdmeM3F\/H4nGol2ccrxryhDNWPZHobehj6BjkA3oV7sf4n0yFZcPCYBCUhgThPA+eUJ+oNtPOciju8+SADk9zy0hEPm99tRylK1ZeTPswZ5feYlAQlIYGQI4AAfic7o4FlP4dzKgygw+eyNMhpn2UZ+7G+FbkZ12P6NfNxKQAISmDgCeNVUAGd38a5vqBsM+cfRZ2LWT9Ejkh\/bVdEvUB32KxJdo+7rMn0JSEACI0sAJ5iZsQd38bBXcn5+XRdB2lmL55zpMvyA7VTnM9svTB+renMjCW5d1\/WYrgQkIIGxIYAzfBK6uIuX\/TLnaxkVRLoHNuV9QsDxO81Bdzcdr3L3gLG5ORZUAhKQQN0E8K67oHSKtrM8Nb+k6nKQ5nZoYVOm57Of5qA\/Nx2rcvfXJLZa1ddhehKQgATGmgCOMTNsOy2XcDznl6\/qIklrJXQiarbMyl3QfKDC\/dNJ68lVld90JCABCcwZAjjHDAn9MGpXCeT4dlVdMGm9DD2ABmG3kcnU5LGqym86EpCABOYUAZxkVs38bAePnGGaffcFkEZGH\/2sQz5FTmUWb5EJYJk49u45daO8GAlIQAJ1EMBZLo8yGqeVpYmm774A0ngpSlq9Wlb3zGzgmWv6t0rvUxwciRnNddwv05SABCRQKQEcZoZmntDKm3Ls52iZXjMkbp7+05\/Qi91ApAPQnqhIX0GGuPqR915vlvEkIIHJJIDjfCI6Fc202znw2l6pEDcjjlp9lGVmPjN\/n8SBbdHfoItnnmzxO2sErdprOY0nAQlIYKIJ4EA3QZkINtMyk7b0EhHEyaqeh89MrMvvNBV9Aq2IXoiuRt0szUOlyzfRN9uLl4AEJDCTAI70HS28bUbvlO4LIM4G6KoW6bU7dCsnXpcysX0OKuL8DyWcY\/1n3kh\/S0ACEihLAGe6HMoaPTPtGA6UGhFE+NfMTKTD74s4t3PKy\/bZ6MIOYRunfsTO6mWv0fASkIAEJNCGAE51UxSH3GxZquGZbaLMOkzYpVHa8YvY0QTaOImw\/Tt0eZdIGRL6cWSzzyzyHpCABCTQJwGc6+vQ\/ajZPls0WSJtieKou9mJBHhc0mW7IcqQz052HSd3Q\/OKlsVwEpCABCRQggAO9lFo5vDNrN2zdpFkCPefqJv9lgAbJD22K6M06XSyfMtghyL5G0YCEpCABPoggLPNqKA8cTcsy0N0nWVLmDT\/xLl3smM5OVWZsE2\/wzc7BebcIWjqTaGPSzKqBCQgAQkUJYDTzaJxzbN4f87vjovEcf5ZqNVwUg5P2cn8u07KwDZrEn1y6mjrf67gcMow9eGYouU2nAQkIAEJ9EkAx5svdf0YNew2djp2BnP+X9DiRoQZ23Qub9ooFvv\/iNLB3Moyh2DzRli3EpCABCQwYAI44azls6jJQ3f8vi7hDmsK27x7FT+e1yg++xnx02qBt8z83QP51N+A5VYCEpDAMAjgiJdFabZpWJplWk6+4vjq6E+NgE3b9B\/s1ig\/+1ugmWP9M2roK2h+I5xbCUhAAhIYMgGc8p6osZ5\/hofu1apIHN8c3Ylm2oGN8JxYCeVrXc2Wsf9vQ0NbyZO8s3SFw0sbN8ptIQK+phbCZKAxJ\/B9yr8v2gTFSe+ODkUz7dkcmNlJfBTH3p+A0w72few2f6j9W\/z+j3nz5p2fMFXZdGWSsmaRuPXQumg+ejRaEa2CVkIroGVRZjqnkrs\/W\/Qgyv4idCW6FC1Al6OL0Q2UOeE0CUhAAnObAI7xfahhl7DzlOYr5neeoGd+W+DPHHvo04zsvxg1On0Xsv9OtHRzOr3sk0Y6qzdAz0EZNZSmpIxYSqfzzSirmqYfI28vvVoqhzRT5XvKSTNvMe9Cz0TroKG9vfTCzDgSkIAEChPAwT0d3YhiceJvao7M7zjhq1HD4ixf0wjD\/nzU6B\/4Jft\/2zhXdkvcR6DN0GtRJp1lXkGnoaecrs3SuZ1K55Flr8PwEpCABMaCAA5uGfRV1LBvNxecg9uidPY27HB2ppwi20wO+970ie+yLb2Oz3Qa27DNvIE8fV+Dhmmp7D6O0u8xs9mrGY37EpCABMafAI7uDahhZ7OzRuOq2H89ajSxpFN3\/aZzz+d35gZ8AZVyloRfC+2FTkNJY9h2KwX4PFoP2WncuMluJSCBuU0Ah7c1igOMpU19i8YVs\/\/vOYileWjPpuMr8Pv\/0MdQOlsLG+GXR29FJ6Nz0RXoPjQsSwU31aFd+CIMOKcJOApoTt9eL24GgbP5fQXKaKB8Kzjb01Bso79slvoi28Oyj7PME3JGDB2NvsComYysKWP3Evgb6DtoOZQRO49BWUcoeW+GnorWQxnFM4iO2H\/gunKtZ6A\/TG\/v4NoyYkibMAK+Ak7YDZ\/0y8X5HQeDF01z+Dzbt8exYyezvxbaht8ZLpkKIEMwN0B\/5FjlQyZJP5VQ+hkyMS2VQaNSeBL7+VjM41Fdluu5B92OMoT1VPRrlEryKq73braaBCQggblDAKf7RdSwrPoZBxxnn47ZJZpH+D2UByTyfQTKonT7ogxNTfNRo3+C3Voto4IORRmhlJFKeTPRJCABCYw\/ARzau1HD7mJn6imbbfoAWi4RUfVVk0+pph7Cr40ygui9KJXWoPoRMlLpRLQzsrm46j+EEUhvKE84I3DdFmFCCeDIduDS90b5238U+jeaO\/KxltXY3sTvQkb4vDmkUzjbtPXfTfzFbLsacTckUJqb8nR9G7oZ3YVuJ400ybQ14mYU0tPRG9E2aD4qVaEQvqylf+BXKKx+Wzay4UeXgBXA6N4bSzZiBFJJUKRnoGehdVGGkWZOwK1oIboIpXP1dBzljWxbGunEYWci2avRFuhx6GqU+OegC9CVaAHpTPVHsD\/LSGc+B3dGL0bPRlkiog5LxdhYUuLt7P+ecpXtEK+jXKYpAQlIoF4CcfzoE+hMlGajTpZhpGehD6Cs29PRCLMm2g0lTrNluOqF6Fco8w\/+HmUhulkPbRzLiqfPQJ9BWTaiKruIhHZC+brahtPbddjOKkPHi\/SkBCQggToI4IzyScYnoi1QnGTaq5+DnoTydN6zET+dsbuj81Avdj6RXlWkAIRbEe2JTkWtLPMWFqDD0KtQHPIST\/z8fhhK53FmK7f6VgGHS1k+qfncIuU3jAQkIIGBEcAx5Wk4T87fQBm5MtPiAI9EWaZ5zbIFI84y6EMoT\/T9WOLvgwpNIiNcruuD6FLUya7lZJan+GeUCW5LVHb8fjE6BmVNo34sbxQfQRuUZWh4CUhAApUTwBllMlO7J2VOzbI8iWdGbqGRLAmH0uxSlWUI55dQofwDjLAboJRhMepmtxAgHdnfQi9FU8tVsM0Eh4weSkXQr11KAinPU1Ddnc6V\/82YoAQkMOYEcDxxzHnivROVtQyd\/G+U2bhtjfNxmu9ED6AqLem9BxVuPyfsw1GatMpUdmkqugDlLWITNFXpsP0QSkXRr+W7ykegHVFmN2sSkIAE6ieAw3kHuhf1Y1kIre0a\/px7Cbqxnww6xE2z1FZlSRHnsWh\/lPhlLOv+561gV\/QY9EL0R1SF5a0mzW9JMzOaNQlIQAL1EMDJ\/CPqtz2eJKbsA61KyZmV0El\/CVLbvz8g5SXa61uVpdUx4qWj+\/uol7eT84h3MEoH8ndQv30DJDFlebP6CcrcBm3MCBR+HR2z67K4I0gAJ7EOxco6N5ujtCOfji5gTPllbNsa8bKA2knooa9ztQ1c7ETG7O9Ovic2Byefnfh9NKrz\/0XW4HkFef+wOe+i+5QxE8\/2RB9CmUxW1jLR7PfoPrQdSnq9WiavZQ5E0srchf3Qac4RgIImAQn8hQBOK23ZO6Gz0ExLB+0uqG3HIuf2Rr089RKtrWU45UPOj\/0MoTy8behqT\/ww+fXz90H8rdDRfRar25yGbsmfSYB0Mm+A\/hZthzK7WZOABCTwFwI4hXSqdnI26bj8t1a8OJ6265+jqu0GEtyokSf7j0Nl29h7LVPa5nt5em8Ud2pLGhmqmiadK9AwLPf035colD8kIAEJNAjgILZERUafLCTcCxrxGtvp+FW1\/ZPcErZrUz67ciYdm4Ow5JNlICox0toYpV0\/FemgLdfyMeSTfyV3c7CJ9PUaOtiimtuYEngH5S7S6flYwr0eRzLzbzIfTCk0iaoHPmlGabT3b0z8mXn3kGShKMkn+VVitLmn\/X0P9M\/ozEoSLZ5IrmVf9MYW9654KoYcCoFB\/cEP5eLMdLgEcAgZc59O36KWkSQz189Zr2jkHsKtTZzGk2vp2cI95NccZWoZ6uYD\/exTCTyAvkIaeYt6E7qwn\/RKxl2G8J9E7yoZz+BDJmAFMOQbMMezzyqXq5S4xoTPiptTNv10PrNCaJyuYpu3jsb\/gYw0GqQl78qNSuBadAgJb4P+C11ReSatE8xbWpqC8sanjQmBxh\/\/mBTXYo4ZgQwRzFDBonYbAe+cEXjm7xmn+\/p5B7EzLDOW\/UFarflRCVyP3ssFZWhr3gzCtm7LqKoPUwn8Y90ZmX41BKwAquFoKi0I4IBu4PDVLU61O3QZJzJGf8qI\/yA7V03\/rGOTsjUqgDLlrKIsA8kPhn9C\/0SBM+b\/wyhNQ41rZrdyW5EUv0Ql8P8qT9kEKydgBVA5UhOcQeBb\/M4XpbpZwhyLs1o8I+C5\/K7LYZ1Jfo2001SSCmcQljwXDCKjRh5cZz5s\/xF+b4nyhH4sqqtyXYm0D6ISeD1bTQISmFQCOIGlURYP62ZZImFqFctmVhxbD52NqrYMLd2ikRf7T0Wd5ipUmX\/y2ayR97C2lOFZ6AB0Mup3jSWSmGW3cuQNyAfNYd1k85XAsAngAFZDn0KtnEzWkskywy07RTmeFUDTuVi1\/YIE803gKWM\/FdVvqs6kTXq\/5\/jUKp2N\/Ie5pSyrogyJzYS9n6LbUFVzIrLm0CdRRgppEpDAJBLAAWSphSxt\/FWUJ85T0NfRP6DGUMyWaDifp\/NMFKvKUhHNap7g2NuryqBLOiM7UoZyL4PWRK9F30bnoMya7rdCyNIbfc9+bvkH4kEJSGBuE8B5HIiqsiNJKJ2VSxjH1kaXVJVJm3Syfk4WxRsLo6yroBegfdDB6McoTXJp3ilrfyTCq9FDb15jAWEOF7IxC3IOX6KXNhcI4DTSP\/B19NDyDT1e16nEexkdote0ik8+GTr5cVRXu\/VryTsd42Np8HkkBX8MSpPdamh1lAl1qdTyhL8qCrso\/qWx33jLW8CxQ2FwHFttyASsAIZ8AyYhe5xGnECcRpx4viLV6Oy9i\/27UbY34BQaI3L4OdtIJ7NnM+O013HmZxA3Dvis2an\/5Qh5pHxfRa9qF6aP44cTdw\/yv7ePNEYy6vQ9jpNvOPrmcjb8TEZZTY20gsE9zQHcl4AE5hgBnMJ66BUoHcA\/R+eitCc3LPv5UMmJ6NPolWj9Thg4nyaJL6LbUVFLm39GGWVdoa5GuLVQOmqrtNNILE\/KmgQkIIG5SwBHty06Cl2Mylra4I9G26PGk+MsWJz7G5QO5VQE96OZlu8HZLjlz1DpzxYSZ110AqrCUvnMn3URHpDAkAm0\/Q825HKZ\/RgSwMltRLHfjPZGHT++XuDy0iz0DfQZmgsuaBWe\/NLckGah7dGTUZ6wM7zyWpQZrz9DC3ptbiD9tHP\/B9oNzeo05lg3u4MAafZ5B2XIshiaBCQggblHAGeZ4ZwXoaotbxF7DJMY+e+Kfl3ywvLmsRvyIWuYN8+8JSCB+gjg4DKB6l3oblSXZTLRB9HS9V1J55TJe2W0zXQ5\/sA2wyAXocUo5cvvzG\/IYmjPRY2O7s4Je1YCEpDAOBLAyWXSUGbxtmqD53Cl9gCpHYJ6aYqpFC9lWA6lQpiPnoHWn\/6dEUSaBCQggblPAKe3Hxqk3Udm\/4laDTWc+8C9QglIQAKjQAAnvAtK08egLc0uvc4DGAV0lkECI0PADqqRuRXjUxAc8NMo7TFo3SGVeiH5Pp+RNWcOKf\/as4VxmpOi9CVk8tTUhDmueRH7mgQqIWAFUAnGyUoE55QlGfYa8lV\/h\/z3xCHeN+RyVJI9TPM5zKejDGfN0NYMQV0drYHyrYRUeteh61GGuWY28xlc\/01sNQn0RMAKoCdskxsJR5Ux98eiPJ0O0+4k8yzrcOQwC9FP3rDM8hg7opeiZ6D1UdbaKWKZJ3EpOh0dgU6Axe1sNQlIQALVE8BhZcjn\/6JRsZ9QkLFbZ54yZwTRq9AFKMtU9Gvpi8nQ1CylMeyKufo\/PFOUgASGTwDnsjm6Ho2KZRmIoX9Zq8ydobxZWjlLQ9RlXyfhrcuUybCTS2Bkvko0ubdgrK58C0qbZotRsawrH2f3pyIFwjGmyTPzCOajtLOvidKpeiXK93GvoBmllpU6yTtLY3wMvRkti+qyvUh4Z\/I7mO2H6rqeugpvuhKQwAgSwKEsj76JRs2Oo0AdH2Q4nyaXF6HPoStQFolLs0nmFaQJJrOY70CnosxqrvStgvTWQfkIzaDtYDLM+vyaBCQggd4J4EiegC4ZtAcrkN9NhMkImpbGuW1R2SaXNHPlO8R9f7mLNJ6IBvWtYbKaZUdx5Akt4XhQAhKQQBECOJFnznIto3EgT\/Cz2rw5tgI6COUD573ahUR8eRE+rcIQN0tFnN1r5hXGSwWUJi9NAksQyJeaNAkUIfDoIoGGFGaJNwCc3SqU41voX1A\/awdtSPzDSO8tqNT\/lekyfJH4m6Bh23MowEco09AW0xs2APNvTaDUH3XrJDw6IQQyIWkULesCPVQ2nFw6W\/dHO1dU2MzE\/QT6+6LpTTvajxL+BUXjDCDc3uSxzwDyMYsxImAFMEY3a8hFXeIpe8hlac4+I3ummjdwvNnfD\/1Tc4AK9lOpHEL6eZIuYrsT6E0o5RklS7\/GbqNUIMsyXAJWAMPlP065LxrhwmZWbOx56J2oDsebCvAAHGjHiVacT1PZ+9EoNrdk0ty7KWOGz2oSWMoKwD+CogSy\/swo2gMU6hqcWoaCvgPVOTN4K9J\/Bepkr+fkRp0CDPncU8m\/cHPWkMtq9jUTsAKoGfAcSv7qEb2WVACXoDTP7FhzGfP\/ZR8qm5Va5cPxdPhmotcoW9Ya+lfKmjcabcIJWAFM+B9Aicu\/jbCLS4QfVNBUANehbVGdM2wb15On+00bPxpbHGqandLRun7j2Ahvt6RsVXWSj\/BlWrRuBKwAuhHyfIPAjewUWnKhEWFA2yvIJ0tCP3dA+WVY6eYt8lqVY7PmI7QINyqHdqfS8v\/\/qNyNIZXDP4AhgR\/DbNMH8NMRLPcPKVNG6aR9flC2Bc5zZmfwBmRe6RISNV9Mlp\/esOY8TH7ECVgBjPgNGpXisahYmlpORfk4yShZKqW0a7dsl6+poGk\/T6XTbHn6H8WRP81lbN7P\/IYXNR9wf\/IIWAFM3j3v54pPJ\/Ll\/SRQcdw0\/5yLVq843W7JZajnQ28AvA2kAnpht0gjdj7\/97ef7rsYsaJZnEERsAIYFOk5kA9vAXG43xmhSzmcslyN+lnuoZfLSWdz8wqkeZouOkmsl\/zqivNEEk5lpk0oASuACb3xfVz254g7Cm8BF1KOQ6iU8sH06\/u4nl6ipkP87qaI+X5v3gLGzVJxrTZuhba81RGwAqiO5USkhMNdyIV+ZgQu9puU5c\/T5cgQ1UH2TdxAfo3ZxylC1iIax\/9LqQAG2XcSVtoIERjHP9oRwjexRTmEKz9siFd\/FHkf1JR\/nsgvaPpd9+75ZHBHUyZrsT+O\/5eyJMTKTdfh7oQRGMc\/2gm7RaN3uTx55+l3P3TWEEqXpp93UYY7m\/JOP8BJTb\/r3M2bxmnkn1FRDcuooHH8v5SObCuAxl2cwO04\/tFO4G0avUvGAS6gVPuiPH0PypLXe8j7kuYM+X0Pv3+Hmp1yc5Aq91PZzJwQ9\/AqMxhwWvqAAQMfpey8+aN0N8asLDjejMHfFZ09gKJfTB6vJM9M\/GplP+FgwtRtx1CGS2dkkkphEJXPjGz7\/rmIFG7pOxUTGFsCVgBje+tGo+A4wxMoSSqBk2ss0R9Ie2fyOrFdHpy7jnNfbne+ouN5A\/lUi7QyS3ocK4A0o93a4no8NCEErAAm5EbXeZk43\/NIfw\/0DVSlQ0lH6zfRa8mjSH\/D1wj7e1SHZbhpOp4vaZF4Kp9xrADSl5MRVJoEJCCB\/gkwszTr5ByB7kG92mIiHoueXbZExHkaquND7J8l3ZZj\/Tm+KroDjZudR4EzhFWTgAQkUA0BnMojUJYZ+Dw6E92KulnCnIW+iHZEPa+rQ9wd0HWoKvsxCT2mHR3OLYN+WVVmA0znePKa1+66PD73CTRPZ5\/7V+sVDoQAzTVZnvmECAeTpQa2Q09HmTGbYYeroDiedECmySgzeTOy5hfEzUSzvow0fk6+e5FImmw26iuxpZb6PvH3Ic1M\/mpnizmRTujntgswgsfTZBXeadrSJCABCQyGAM552aju3MhjffQ5dDcqawuI8DpU6BOThHs2StPVuFiarDap+x6YvgQkIIGhEcDJPQxth45GF6NOdjsn\/4QORJndW9gIvzpKE9a42GkU1BaAwnd4bgb0D2Bu3levapoATRxp6sjw0RNxeGuz3RKtj9Kmnw7QTCLLMM40Q52Lfk+cjI4pZcRZSPpp9npqqYjDC\/x1ypymOm2CCdgBNME3f9IvHYedpRDuxxGmDb9vI73NSOQYtE7fidWbwOkk\/zKuO8t7axNMwHkAE3zzJ\/3ScYB3V+X8w5K00pGdeQujbFnL6GCd\/yjfosGVzTeAwbGe2Jx4Mn4EDmfkmhvqKBdprs6N\/hXqd\/RRXX8vfyThHbgfGYGlTTgB+wAm\/A+gysvH+eWNclW0I9oepSM1Qz\/TEXs726tQZupmDaFLcUL3sq3d4ujJJG3+26FnoqzeGa3MuTwRp\/0\/\/QBXop+jNJHcRflKD5EkTvoCDiD+V9CoWZq6PqPzH7XbYnkkMOYEcHqboi+ga9B9qJ09wIkMQTwGZcJXoWGWveAh7TXR7igzk29CncrF6SnLDOYLUEYCbYtazv7tVJ7EQd9Go2YHUCDf+jvdPM9JQALFCeBQHo3iWG5AZe1eIvwv2rR4jt1Dkt4KaF90DurHMq7\/OPSi7rkuGYI4a6DMIB4V+xoFWWHJUvpLAhKQQI8EcChrozzJ92vnksA2PRZjiWikk6f2zATOm0ZVdj0JfQqlOauwEf5J6CI0bMvchjULF9yAEpCABDoRwKE8Dv2uQs92NWnt1CnPbueI\/2rUy5tI0cs4kYAbdytH83nCZ4bw+WhYdgoZZ3iqJgEJSKB\/AjiU1dCRNXi0q0iz9EQq4iyHPogWobrtEjJIZ3JhI\/yG6Ad1F6xF+l\/mmKt9Fr5TBpSABLoSwKl8pIWzqerQ8SSUCVqFjfD7obTXD8ouI6NnFS4gAQmfSvNLqEhHNMH6srD4HLLNv8xNMqwEJNCZAE5lY3QzqtP26lyKv56lELuiQTz5z7zeP3CgVLs64TMcdi+UuHXZL0l4Z+Ron7\/+mbgnAQlUQQDHclhdnqsp3XRadl1OgTBbonTQDsuOJeOVy3JNHJSVRtP5XZWdTEJ7oNpXWS17vYaXgATmAAGcy3roclS3pQlj707IOL8S+n7dBemSfkYa7dGpnJ3OEfcJiY9yHTeiMs1DGUKbSWffQa9ApVYv7VQuz00OAV8TJ+de932lOJmXk8gR6OF9J9Y9gayps1e72biUZWfOH9k9mdpDZGZzPlh\/da85cS3hmZnJO6Dnobz9rIjShh9lRnJWKM03krOEQ2YsH4+y+ugt5J3ZzJoEJCCBegjESaH90aDsDDLKujqzjON5+j99UAUpkM\/7ZhWyggPkm6ai+WhdtFIFSZqEBJYgkLVbNAkUIZC25fWKBKwoTJz\/Km3S2oXjT29zbhiH34KDzqcvKzWe7G9Fl6EF6LZKEzcxCUDACsA\/g6IEMjSz7YfRiyZSIlw6V5dvEz4VwChZRgNtP0oFsiwSKELACqAIJcOEQBZty0qfg7I4\/1kjWnjSTvv4JoMqRMF88v8o\/SOaBMaKgBXAWN2uoRY2SzenE3JQlk81Lm6R2dM4tnaL48M+tBmVU2UVJGnNi4Z9UeY\/twlknXRNAkUI3E2g64sErChM2rwz8mWmPZkDpZdonplIDb8fT5pPRKf2kjbOPqN91kdPmd5mVND9HM83FC5D56E\/0xfgiB9AaNUQsAKohuMkpBJnfPkAL\/Q68lqi4xNnmDfWONpRtDjw0h3BXFOa1vZCu6HNUbuO74Wcy8Juh1EJfI99TQJ9E7AJqG+Ek5HA9JNnvpQ1KLuAjFIJNFuc5SA7opvz7rafspUaqokz35I4R6HPoO1QO+fPqaUyKiqrpX6FeN9Fo9gMlnJqY0TACmCMbtYIFPUMyjDTKddRrAdI9JQWzR3pGC61Jn8dheuQZicHvkQ0HPiOHDgcvQil8ihqmSC2O\/of0nhG0UiGk0ArAlYArah4rB2BCznx23YnKzx+EWnFOc60NFmmqWVUbbkiBcNxx+l\/D\/Uzr2Jr4mdJ7nzjWJNATwSsAHrCNpmReCLPSKDPokU1E\/gGebXqb8jIoFtqzruf5G\/vFhmHne8dHIBW6xa2wPlUIJ8mzSrSKpCdQeYaASuAuXZH67+eX5LF\/9SYzTmk\/aU26WckUjpDR9GyXs+tnQqGo84bzPvQJp3ClTy3LeGzoNy8kvEMLgFnAvs3UI4AT+ZxdO9BPysXs1Do6wj1RvK4qU3ozAu4vs25YR\/OW1G3t5OtCNPXZy\/bXOS7OL5Rm3MelkBbAr4BtEXjiXYEcNB5Ct8XXdYuTA\/H40A\/Sdq\/aRd3uvK5pt35IR9P80\/bymn6CX1nwqQTt2rL7Oj0K2gSKEXACqAULgM3COCMMyLoNShNNv1anvj3QQcWSOgswtxZINyggywgwz93yHQFzv19h\/P9nnoZlcwglunut5zGHyECVgAjdDPGrShUAr+mzC9BX0ZpGurFTibSS0nrkOkn\/G5p\/JEAl3ULNITzJ1H+9FG0s6dwYoN2Jys4nklkozpJroLLM4k6CFgB1EF1gtLE6WW0zr+gf0CnojTldLOMJsoT8zvQK0ijbbPPzIQIexvHBjkhbWYRWv2+j4M\/bnWi6dj6Tft17GZ5jHXrSNg05y6BjErQJNAXAZxynH7GpB\/HNuPSX4kyy\/VR08qDxl0oi8llLsGx6KfEu5ltL5ZRSLuhpXuJXEOc80gzbzKd7HGcrPOBK80\/a3QqgOckMJOAFcBMIv7umcB0RZCn+akneiqEldlfFeXvLEMkbyZMnpb7tZ+QwI\/QK\/pNqIL4WZzto1xXt36JDNOse6hm3elXgMskRomAFcAo3Y05VhacYpx+VKmRblbJPIhEX4jSuTpMS9PP8QUKkJFTqSzq6qjN8hmjOkeiAB6DDINAna+kw7ge85wcAulv+OqQLzd9GZ+jQkq\/RDe7vFuAPs\/nzerKPtMw+oQRsAKYsBs+Vy4Xp5tlIf4TnTbEa9qfvH9WMP+zCbegYNhegp1JJCuAXshNcBybgCb45g\/z0mnCyTo2W6F0GqfDOB26f0KnoN\/h4C9g29EIcx3pvI1Ax6DHdgxc\/cmjSHJ\/ypCmlyJ2O4FSWexdJHAPYY6jLHkL0CQgAQmMJgEc9jLoNehqlLb8mZZjN6MPokKzZgm3K7oRDcp+SUbzyxImzg5oUQ2FXEiam5Ytj+ElIAEJDIwATuqJ6Cj0ACpiJxAobwhdjXDPQ5cUSbTPMN8n\/ppdC9QiAPGWRT\/sM\/9W0ffjYF2dyy2uxEMSkIAEShDAQT0MxXmWtTxtr1YkK8Jtic4om0HB8PcS7mC0SpGytAtD\/OegBagqO5OEnAHcDrjHJSCB4RPASb0SLe7R6+1PvEIDFgi3Nvosuh5VZeeQ0J6okj4z0kmT1Z2oX0sfyHOHf3ctgQQkIIE2BHBS89GFfXi79AkUagpqFIHwW6AvodtQrxbH\/3ZU+Qxb0kyFGAfeq+VNZ7vG9bqVgAQkMJIEcFQ79erlmuK9pezFEfeRaHO0L\/otugPlLaRV5\/N9HE8H7TUo39vdHWWkUm1G+i9Gp6OifSIEfTDl\/AWy07e2OzM5CVfySjs5uLzSHgls1mO85mib4fQezlDHzKYtZIRdTMDTI+J+mm1W43w6yro80VpoEboC5WM0GUefCWY3lhjeSfDejDyOo1xZNuPN6NXoCWh51Moy2ex89HV0KHFTbk0CfRFw7ZC+8Bm5G4E4bcJkzPxO3cJ2OR9HvjWO7+4u4Wo5zXWk83cllPWMMqa\/UiP9dHSncsqTfSqm1VEqu2vRVSgTvU7T8UNBq4yAbwCVoTShNgTSeVvFJK2kUagjuE05Ch\/GGWdSWkbWvAxtj9ZGeTLPksv3cD6rmuZt4afoOLQQx5xlIXo24uejOCdMaynyWI79B3X4PSM1ogQkMGwCOLIM\/\/xv1K8dTwJxwLUaeWyHvofSX9DN0nZ\/EzoMbVVrwUxcAhKQwDgSwDm+CfVrHyeB2posSXtj9G3U60zdVBhfQeuP4z2yzBKQgARqIYBT3BqVGelC8Fm2ay2FI1Fyeh7646wcezvwe6JtVldZTVcCEpDAWBHAIa6MvtubP52KVdtsV1LfHmVdoirtYhJ7xljdJAsrAQlIoC4COMQ0sfTiaG8m3svrKFecNLoc1WGZRPakOsptmhKQgATGjgAO8Z2oTBt7Jj0diCof\/UOaq6KTUJ32fyS+4tjdKAssAQlIoA4COMRXo\/MLeN0scfw2VPkql6Q5D70FDcL2rYOjaUpAAhIYSwJ43XXQp9Ef0F2oYekoPgt9GdXWhk7aG6E\/o0HYRWSyzljeKAs95wnUNqxuzpPzAvsigFPMJMQsspYZsE9GmXyVpQ7yYfNMrLqHbS1G3h8g4Y\/WkvjsRB\/k0Nu4noNnn\/KIBCQgAQkMjADOfxn0JzRIO5LMVh7YRZqRBAoSqLxzrWC+BpPAsAg8jYwHPTony0nMH9YFm68E2hGwAmhHxuMjQYAn56VRPqWYJ\/cq1q6KM05z0yAtT\/+peDQJjBSBKv5DjdQFWZjxJ4CjT6dpntLztassrZCVMbPY2jWcO4\/tr9H5tKvfyrasZY3\/YfR9zS9bUMNLoG4CVgB1Ezb9wgRw7lnx850oq3B2aqZJB\/FphP8W269SEWTZ5KKWVT6HYWtSXoo6L53CmgQkIAEJNAjgHLdFp6AylqWZs4Bb3hAKGWF\/VSaDCsN+n7Qqn9NQ6KINJIE2BOwDaAPGw4MjgGPcmdyOQFuWzDXLQ+dLWkeQRqc3huZks5b\/MCwfkfHpfxjkzbMtASuAtmg8MQgCOO6tyedrqPBTfItybcuxvAkU+Xh7vq41DLuK5p8HhpGxeUqgHQErgHZkPF47ARz2WmRyIMrnFvu1Z5LAe0mzWwfvtf1m1GP8a3qMZzQJ1EbACqA2tCZcgMBrCVPll7TeSHqpCDrZbzhZptO4U1pFz+Xj9GcUDWw4CQyKgBXAoEibzxIEeFLPUM+3L3Gw\/x\/5ju6\/dUkmQ0iv7BKm6tO\/JcGLqk7U9CTQLwErgH4JGr9XAs8nYpE2+7LpZ43\/rC3Uzu7kRD7mPkj7BZndMMgMzUsCRQhYARShZJg6CLyQRLu11\/eSbyqV7dpFnO6IPZTzt7ULU\/HxG0nvaDuAK6ZqcpUQsAKoBKOJlCHAE3omIK5fJk6JsMsQttuQ0D8Q5gsl0uwn6OE4f9v\/+yFo3NoIWAHUhtaEOxBYiXPLdzjf76mOo4pwyOmUPRRd3m9GXeJfxvmMctIkMJIErABG8rbM+UItyxXWuQxJ3gI6GpXAhQR4L1rUMWDvJ28m6lvI55LekzCmBOolYAVQL19Tb00g7e93tz5VydFC7fs45\/8ht\/eg+yrJ9a+J5NreSvo\/\/ush9yQwegSsAEbvnkxCiTISJ6rLyoy4SV\/A+1GhSqNAgW8hzNvQ9wqENYgEJCCBySNAR\/DnUB12K4m+sixR4uyCzu6zQKcS\/wVl8za8BCQggYkigKPcHi3u0+G2ip6PynfsBG4HmnhroH3RxaiMnUfgt6Ke8m1XHo9LQAISmJMEcJbLod+gqu0j\/QKjQPPR7ugodB3KW8WdaNH0Nr\/zcZrvop3Ruv3maXwJDIPAvGFkap4SCAEcZz78cjjKss5V2GUk8mw6XxdWkRjly\/+PFdDj0NooT\/g3oSwlcR26i7xc4hkQmgQkIIFSBHCw+dbvAagKu4tEdilVAANLQAISkMDwCOC0V0En9VkDPED8g5Cj2oZ3K815DAnYBDSGN22uFRnHnQ+1fwllfaCylolcn0D\/QXNMvhVc2Mh3TQKvjFZES6O7UL7ctZC0qhoWSnKaBCQgAQm0JYAzXgntg9LpWtTyYfid2iba4gThH4\/ejA5DGTF0Nbob3Y9uQZehX6MMU90R+VbRgqOHJCABCVROAIe7KfoUOh\/dgTJUNM75PpRROLehjB76Z\/T4ogUgbEYdvRqdg4oOP72BsEeiZxXNx3ASGCcCNgGN092aoLLidPNxl3zdaz7K94LvRdei89G5NNEU\/qoXaW1EnIPQi1AvllnLH0AHl21m6iUz40hAAhKQQAUEcP5bo7ITu4gyy9LR\/B302AqKZRISkIAEJFAnAZz15ugCVKV9i8QeXme5TVsCEpCABPoggJNeHdUx0ziVSfofrAT6uD9GlYAEJFAbARz0V+Kpa7KbSHeb2gpvwhKQgAQk0BsBnPPT0PU1Of9GskewU+dHbXq7eGNJoAQBxziXgGXQ0Scw7ZR3o6SPqbm0LyX9rWvOw+QlUCsBK4Ba8Zr4EAisRZ5xznVbZg6\/pu5MTF8CdRKwAqiTrmkPg8DGZPqUAWX8TN44HjWgvMxGApUTsAKoHKkJDpnAVuQ\/qL\/rrCW0wZCv1+wl0DOBQf1H6bmARpRAUQI8jefveZAfZ8nT\/6OLls9wEhg1AlYAo3ZHLE8\/BPL3vEY\/CZSMm+UqspqoJoGxJGAFMJa3zUK3IZC1rZZvc66Ow8mvqq+Z1VE+05RARwJWAB3xeHLMCDxAebNg3KBsMRndOqjMzEcCVROwAqiaqOkNk0AqgHyrd1CWD8hYAQyKtvlUTsAKoHKkJjgsAizVnA+0nzPA\/G8mr3wgXpPAWBKwAhjL22ahOxD4HecWdjhf5alzqHSuqDJB05LAIAlYAQyStnkNgkAc8kmDyIg8jh9QPmYjgVoIWAHUgtVEh0WAJ\/J8zP0IlC+I1WmXkfjhdWZg2hKQgAQkUJIAE8JWQPmwe522d8liGVwCEpCABAZBAM\/\/YnRnTTXAj0h31UFch3lIQAISkEAPBHDS+6J7K64ELie9TXoojlEkIAEJSGBQBHDUy6D3o\/tRFRbnv8Ogym8+EpCABCTQBwEc9tLovajf5qBTSCMrjWoSkIAEJDBOBHDeL0e\/RGXtRiJ8Da0zTtdrWSUgAQlIoIkATnx5tAfK93zzYfdOdgEn\/wv51N\/E0N25RSCrGWoSmCgCOPWs459PR26JnoDydJ9VRDODOEs7nIWypMRV08tLsKtJQAISkIAEJCABCUhAAhKQgAQkIAEJSEACEpCABCQgAQlIQAISkIAEJCABCUhAAhKQgAQkIAEJSEACEpCABCQgAQlIQAISkIAEJCABCUhAAhKQgAQkIAEJSEACEpCABCQgAQlIQAISkIAEJCABCUhAAhKQgAQkIAEJSEACEpCABCQgAQlIQAISkIAEJCABCUhAAhKQgAQkIAEJSEACEpCABCQgAQlIQAISkIAEJCABCUhAAhKQgAQkIAEJSEACEpCABCQgAQlIQAISkIAEJCABCUhAAhKQgAQkIAEJSEACEpCABCQgAQlIQAISkIAEJCABCUhAAhKQgAQkIAEJSEACEpCABCQgAQlIQAISkIAEJCABCUhAAhKQgAQkIAEJSEACEpCABCQgAQlIQAISkIAEJCABCUhAAhKQgAQkIAEJSEACEpCABCQgAQlIQAISkIAEJCABCUhAAhKQgAQkIAEJSEACEpCABCQgAQlIQAISkIAEJCABCUhAAhKQgAQkIAEJSEACEpCABCQgAQlIQAISkIAEJCABCUhAAhKQgAQkIAEJSEACEpCABCQgAQlIQAISkIAEJCABCUhAAhKQgAQkIAEJSEACEpCABCQgAQlIQAISkIAEJCABCUhAAhKQgAQkIAEJSEACEpCABCQgAQlIQAISkIAEJCABCUhAAhKQgAQkIAEJSEACEpCABCQgAQlIQAISkIAEJCABCUhAAhKQgAQkIAEJSEACEpCABCQgAQlIQAISkIAEJCABCUhAAhKQgAQkIAEJSEACEpCABCQgAQlIQAISkIAEJCABCUhAAhKQgAQkIAEJSEACEpCABCQgAQlIQAISkIAEJCABCUhAAhKQgAQkIAEJSEACEpCABCQgAQlIQAISkECtBP4\/73xiRW3LU18AAAAASUVORK5CYII=",
      "BTTStreamDeckIconType": 1,
      "BTTStreamDeckAlternateImageHeight": 50,
      "BTTStreamDeckIconColor1": "255.000000, 255.000000, 255.000000, 255.000000",
      "BTTStreamDeckAlternateIconColor1": "255, 255, 255, 255",
      "BTTStreamDeckIconColor2": "255, 255, 255, 255",
      "BTTStreamDeckAlternateIconColor2": "255, 255, 255, 255",
      "BTTStreamDeckTextOffsetX": 0,
      "BTTStreamDeckAlternateIconColor3": "255, 255, 255, 255",
      "BTTStreamDeckAlternateBackgroundColor": "255.000000, 224.000002, 97.000002, 255.000000",
      "BTTStreamDeckAlternateCornerRadius": 12,
      "BTTStreamDeckAttributedTitle": "cnRmZAAAAAADAAAAAgAAAAcAAABUWFQucnRmAQAAAC6YAAAAKwAAAAEAAACQAAAAe1xydGYxXGFuc2lcYW5zaWNwZzEyNTJcY29jb2FydGYyNjM5Clxjb2NvYXRleHRzY2FsaW5nMFxjb2NvYXBsYXRmb3JtMHtcZm9udHRibH0Ke1xjb2xvcnRibDtccmVkMjU1XGdyZWVuMjU1XGJsdWUyNTU7fQp7XCpcZXhwYW5kZWRjb2xvcnRibDs7fQp9AQAAACMAAAABAAAABwAAAFRYVC5ydGYQAAAAc5rBYrYBAAAAAAAAAAAAAA==",
      "BTTStreamDeckSFSymbolName": "folder.fill",
      "BTTStreamDeckIconColor3": "255, 255, 255, 255"
    }
  }]
}

