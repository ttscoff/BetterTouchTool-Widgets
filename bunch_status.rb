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
