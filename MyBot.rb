# Welcome to your first Halite-II bot!
#
# This bot's name is Opportunity. It's purpose is simple (don't expect it to win
# complex games :) ):
#  1. Initialize game
#  2. If a ship is not docked and there are unowned planets
#   a. Try to Dock in the planet if close enough
#   b. If not, go towards the planet

# Load the files we need
$:.unshift(File.dirname(__FILE__) + "/hlt")
require 'game'

at_exit do
  e = $!

  if e
    File.open('errors.log', 'w') do |file|
      file.puts "#{e.backtrace.first}: #{e.message} (#{e.class})", e.backtrace.drop(1).map{|s| "\t#{s}"}
    end
  end
end
# GAME START

# Here we define the bot's name as Opportunity and initialize the game, including
# communication with the Halite engine.
game = Game.new("StaticAssignment")
# We print our start message to the logs
LOGGER = game.logger

## Assignments
require 'assigner'
Assigner::Assigner.register(Assigner::Settler)
Assigner::Assigner.register(Assigner::Conqueror)
Assigner::Assigner.register(Assigner::Assaulter)

assigner = Assigner::Assigner.new(game.map)

Assigner::Assigner.register(Assigner::Stalker, prepend: true) if game.map.players.size == 2

while true
  # TURN START
  # Update the map for the new turn and get the latest version

  game.update_map
  # Here we define the set of commands to be sent to the Halite engine at the
  # end of the turn
  command_queue = []

  assigner.update

  command_queue.concat assigner.execute

  command_queue.reject! {|action| action == :skip }

  game.send_command_queue(command_queue)
end
