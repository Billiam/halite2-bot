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

# GAME START

# Here we define the bot's name as Opportunity and initialize the game, including
# communication with the Halite engine.
game = Game.new("ReduceSuicide")
# We print our start message to the logs
game.logger.info("Starting my Opportunity bot!")

while true
  # TURN START
  # Update the map for the new turn and get the latest version
  start_time = Time.now

  game.update_map
  map = game.map
  # Here we define the set of commands to be sent to the Halite engine at the
  # end of the turn
  command_queue = []

  speed = Game::Constants::MAX_SPEED

  # For each ship we control
  map.me.ships.each do |ship|
    # skip if the ship is docked
    next if ship.docked?
    next if Time.now - start_time > 1.6

    nearby_entities = map.entities_sorted_by_distance(ship)
    planets_by_distance = nearby_entities.select { |entity| entity.is_a? Planet }

    # reinforce
    non_full_planets = planets_by_distance.first(4).select {|planet| !planet.full? && [map.me, nil].include?(planet.owner) }
    ship_command = non_full_planets.lazy.map do |planet|
      ship.dock(planet) if ship.can_dock?(planet)
    end.find(&:itself)

    unless ship_command
      # conquer
      ship_command = map.target_planets_by_weight(ship, distance: 1, defense: -1.5).lazy.map do |target_planet|
        if target_planet.owned?
          next map.sort_closest(ship, target_planet.docked_ships).lazy.map do |target_ship|
            attack_point = ship.closest_point_to(target_ship)
            ship.navigate(attack_point, map, speed, max_corrections: 30, angular_step: 3, ignore_ships: true, ignore_my_ships: false)
          end.find(&:itself)
        end

        docking_position = ship.closest_point_to(target_planet)
        ship.navigate(docking_position, map, speed, max_corrections: 30, angular_step: 3)
      end.find(&:itself)
    end

    command_queue << ship_command if ship_command
  end

  game.send_command_queue(command_queue)
end
