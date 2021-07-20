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
  opts.separator '    add [touch|menu] COMMAND'
  opts.separator ''
  opts.separator "To add buttons automatically, use: #{File.basename(__FILE__)} add [touch|menu] [type]"
  opts.separator '    where type is one of cpu, memory, lan, wan, interface, location, or doing'
  opts.separator ''
  opts.separator 'Options:'


  opts.on('-a', '--averages AVERAGES',
          'Comma separated list of CPU averages to display (1, 5, 15), default all') do |c|
    options[:averages] = c.split(/,/).map(&:to_i)
  end

  opts.on('-c', '--color_from AVERAGE', 'Which CPU average to get level indicator color from (1, 5, 15), default 1') do |c|
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
    },
    'close' => {
      title: 'Touch Bar Close Button'
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

def add_touch_bar_close_button
  button = {"BTTTouchBarButtonName"=>"X", "BTTTriggerType"=>629, "BTTTriggerTypeDescription"=>"Touch Bar button", "BTTTriggerClass"=>"BTTTriggerTypeTouchBar", "BTTPredefinedActionType"=>191, "BTTPredefinedActionName"=>"Close currently open Touch Bar group", "BTTEnabled2"=>1, "BTTEnabled"=>1, "BTTModifierMode"=>0, "BTTOrder"=>0, "BTTDisplayOrder"=>-1, "BTTMergeIntoTouchBarGroups"=>0, "BTTIconData"=>"iVBORw0KGgoAAAANSUhEUgAAAIAAAACACAYAAADDPmHLAAAK4GlDQ1BJQ0MgUHJvZmlsZQAASImVlwdUU8kagOfe9JDQEiKd0JsgnQBSQg+9N1EJSSChhJAQVOzI4gquIiIiqAi4KqLg6grIWhALFkSxYV+QRUFZFws2VPYCj7C777z3zvvvmTvf+fPPX+bM5PwXAHIQWyTKgBUByBTmiCP8POlx8Ql03CDAARjgARHoszkSETMsLAggMjP_Xd7fBdDkfMti0te___5fRZnLk3AAgBIRTuZKOJkItyPjFUckzgEAdQTR6y_JEU3ybYSpYiRBhIcmOXWav0xy8hSjFadsoiK8EDYAAE9is8WpAJCsED09l5OK+CGFIWwl5AqECK9B2I3DZ3MRRuKCuZmZWZM8grAJYi8CgExFmJH8F5+pf_OfLPPPZqfKeLquKcF7CySiDPay_3Nr_rdkZkhnYhghg8QX+0cgMw3Zv3vpWYEyFiaHhM6wgDtlP8V8qX_0DHMkXgkzzGV7B8rWZoQEzXCKwJcl85PDipphnsQncobFWRGyWCliL+YMs8WzcaXp0TI9n8eS+c_jR8XOcK4gJmSGJemRgbM2XjK9WBohy58n9POcjesrqz1T8pd6BSzZ2hx+lL+sdvZs_jwhc9anJE6WG5fn7TNrEy2zF+V4ymKJMsJk9rwMP5lekhspW5uDHM7ZtWGyPUxjB4TNMPAGPiAIeeggGtgCG2ANnEA4ADm8pTmTxXhliZaJBan8HDoTuXE8OkvIsZxLt7GysQZg8v5OH4m34VP3EqJ1zeqy9iBHeQy5MyWzuuTtALSsB0D1_qzOoBoAhQIAms9xpOLcaR168oVB_hMUABWoAW2gD0yABZKdA3ABHkjGASAURIF4sAhwAB9kAjFYAlaAtaAQFIMSsA1UgmpQBw6Aw+AoaAEnwVlwEVwFN8Ad8BD0gUHwEoyC92AcgiAcRIYokBqkAxlC5pANxIDcIB8oCIqA4qEkKBUSQlJoBbQOKoZKoUqoBqqHfoJOQGehy1APdB_qh4ahN9BnGAWTYCqsBRvB82AGzIQD4Sh4IZwKZ8N5cAG8Ca6Aa+FDcDN8Fr4K34H74JfwGAqg5FA0lC7KAsVAeaFCUQmoFJQYtQpVhCpH1aIaUW2oTtQtVB9qBPUJjUVT0HS0BdoF7Y+ORnPQ2ehV6I3oSvQBdDP6PPoWuh89iv6GIWM0MeYYZwwLE4dJxSzBFGLKMfswxzEXMHcwg5j3WCyWhjXGOmL9sfHYNOxy7EbsLmwTth3bgx3AjuFwODWcOc4VF4pj43JwhbgduEO4M7ibuEHcR7wcXgdvg_fFJ+CF+Hx8Of4g_jT+Jv45fpygSDAkOBNCCVzCMsJmwl5CG+E6YZAwTlQiGhNdiVHENOJaYgWxkXiB+Ij4Vk5OTk_OSS5cTiC3Rq5C7ojcJbl+uU8kZZIZyYuUSJKSNpH2k9pJ90lvyWSyEdmDnEDOIW8i15PPkZ+QP8pT5C3lWfJc+dXyVfLN8jflXykQFAwVmAqLFPIUyhWOKVxXGFEkKBopeimyFVcpVimeUOxVHFOiKFkrhSplKm1UOqh0WWlIGadspOyjzFUuUK5TPqc8QEFR9CleFA5lHWUv5QJlkIqlGlNZ1DRqMfUwtZs6qqKsYqcSo7JUpUrllEofDUUzorFoGbTNtKO0u7TPc7TmMOfw5myY0zjn5pwPqhqqHqo81SLVJtU7qp_V6Go+aulqW9Ra1B6ro9XN1MPVl6jvVr+gPqJB1XDR4GgUaRzVeKAJa5ppRmgu16zT7NIc09LW8tMSae3QOqc1ok3T9tBO0y7TPq09rEPRcdMR6JTpnNF5QVehM+kZ9Ar6efqorqauv65Ut0a3W3dcz1gvWi9fr0nvsT5Rn6Gfol+m36E_aqBjEGywwqDB4IEhwZBhyDfcbthp+MHI2CjWaL1Ri9GQsaoxyzjPuMH4kQnZxN0k26TW5LYp1pRhmm66y_SGGWxmb8Y3qzK7bg6bO5gLzHeZ98zFzHWaK5xbO7fXgmTBtMi1aLDot6RZBlnmW7ZYvppnMC9h3pZ5nfO+WdlbZVjttXporWwdYJ1v3Wb9xsbMhmNTZXPblmzra7vattX2tZ25Hc9ut909e4p9sP16+w77rw6ODmKHRodhRwPHJMedjr0MKiOMsZFxyQnj5Om02umk0ydnB+cc56POf7hYuKS7HHQZmm88nzd_7_wBVz1XtmuNa58b3S3JbY9bn7uuO9u91v2ph74H12Ofx3OmKTONeYj5ytPKU+x53PODl7PXSq92b5S3n3eRd7ePsk+0T6XPE18931TfBt9RP3u_5X7t_hj_QP8t_r0sLRaHVc8aDXAMWBlwPpAUGBlYGfg0yCxIHNQWDAcHBG8NfhRiGCIMaQkFoazQraGPw4zDssN+CceGh4VXhT+LsI5YEdEZSYlcHHkw8n2UZ9TmqIfRJtHS6I4YhZjEmPqYD7HesaWxfXHz4lbGXY1XjxfEtybgEmIS9iWMLfBZsG3BYKJ9YmHi3YXGC5cuvLxIfVHGolOLFRazFx9LwiTFJh1M+sIOZdeyx5JZyTuTRzlenO2cl1wPbhl3mOfKK+U9T3FNKU0ZSnVN3Zo6zHfnl_NHBF6CSsHrNP+06rQP6aHp+9MnMmIzmjLxmUmZJ4TKwnTh+SztrKVZPSJzUaGoL9s5e1v2qDhQvE8CSRZKWnOoSKPUJTWRfiftz3XLrcr9uCRmybGlSkuFS7uWmS3bsOx5nm_ej8vRyznLO1borli7on8lc2XNKmhV8qqO1fqrC1YPrvFbc2AtcW362mv5Vvml+e_Wxa5rK9AqWFMw8J3fdw2F8oXiwt71Luurv0d_L_i+e4Pthh0bvhVxi64UWxWXF3_ZyNl45QfrHyp+mNiUsql7s8Pm3SXYEmHJ3S3uWw6UKpXmlQ5sDd7aXEYvKyp7t23xtsvlduXV24nbpdv7KoIqWncY7CjZ8aWSX3mnyrOqaafmzg07P+zi7rq522N3Y7VWdXH15z2CPfdq_Gqaa41qy+uwdbl1z_bG7O38kfFj_T71fcX7vu4X7u87EHHgfL1jff1BzYObG+AGacPwocRDNw57H25ttGisaaI1FR8BR6RHXvyU9NPdo4FHO44xjjX+bPjzzuOU40XNUPOy5tEWfktfa3xrz4mAEx1tLm3Hf7H8Zf9J3ZNVp1RObT5NPF1weuJM3pmxdlH7yNnUswMdizsenos7d_t8+PnuC4EXLl30vXiuk9l55pLrpZOXnS+fuMK40nLV4Wpzl33X8Wv21453O3Q3X3e83nrD6UZbz_ye0zfdb5695X3r4m3W7at3Qu703I2+e683sbfvHvfe0P2M+68f5D4Yf7jmEeZR0WPFx+VPNJ_U_mr6a1OfQ9+pfu_+rqeRTx8OcAZe_ib57ctgwTPys_LnOs_rh2yGTg77Dt94seDF4EvRy_GRwt+Vft_5yuTVz394_NE1Gjc6+Fr8euLNxrdqb_e_s3vXMRY29uR95vvxD0Uf1T4e+MT41Pk59vPz8SVfcF8qvpp+bfsW+O3RRObEhIgtZk+1AihkwCkpALzZj_TH8QBQbgBAXDDdX08JNP1NMEXgP_F0Dz4lDgDU9QIQtRyAoGsA7KhEWlrEvwLyXRBGRvROALa1lY1_iSTF1mbaFwnp_TBPJibeIn0wbisAX0smJsZrJya+1iHJPgKgXTjd10+K4iEAamyt7G2CHmhdBf+U6Z7_LzX+cwaTGdiBf85_AjAQG5JmGvd9AAAAbGVYSWZNTQAqAAAACAAEARoABQAAAAEAAAA+ARsABQAAAAEAAABGASgAAwAAAAEAAgAAh2kABAAAAAEAAABOAAAAAAAAAJAAAAABAAAAkAAAAAEAAqACAAQAAAABAAAAgKADAAQAAAABAAAAgAAAAAAipO1xAAAACXBIWXMAABYlAAAWJQFJUiTwAAAcvklEQVR4Ae3baaxtZX3HcbVVKg6ADPfCHc5RKoJorUUK2AqJNg7VpPquidHa+qJKTNPalsbXTYe0aewLgzaxbVobm_RF00QM2NEKLSDWOjB4FfScOwMXRAQcO_w+++7_zXMX+wz77LX3Oeey_8n3rmevtfZ6nuf3H55n7QNPe9rc5grMFZgrMFdgrsBcgbkCcwXmCswVmCswV2CuwFyBuQJzBeYKzBWYKzBX4BRX4OmnyPzM40fCM8KzhscfzdH5Orruc0s+nrD_S6vlf4aff9gc_zft7wfHup7m9jXinArGubvCc8JLw3PDQnh2OD_8WDg3PDO4x7xPCwKGcej3Amc_Fn4QjoXvhiPhibAcXLs7PB4OB_dva9tuAVAZzeGcWkdZvydw_OLwuFoA1PfaAOBsWV0B4FnOefZ3gr5dEwyOnqEa1PfcI5CqYqS59c2ktpPJ4BeGM8LV4exwZXheOC8I6HYJ4GCOMs86ltO7c1f+GSdqV4kvhzq6xukqxAPh2+G2oFp8JnwrLAfXt4Vt9QrASZXpSre2zD4zLAYB4ChbXxA4eaOmL1YBIthWMsFxehAAR4P+94dHAuerCqqE+ywtFVxpbi2rSW+tUR0fjbFx+GVBdr81nBMuDtZ2cJZ7HCdxfr4+tnGuitAuAdr2CCrCPwRV4r+D81syCLZaBeB0mceZyrzMkvECYDHI+F1BmV_LOIe1JZwTWgY3DP_RdwttfC6NqjIMbx+M0TirUqhKlgcbRONeDIL0_uCc5UHQqBBbJhhMcCsZx14YdoRfGR4vyZGQloASfK1xc75NGYfYxctAR59HlWbP81bg+ZxnHPX24OizMXSDIKdOMo7lYI7mdGO4KwiCvwgqwteDcWwJq+jezMEQn7A2ctbVvWFnWAwyXzCslPElOIdzMuGJ6_josH04x40EgLXb8uJ5+n9+ECDajrX0qAAVkI41VgFTAefeheBoXE8E+wfj3tRqUAPPODbFSjDl8+1hd_j5oPxjrYwn8H3hkXBr+GaQcbJ8KbheJbeWAoIXaZ4wY2mpJYCDOXUxCNJLw1nh1cEYXxTK6WmeZPqpimCMloFPhoPh48G5Gl+as7fNqgCELueem7bN3UIQABcE5b5bbstpymqVWJm9FAjZHgXA_kBcWTaJGUdlueXB2DjSOM8MpwWZXUuUzG8DqYLDfe4xT3PfFZx7MAhOczLHmZqBboYJPAIo778eiHlpIKRlYJTziaR03hysqTeEh8NS+H5olwBOr4xPc2KjkzEbF4dyoLFy4GLwCvqWYMl6TTAH93f1NS5zEMR3hsPhT4P5HAnGPFObdQUgCAGJJwA4XkbsDMpp7ajTHJiM4FjCcLZ1cykQzFHJJ+K0hTMO1YTZG5RVZbCuLwWOXQz2C5YJ+pprBYIAUkVOC7uD63uHR1XFXPUzs0pQA0ufMzETvzhw_AeCHbY2IUdlDEFvD0fCx8KxcCDI+MeDsrkppTP9MvoZN8cq74J7T7CsvSMI7CvCs0NrHCxoOftQML8_GLb35Wh+MzGDn4URivOJJPKJpAIomTKkLfnKJKfKCBm_HGS540NBELi+FaxbGSwNTJlfChy5EGweVTjXzZUegt5nQeKcSuC8gPB9lWbqlUCHszBOfmXg_OuCSXN+ZU+aA+N8jufkjwRi3BZs6gQDx28V52coI41TwenK_VVBsL8nnBMsD92AVw0sa0fDH4WD4Qvhu2GqNu0KIMCUxTbzlX1CyIAKwMokGSPbibHctKcuRPrqyypIVSvLlHko9QeC+dGcJjV_waBt2aDHnsC+GiSE7069EqSPqZiy_4rw5nBHENlEMDGTKpS7L4WbwuvDTwSZonJUkKS57czYzUH5p8MbwqfCl4M51_wdaUIbgfLZ8Kbw8iBYpmbTqgAmrgya_AVBVO8MMl+f5VQTl93WPMEBAjwQapOX5ra1mp8stpw57g+qhErodbGCnCa0oZHv0cxxOQgO3_F5W5iJLIRXh8+E+4KI72Y+x98c_ja8Kpi0qiF4TjUzJ3MzR3M1Z3OnAccWNKLVveHTwVuEvRNNe7dpPFQkW9N2BNkv0mvD1838x3LtYJAVh4N1UxncNpGesa7XZDDnqm7a5sxecvzwpEpgT+A+Gtok1tvPltaGg0X53vDx8B+hSnlFuGOb+dZ7wSIYK0DSPGXNHM3VnM19pUrA+RJEBf1Y2BPsB3rVqO8K8IwM0O_j5wSRa91XDZxnnG8dFACV+Xb8Fd1pnvJGg8pok61KcEnalgl6cTLNOJyG7qeppUGVFBy9mA77NLvdXwrXhNeFbunn_H3hnvD74Z_DU8n5me4JEwgceueQi3Lk6LNC+UUQeBuCtspKOxvnXqyvCiBiRa5d7e4hdrfOlVn_rO+Hg+yX+b1Gc5633Uwm04DDaeK4MDxql67PTpuu7qexCiqZBNGWMKXq4vD68JXgjyMGa4DQ_ma4K7whKHf2Cr2uZ3nedjQa0OIl4eeC30MEhWrQ6ucXUtlf+tF8YuurAohW5d56pVz55U_JKhMASr2sPxoeDDXBNJ_Sxsm0oImK6S1BQDwv0JXR8rnB_orGloClMLFVB5M8SASfHX4nvDa8KHSjU_Z_MPxT+HyoCpHm3KKAILA8fifQ6r5weVDuy+jMXzaDi+GWYCmYyCatAAZlrRedO4Iq0AaViYlWf8g5FA4HGx8VYW4nK0CT2iOpBI8FlZS+dGa0pTFNaS6RtOm8IWudtZEH2JxcFi4NvxhsVAy+Bmxwt4Uvhr8J9wYBMLfRCggCS4EqcGHwG4rEoimzFFgGVIa7A_3dbwnZkE1aASoiRaXBtKW_1rYjOS_zRbSAmNvKClTF5Hi62QtwrvOSCjSmNc2fCBMl8aQBoES9NSwG7bJy_sM5IfOXg2VgGkYUps9TxZT2j4WFcFXgcI6uuSr_bwtL4fYgYDZkGw0AA_Fd65NNiU1gG4mcYVCcfiz09b6vX1mh7zOCkuic0uk1yXGiNTHfX830Zc7mWj_OuN9vHJwmWy1xkwaj59FMqfdcc+V0_TP9011VNR5LRFWKNNdvGw0A33thEKEXh12h1qk0B7vZm3NcCgeCIOCcSY3zXxnOD9eGswKxrJl_Hiw1nwt209MwYr8q6P+Xg_WYs_X_0XAkfCFMutTRytrOPhPofE2oKkvri4afL8yRP_YHPw6NZRsNABEoKgnQXfsNwATuH2Jn24fz85jBRIm_NyyGCgBjIZJx7QsyRRBwTh_meeYpC_eE3UF_5s9UA+fYnccPE_1r3DL6e+FoEHithsZjL+C8Mah+B8PYttEA0PFrwmLQ7pry_8mwFDa8PuW7XePo9wTit1WHA94fHgiygxi3BpukPozzrwqc_JvBBkzwWYIYJ_xqWAq3B6W5D6PdDWExvDGYZ2vGdXVYCvcFATOWbTQAZNo5Q7TLRK4ypAQ+HJTGNnLzcSIjOOFfEDi6+q7xuC44mF_S2CSVoDLfsyrrd6at_+o7zYEZl0ysoDh+drJ_a3njeJrSls+Mi9W8BVx3PIMb1vpnowEg668Mi6GtAAYoEpeHHMqxrwAw6Zp4mk8yAnDM+8L9w6uTVoI2838rz_ROPsr5uhP86NMsA+YgEO4N9H1hEPyM9lcEQdn6IR_XZ+MGAAcQ2vojK6yJbcQbqCx4JChHJtCnCSbPVllkRTfqKwhyaaJKYJ6c32b+as6vcRkbDfqyqqi09Owzg74qAGhvjOAT_nR93YE4bgAQ+IKgHJ4butmgTP1nWArafZpJPRo+GhbD+0P39TOnBkFhXJNUgnEyv5z_V+lzORhj30bLW8OR8OJQ2c4flmLXdwUV4mhYd+KNGwAizquIzBeF3QwsMUSrdt9mYkQw7irznN2dR7cSyOg7A1ttT+A+4o6T+fY6XtkOBWObxrxrL2AT3K0w5soX_IK2Iufj6tYVbvW7j5eZS3PTYlByuuaV766wFLT7NpF+R_hKMNG94dfCWpXA2wGhDoRbwkpvB5xvTd0T1lrzyykfzr0y_1+C7DfGvq109VYwSle+4BcBIBBH3ZPTT7ZxA4Dosr+79nsyQUS_X_8eG37OoVezDMhgxpmMc9lKlUBwyGzBwuwdWFsJ2sznfPd61fNMgdM187QP0ff+cDCYd40tzV6Ntp4PVZAOxlzW+qU9X9dXPI4bAO5fGNJ+1wBNXgYsBaKsex3KveOaLLs93D38IoetVAmI4xXt2lDB0q0EbeZfl_tWc765cv71wTw_Gcx7Ws7Powdr+1KOFQj6sk8pZ5dfBIblYN3WOnE9X9KhjkHY1pSdwmbEYKZlnl2Cr7cSyGYmWJhKUAIqnW3mqxrryXx9c_4TYZpmvqVtHQVtjb_8cnpzbl3jGTcA3H_BkFYg2X44WH84X6TOwiatBMcySOPl8K2Y+a2GNOV8G83TAmfXPoxfzg9eF8fy6Vg35+EiTeS10ZePg2znDEwz8_XV2kqVwDhlfBukvudzWwlkvuC1RCj7q2X+w7luCVH2Z5X56eokq_mqfq3OK_nlpC+P+jBuABCQUH4DaMUl4tEh01z708VIq0pwT65amhbC+8KoIHCdw98bbOYIWYHRzimnB+Yezv9Q4Pwbg81YLUFpzsxKZwn4kqZX494RjGnUHJpbT26OGwAizSZD6dEuI2KtTW1k1vVpH_Vp8sZ0cNjZ_Tk6Lwi68yyHD28dHEYJV86X+cvBszl_2mt+uljRRulcfuGb1i8rPqQudIWp8ysdPXzUJpDQhMGs1v909SQTBLcGP+QYx96w0tvBKIfn9hPm+3b7Hw6cf1PYrMxP1wMzplE6t36ZegAQriueAFCeZMxmmnHITscDw4HIXjaqEhy_8uR_zWPUe_5mZr5Rls601i7j9PLL1APA+mMX2nZkMHags94EpsuRVnuCu4dXV6sE3QdU5l+fC9b8Wbznd8ew0mc6m1tXZ77gF9W59Us+rm7jLgGepgMbqa4RDlvBCGU5MM6Hgl8u11udfLfWft9Vcjc78zOEE7aSzuY6lvM9cZQjT_Q0b5z6CmykAsiQUZkumLZKQFVJ9J5_dhj1OpjTI813rae+428aNpRVURw321bSmU_GHt+4AaAD64_1vn3lIJp9gXVo7DKU7_RtxnFF2BOuC+eF9QYBgdf620Fu2RSjbb2FtTqXXyx7YwXBRgLA+thdTw3Gs7pvBzk1UyuBZC3n7w2crwqMM7aqAPna4BlE9Uw2tsjHv9bLv63O3QAov0w9AGyIQJAq+Qbjc3suH2dusuOqsDv4e_5qmd8N4m6AVCV4b57jVdL9B4PfGcx_M8yYbGi7OnO6wBw7ODdSAfzxpPvXPgHg18HuL4Q5NRPTv7JPGM5fCDvCSmWfM_2860i8yviuHnU+twyeqZ+7fIiNLfbxr0387yidzWGUX9bsrDvhtb5AsAeDzdXOYB_APMdn+4Nxn5mvTGycf2XYE2T+as63Wapf+B5K248q1vzVfjEUSP62YO6C4kC4Jcy6EpTOtDaOMn65f4j2um1cZ4k0ToZ2WWXgrDeB1e_zMxDOrzV_tcxvf+E7lu_IHO_6q_1iSGz7CP0tBKZPNstKoP_VNoFdvwwGuNo_4waAbDkclKE20jzHfydATFXBWiXTpm1t5v92Olttza_Mvz737Q9+4eN4pqIxAbRSJejuCdw_y0qgf7qfH1SA1nf8cmSI9rqtfch6viTrlT10HVxrk6Mg8FertkrkY2+2UuavtNsXrG3mc9yjwTyYuTjH1qoEqgubZSUw31ZfbefKWr+Mpfm4ASC6loPO20gTnUqTsrgYXP9GUBGmYZNmPucr3WVK5+3h7uGJrVYJJNTiEBtdWtO4jM7LQWUbS_NxA0Cm+HUM3QogCKyVBuhVxee+zaQ5Xx_tmr9a5j+ce2U1cbqZn1MDkzUVEG0l0N+o_YR5ViUQLMyYPGfsddiX1zBaej74rHV+Pg765RNL2lQrgLIuS5RO7a4pTZcGa+rXgl8M+zTOvzxw_lq7fWWf8z8UOP_GQKBydJpPsqoE9+QK0ReC3f+oIHC9_sui+9P2XMHzuWE7h96Mri8Li0G7a3zh9XQ5jPJL9_4TnzdSAR7Pt0WbUkNk2VCmTZRvhfZ8XZ_06Jk2QbvDjrBW5nMMUQ4Gzq81P82RVpVAhvkO8ww2KgiMx3nV0Jgsi9OYdwUbbbVb4wO+4Bd0K3NOrWzjBoDODgeTVFZPD60wMvTV4YLwd6FvOyMPfHdYDP5HyVFit5nP+TeFtTI_t5xkstkvfkouW60SGAPHvCvo75YgQfo0uvqFczFY_8vM1W8TR8Oh4dG5ddu4ASBDRLkyQ1S0jhCdnOScPw7ZvLjf9_qwNhNWc_64md8dm_FWtVhPJTAuc1b5uhmaUxu2p+ebfERLutpkt8+X7eUHVYDWY9m4AVAPt1beFkTeuYGjmeOLggEvBhMQmQY3qXkWVrI+Mr_77HEqge_2Feg1Dv7ZExbCi8Ou0Pqs_LCU89pjW_uwcb5M7GPhuaEtORxkk6JkWRoeDUdCX6Yv7_MyQd8luExw3rK0HA4GmVFZnOaGbFQlEPT6a9djAW7DaQxjrcG5fzWT7fqhZVXU9n56PDSk9UN7z6rtUWV01S8MLxJGxHHw6wNntOY6Uc4LXwwyqQ_zXELvCxcGYnOyILs+3Bj+MXw99NVnHjUorRy_P9gD3Rn2BqJb7537s_DpcHfoo+LlMYOy_44cfzq8IgiC1gTcR8KXgjGMHQQbrQCEt949EghtT6D8V4kWWDuCa88KPo89uHyna9a4qigyXQAKCuPw2TWZ36fz87hBHwJNXweCcSwF675zHKHq6L+PedKRZqcFOqL1lT4FmSQ0d77gk5mZAXL4QrghfDl8LxgYiGBgzl8edgYTmtT0a3lRcbxp7B6i7ZwdsnumZZ6tj1H9++3D2Pron7PN6cpwV+Bgmpa+tJb1nwgqUZt8+bh+a6Nq_d86PpCKwGP5IkHayCeCV0RrtU2i7FG623vycWwjgKhnfb9qHX_q6v_qv6rLNPu39p8daOdVlJZtYNGR7l4BBcOGl5w+slLn1kfRaqDMYE3C82WMKP2vUOKlObdVFDgr164N14SXhW5lUV0_Em4L+8KGA2CjFSB9DkwkPhA4mXPbvYAg8Pydw_OqxOOhloo059ZRgGbWfVpZAs4PNKzsV4E4m9Z0x0RVddIKUKXIZuzyYCNyRqjnVgAoZ18NAkXZGvsHi3znqWAy_bLw8vCu4N2_zX7OpyM+Gu4NEmrDpkxPYrUmy+z7h7QRKXI53Tq2K4hqEV4BkubchgrQhDY0opUqQLvK_jQHiUPno4Hm9kN8sOlmoK8J7wj1PmpgxffT_lr41+B99pwwD4KIMDRanBt+MvxbkNk0K_0cJdah8PbwM0FlmNgm3QPUAAzOemRQNiheiURwVRgT5HSTsif4Qfh2sGSY3FPZZDg_CADa7AjdBKETvbwOyn7LKM0ntr6y0ADtA7waGfyxsBj8CMRMUvv0sDu8NHwuKGG++1S10uW8CPCB8MZwaWiTJx8H5f7GHD8bPhFU2R+Gia2vCiCLZbfdqTLludrWNG0TVQ0EwQVB9Ir0qhy9TCbP224mAc8OtNgV7PppVJWTrqql31HoejDQ1blerK8KUIMxsPvCN8Irg+z2Y1D1Y2LecZU7k74kfDFsmc1MxjIro4lq+f7wpnB1EADPDBKG0ZOWXwt_HG4NlgGB0Yv1VQFqMBxuDyDzlSnP3xVMlvOr5NVSkFODQHB8KKgIvU3OQ7eg0YAelfl70rYs0kT2l9FSAFjzaUkf2jrfm1Vm9vbAPMgAvZt+PdwTrggCoo1sgWHdM3EBYk9wZ7CM9DrBPG8rWSWACijz3xxeFxYDjVxnNLDp4_jfDZ8K+4OA6DVB+q4AGd9ggNZ076uefyTIfpFeQWCiXh2ZIGD2BgLygeD7qsGpZOZWgW_52xvM3W8k3p7KONj87fRpJwhKk16dn+eeWJu1+zQDfTwoWctBdl8WRDkhKtJLEGJcFH4q7AsyQBXpfcJ55maYOb8gcPgHwi+Eq8NCaDPffM1b8vxeuCHYI9FxKgkxjQqQsZ6oAjZ3hwKHW8scRb9+taESEEiFqKNKodwRYzsHgvlxMCx13vMF+_nBq96zQhnny3yv0LQ6GGQ_DZ2fihngNM3zOdNkXxs42dpn99uNfA63B7DWyYDrAwE+H4iwHU1pV_ksb9cGwU8DjqdL6V+Zz_l_Emjw6fBY6H3dzzNP2LQqQHVgYpzqPVZEsyPB+aoE9geEIIrxEEt7MRDpULCcPBosDUqh729FMw9VzJy8_gr8hSD7OV7gnx5cLzMnGW6dl_mcTyua0W6qVhE41U7ycP3IeJO_IhDjunBeeE7oCsLJ3ndlwM1B0HwseBWyOZpaScyzJzEBbIfvFe+dQan_2SAQ6q+k3bna7ZvTHwaOvyNw_kyWPgOehclYZVy0m6TPMpujZUdlv0AhEGSL4JBBgsdRADHiqAqVPZ63GWa8NDReYzXOvUEQGK8AUOnqjSfNgRmv0g5ZL8D3h8NB0E8989PHwGZVAdr+lHVr4yVBuf+NYHO0GFxrjVC1CbITtgz8e7BHuCF8MwgoQm6GGa9qdlZ4S+Dsa4JXuzOD4DDXrs4c_I3A+R8MHL8vmKu5mPdMzABnaSZm8jJXBVDKl4dHgsmUdo0knHO+56iMLgzbizlaZz1LRagKU8_vU0jj4GyZrlo5cmxVJq94i0EA7A7mYC_ge60Zq_KOA4HjZf4DwbmZL23dAWYMMzH9EkgAKpfK_TvDrvCGYM0kcmuCAN8Jlg5LAKffG1SHW4OKcFewri6FCoY0N2zl9MU8QWa_LMj4q4KAfHEQCJaANuO72nK+cd0UBP9fB3uaY4Hjzcn8ZmqzrgA1OROtSSvnMnh5eI44qgFxjU_mEbMgNJP9shzuPxJ8R2AQmuACANWfY0s+nrB6fgWevp2T8VgMAsBRADgag6A1xlGmL+MzV0H6rbAcDgbZ75xr7tsUe_qm9Hpyp8ZAdOIq8zJMKX13OC_8eOCAUUa4CqR2CXBOEHA+oV0TID7bZMk250p4Y1DSOV310d_OYDznDz8bn+uuGa9rjs6tpKP+vhoE+V8Ga_7dQRWrIK0x5NTszeA32wjAIbLBOrg_cM5SIBSHENvRslEVIc2B8D6DA8s803c5gMO0lem1AsDzOboNAIHgszGs5OhcGph+Zbz5CDT9LgeOXwoPhmPBPVvC1prQrAdpPJzJEfVDyuVpqwRvC_YKFwUOWcs4A1ViHZmloa4NTgz_0TdktaMxOFaGa69lAmxf4OS_DzZ3dwTLkjcYgVHjSXPzbStUgFYFjiEiUwWIthxUhqUgq+wBZLuM5CRtTtNujcNQwaIC9GmcKZiMU1u2axuvTHcUAEeC81vSCLSVzfg4jnMtAZx9YbDpuzqoCFcEZVu7GwQ5NRXjcE4WkLcFGX9z8BZyX7Cpdc192gJ7S9pWqwBdkQhX2aOMWh6M2W56KRB5ZxAA7nNdxrebsyrhgkNAteTjCatloY6cp10l27HeLKzhR4ON3FIQAI72MUfCllnjM5ZVbatXgO7gjZdDObhdAjh9V7A8vDQIiIVwerCLVzlUCAGiknjGacFzGMfKVE4WVJYhThVUHFqbOQ6_KwjGQ4Gj3SNY3OM5FTBpbn0jxHYyGVnZxWFl5uG8AOB0AeBebfcJAI4VKO5xv3OVAO7lyFEBINPtQZaDAHAUAM67f1tbCbCtJ5HBm4cSL6M52WfZ7sjZdd2xJR9PmCBo6S4BAsx11UGm1_U05zZXYK7AXIG5AnMF5grMFZgrMFdgrsBcgbkCcwXmCswVmCswV2CuwFyBuQJzBbasAv8Ph4K7Pz+1GwoAAAAASUVORK5CYII=", "BTTTriggerConfig"=>{"BTTTouchBarButtonColor"=>"0.000000, 0.000000, 0.000000, 255.000000", "BTTTouchBarItemIconWidth"=>22, "BTTTouchBarButtonTextAlignment"=>0, "BTTTouchBarItemPlacement"=>1, "BTTTouchBarButtonFontSize"=>15, "BTTTouchBarButtonCornerRadius"=>15, "BTTTouchBarAlternateBackgroundColor"=>"75.323769, 75.323769, 75.323769, 255.000000", "BTTTouchBarAlwaysShowButton"=>false, "BTTTBWidgetWidth"=>400, "BTTTouchBarIconTextOffset"=>5, "BTTTouchBarButtonWidth"=>100, "BTTTouchBarOnlyShowIcon"=>true, "BTTTouchBarFreeSpaceAfterButton"=>5, "BTTTouchBarItemIconHeight"=>22, "BTTTouchBarItemPadding"=>0}}
  script = button.to_btt_as('add_new_trigger')
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

  if ARGV[0] =~ /^close/
    if type == 'touchbar'
      add_touch_bar_close_button
      puts 'Close Button added.'
      puts 'You may need to restart BetterTouchTool to see the button in your configuration.'
      Process.exit 0
    else
      puts "Close button only works for touch bar"
      Process.exit 1
    end
  end

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
  chart = `/usr/local/bin/doing view btt`.strip.gsub(/(\e\[[\d;]+m)/, '')
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
