#!/usr/bin/env ruby
# frozen_string_literal: true

require 'cgi'
require 'json'

# Reads all Bunches and creates BetterTouchTool Touch Bar widgets for them. Each
# widget shows the name of the Bunch and the open/closed state using background
# colors. Requires additional setup: <http://ckyp.us/jcBxaM>
#
##########################################################
#..___...........__._...................._..._...........#
#./.__|___._._../._(_)__._._.._._._.__._|.|_(_)___._._...#
#|.(__/._.\.'.\|.._|./._`.|.||.|.'_/._`.|.._|./._.\.'.\..#
#.\___\___/_||_|_|.|_\__,.|\_,_|_|.\__,_|\__|_\___/_||_|.#
#....................|___/...............................#
##########################################################
#
# Edit the location of the `status_script` below to point to `bunch_status.rb`
status_script = '/Users/ttscoff/scripts/bunch_status.rb'
# If using Bunch Beta, change the below to "Bunch Beta"
bunch_app = 'Bunch'
#
#### END CONFIG ###

# Hash methods
class Hash
  def to_btt_json(method)
    query = CGI.escape(to_json).gsub(/\+/, '%20')
    %(btt://#{method}/?json=#{query})
  end
end

`osascript -e 'tell app "#{bunch_app}" to list bunches'`.strip.split(/, /).each do |bunch|
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
      'BTTTouchBarScriptUpdateInterval' => 5,
      'BTTTouchBarButtonName' => bunch.to_s
    }
  }
  `open "#{data.to_btt_json('add_new_trigger')}"`
end
