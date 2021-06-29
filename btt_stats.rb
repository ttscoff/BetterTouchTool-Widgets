#!/usr/bin/env ruby
# frozen_string_literal: true

# Memory, CPU, and other stats formatted to use in a BetterTouchTool touch bar
# script widget Also works in menu bar (Other Triggers), but be sure to select
# "Use mono space font."
require 'optparse'
require 'yaml'
require 'fileutils'
require 'json'
require 'shellwords'
config = '~/.config/bttstats.yml'

# Settings
defaults = {
  raw: false,
  bar_width: 8,
  colors: {
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
  }
}
config = File.expand_path(config)
if File.exist?(config)
  yaml = IO.read(config)
  user_config = YAML.load(yaml)
  settings = defaults.merge(user_config)
else
  settings = defaults
  yaml = YAML.dump(settings)
  FileUtils.mkdir_p(File.dirname(config)) unless File.directory?(File.dirname(config))
  File.open(config, 'w') do |f|
    f.puts yaml
  end
end

# defaults
options = {
  percent: false,
  mem_free: false,
  averages: [1, 5, 15],
  color_indicator: 1,
  top: false,
  background: false,
  truncate: 0,
  spacer: nil,
  split_cpu: false,
  width: settings[:bar_width],
  prefix: '',
  suffix: '',
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: #{File.basename(__FILE__)} [options] [subcommand]"
  opts.separator 'Subcommands (* = default):'
  opts.separator '    cpu*'
  opts.separator '    memory'
  opts.separator '    ip [lan|wan*]'
  opts.separator '    network [interface|location*]'
  opts.separator '    doing'
  opts.separator '    refresh [key:path ...]'
  opts.separator ''
  opts.separator "To add buttons automatically, use: #{File.basename(__FILE__)} add [touch|menu] [type]"
  opts.separator '    where type is one of cpu, memory, lan, wan, interface, location, or doing'
  opts.separator ''
  opts.separator 'Options:'


  opts.on('-a', '--averages AVERAGES',
          'Comma separated list of CPU averages to display (1, 5, 15), default all') do |c|
    options[:averages] = c.split(/,/).map(&:to_i)
  end

  opts.on('-c', '--color_from AVERAGE', 'Which CPU average to get level indicator color from (1, 5, 15)') do |c|
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

def rgba_to_btt(color)
  elements = color.match(/rgba?\((?<r>\d+), *(?<g>\d+), *(?<b>\d+)(?:, *(?<a>[\d.]+))?\)/)
  alpha = elements['a'] ? 255 * elements['a'].to_f : 255
  %(#{elements['r']},#{elements['g']},#{elements['b']},#{alpha.to_i})
end

def hex_to_btt(color)
  rgb = color.match(/^#?(..)(..)(..)$/).captures.map(&:hex)
  "#{rgb.join(',')},255"
end

def color_to_btt(color)
  color = color.strip.gsub(/ +/, '').downcase
  case color
  when /^rgba?\(\d+,\d+,\d+(,(0?\.\d+|1(\.0+)?))?\)$/
    rgba_to_btt(color)
  when /^#?[a-f0-9]{6}$/
    hex_to_btt(color)
  else
    '25,25,25,255'
  end
end

def match_key(table, key)
  result = nil
  expanded_key = key
  table.each do |k, v|
    if k =~ /^#{key.downcase}/
      expanded_key = k
      result = v
      break
    end
  end
  [expanded_key, result]
end

def available_commands(table, key = nil)
  type = key.nil? ? '' : "#{key} "
  puts "Available #{type}commands:"
  table.each do |k, v|
    if v.key?(:title)
      puts %(#{type}#{k} - #{v[:title]})
    else
      v.each do |subk, subv|
        puts "#{type}#{k} #{subk} - #{subv[:title]}"
      end
    end
  end
end

def data_for_command(cmd)

  table = {
    'cpu' => {
      'bar' => { title: 'CPU Bar', command: 'cpu -c 1 --top -i', fontsize: 10, monospace: 1 },
      'double' => { title: 'CPU Split Bar', command: 'cpu -c 1 --top -i --split_cpu', fontsize: 8, monospace: 1, baseline: -4 },
      'percent' => { title: 'CPU Percent, 1m avg', command: 'cpu -c 1 --top -i -p -a 1', fontsize: 15 }
    },
    'memory' => {
      'bar': { title: 'Memory', command: 'mem -i', fontsize: 10, monospace: 1 },
      'percent': { title: 'Memory', command: 'mem -ip', fontsize: 10, monospace: 1 }
    },
    'ip' => {
      'lan' => { title: 'LAN IP', command: 'ip lan' },
      'wan' => { title: 'WAN IP', command: 'ip wan' }
    },
    'network' => {
      'location' => { title: 'Network Location', command: 'network location' },
      'interface' => { title: 'Network Interface', command: 'network interface' }
    },
    'doing' => {
      title: 'Doing',
      command: 'doing --truncate 45 --prefix " " -i --empty "…"',
      sfsymbol: 'checkmark.circle'
    }
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
    key += key_name
  end

  unless data.key?(:title)
    available_commands(data, key)
    Process.exit 1
  end

  warn "Button type not found: #{cmd.join(' ')}" if data.nil?

  data
end

# Hash methods
class Hash
  def to_btt_url(method)
    query = CGI.escape(to_json).gsub(/\+/, '%20')
    %(btt://#{method}/?json=#{query})
  end

  def to_btt_as(method)
    query = to_json.gsub(/\\"/, '\\\\\\\\"').gsub(/"/, '\\\\"')
    %(tell application "BetterTouchTool" to #{method} "#{query}")
  end
end

def osascript(script)
  `/usr/bin/osascript -e #{Shellwords.escape(script)}`
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
      'BTTTouchBarItemSFSymbolDefaultIcon' => "#{specs[:sfsymbol]}",
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
end

def add_touch_bar_button(specs)
  specs[:fontsize] ||= 15
  specs[:sfsymbol] ||= ''
  data = {
    'BTTWidgetName' => specs[:title],
    'BTTTriggerType' => 642,
    'BTTTriggerTypeDescription' => 'Shell Script \/ Task Widget',
    'BTTTriggerClass' => 'BTTTriggerTypeTouchBar',
    'BTTShellScriptWidgetGestureConfig' => '\/bin\/sh:::-c:::-:::',
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
      'BTTTouchBarOnlyShowIcon' => false,
    }
  }
  script = data.to_btt_as('add_new_trigger')
  osascript(script)
end

def btt_action(action)
  `/usr/bin/osascript -e 'tell app "BetterTouchTool" to #{action}'`
end

def refresh_widget(key, v)
  if v.is_a? Hash
    warn "--- Refreshing all widgets in #{key}"
    v.each do |k, val|
      refresh_widget("#{key}:#{k}", val)
    end
  elsif v.is_a? Array
    v.each do |uuid|
      warn "Refreshing #{key}: #{uuid}"
      btt_action(%(refresh_widget "#{uuid}"))
    end
  else
    warn "Refreshing #{key}: #{v}"
    btt_action(%(refresh_widget "#{v}"))
  end
end

color = ''
font_color = ''
chart = ''

case ARGV[0]
when /^add/
  ARGV.shift
  unless ARGV[0] =~ /^(touch|menu)/
    warn "First argument must be 'touch' or 'menu'"
    warn "Example: #{File.basename(__FILE__)} add touch ip lan"
    data_for_command(nil)
    Process.exit 1
  end
  type = ARGV[0] =~ /^touch/ ? 'touchbar' : 'menubar'
  ARGV.shift
  data = data_for_command(ARGV)
  Process.exit 1 if data.nil?

  if type == 'touchbar'
    add_touch_bar_button(data)
  else
    add_menu_bar_button(data)
  end
  puts "#{type == 'touchbar' ? 'Touch Bar' : 'Menu Bar'} widget added."
  puts 'You may need to restart BetterTouchTool to see the button in your configuration.'
  Process.exit 0
when /^refresh/
  unless settings.key?(:refresh)
    warn 'No :refresh key in config'
    warn 'Config must contain \':refresh\' section with key/value pairs'
    Process.exit 1
  end

  refresh = settings[:refresh]
  ARGV.shift
  warn 'No key provided' unless ARGV.length.positive?

  if ARGV.length == 0
    warn '--- Refreshing all widgets'
    refresh.each do |k, v|
      refresh_widget(k, v)
    end
  else
    ARGV.each do |arg|
      keypath = arg.split(/:/)

      while keypath.length.positive?
        key = keypath[0]
        if refresh.is_a? String
          break
        elsif refresh.respond_to?(:key?) && refresh.key?(key)
          refresh = refresh[key]
        else
          warn "Refresh config does not contain key path #{arg}"
          Process.exit 1
        end

        keypath.shift
      end

      refresh_widget(arg, refresh)
    end
  end

  Process.exit 0
when /^net/
  options[:background] = false
  chart = case ARGV[1]
          when /^i/ # Interface
            `osascript -e 'tell app "System Events" to tell current location of network preferences to get name of first service whose active is true'`.strip
          else # Location
            `osascript -e 'tell app "System Events" to get name of current location of network preferences'`.strip
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
  chart = `/usr/local/bin/doing view btt`.strip
  colors = settings[:colors][:activity]
  color = color_to_btt(chart.length.positive? ? colors[:active][:bg] : colors[:inactive][:bg])
  font_color = color_to_btt(chart.length.positive? ? colors[:active][:fg] : colors[:inactive][:fg])
when /^mem/
  mem_free = `memory_pressure | tail -n 1 | awk '{ print $NF; }' | tr -d '%'`.to_i
  mem_used = 100 - mem_free
  memory = options[:mem_free] ? mem_free : mem_used

  if options[:percent]
    chart = "#{memory}%"
  else
    unit = (options[:width].to_f / 100)

    chart_arr = Array.new(options[:width], '░')
    chart_arr.fill('█', 0, (unit * memory).to_i)

    chart = chart_arr.join('')
  end

  color = ''
  settings[:colors][:severity].each do |c|
    if mem_used <= c[:max]
      font_color = color_to_btt(c[:fg])
      color = color_to_btt(c[:bg])
      break
    end
  end
else
  cores = `sysctl -n hw.ncpu`.to_i
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

  curr_load = ((indicator.to_f / cores) * 100).to_i
  curr_load = 100 if curr_load > 100

  if options[:percent]
    chart = loads.map { |ld| "#{((ld.to_f / cores) * 100).to_i}%" }.join('|')
  else
    unit = (options[:width].to_f / 100)

    if options[:split_cpu]
      chart1 = Array.new(options[:width], '░')
      this_load = ((loads[0].to_f / cores) * 100)
      this_load = 100 if this_load > 100
      chart1.fill('█', 0, (unit * this_load).to_i)
      chart = chart1.join('')

      avg5_load = (((loads[1].to_f / cores) * 100) * unit).to_i
      avg5_load = 100 if avg5_load > 100
      avg15_load = (((loads[2].to_f / cores) * 100) * unit).to_i
      avg15_load = 100 if avg15_load > 100
      chart2 = []
      options[:width].times do | i |
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
      chart = chart1.join('') + '\\n' + indent + chart2.join('')
    else
      chart_arr = Array.new(options[:width], '░')
      fills = %w[▒ ▓ █].reverse.slice(0, loads.length).reverse
      loads.reverse.each_with_index do |ld, idx|
        this_load = ((ld.to_f / cores) * 100)
        this_load = 100 if this_load > 100
        chart_arr.fill(fills[idx], 0, (unit * this_load).to_i)
      end

      chart = chart_arr.join('')
    end

  end

  if options[:background]
    settings[:colors][:severity].each do |c|
      if curr_load <= c[:max]
        color = color_to_btt(c[:bg])
        font_color = color_to_btt(c[:fg])
        break
      end
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
  out += options[:background] ? %(,\"background_color\":\"#{color}\",\"font_color\":\"#{font_color}\"}) : '}'
  print out
end
