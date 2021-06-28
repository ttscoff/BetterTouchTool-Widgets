#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
open_color = '165,218,120,255'
closed_color = '95,106,129,255'

# bunch_folder = `/usr/bin/osascript -e 'tell app "Bunch" to get preference "folder"'`.strip
# status_file = File.join(bunch_folder,'bunch_status.json')
# status_file = '/Users/ttscoff/bunch_status.json'

# status = JSON.parse(IO.read(status_file))
open_bunches = `/usr/bin/osascript -e 'tell app "Bunch" to list open bunches'`.strip.downcase.split(/, /)
bunch = ARGV[0].strip.downcase

color = open_bunches.include?(bunch.downcase) ? open_color : closed_color

print "{\"background_color\":\"#{color}\"}"
