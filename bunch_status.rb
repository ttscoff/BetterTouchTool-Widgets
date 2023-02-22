#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
open_color = '165,218,120,255'
closed_color = '95,106,129,255'

bunch = `ps ax | grep -v grep | grep -c 'Bunch Beta'`.strip.to_i == 1 ? 'Bunch Beta' : 'Bunch'

warn "Targeting #{bunch}"

open_bunches = `/usr/bin/osascript -e 'tell app "#{bunch}" to list open bunches'`.strip.downcase.split(/, /)
bunch = ARGV.join(' ').strip.downcase

color = open_bunches.include?(bunch.downcase) ? open_color : closed_color

print "{\"background_color\":\"#{color}\"}"
