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
game = Game.new("Opportunity")
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

    ship_command = nil

    # explore
    planets_by_distance.each do |planet|
      next if planet.owned?

      if ship.can_dock?(planet)
        ship_command = ship.dock(planet)
        break
      end

      # If we can't dock, we move towards the closest empty point near this
      # planet (by using closest_point_to) with constant speed. Don't worry
      # about pathfinding for now, as the command will do it for you.
      # We run this navigate command each turn until we arrive to get the
      # latest move.
      # Here we move at half our maximum speed to better control the ships
      # In order to execute faster we also choose to ignore ship collision
      # calculations during navigation.
      # This will mean that you have a higher probability of crashing into
      # ships, but it also means you will make move decisions much quicker.
      # As your skill progresses and your moves turn more optimal you may
      # wish to turn that option off.
      closest = ship.closest_point_to(planet)
      navigate_command = ship.navigate(closest, map, speed, max_corrections: 30, angular_step: 3)
      # If the move is possible, add it to the command_queue (if there are too
      # many obstacles on the way or we are trapped (or we reached our
      # destination!), navigate_command will return null; don't fret though,
      # we can run the command again the next turn)
      if navigate_command
        ship_command = navigate_command
        break
      end
    end

    unless ship_command
      enemy_planet = planets_by_distance.select {|planet| planet.owner && planet.owner != map.me }.first
      if enemy_planet
        target_ship = map.closest_of(ship, enemy_planet.docked_ships)

        if target_ship
          attack_distance = ship.closest_point_to(target_ship)
          ship_command = ship.navigate(attack_distance, map, speed, max_corrections: 30, angular_step: 3, ignore_ships: true, ignore_my_ships: false)
        end
      end
    end
    #
    # unless ship_command
    #   # reinforce
    #   non_full_planets = planets_by_distance.select {|planet| planet.owner == map.me && ! planet.full? }
    #   non_full_planets.each do |planet|
    #     if ship.can_dock?(planet)
    #       ship_command = ship.dock(planet)
    #       break
    #     end
    #     # If we can't dock, we move towards the closest empty point near this
    #     # planet (by using closest_point_to) with constant speed. Don't worry
    #     # about pathfinding for now, as the command will do it for you.
    #     # We run this navigate command each turn until we arrive to get the
    #     # latest move.
    #     # Here we move at half our maximum speed to better control the ships
    #     # In order to execute faster we also choose to ignore ship collision
    #     # calculations during navigation.
    #     # This will mean that you have a higher probability of crashing into
    #     # ships, but it also means you will make move decisions much quicker.
    #     # As your skill progresses and your moves turn more optimal you may
    #     # wish to turn that option off.
    #     closest = ship.closest_point_to(planet)
    #     navigate_command = ship.navigate(closest, map, speed, max_corrections: 30, angular_step: 3, ignore_ships: true, ignore_my_ships: false)
    #     # If the move is possible, add it to the command_queue (if there are too
    #     # many obstacles on the way or we are trapped (or we reached our
    #     # destination!), navigate_command will return null; don't fret though,
    #     # we can run the command again the next turn)
    #     if navigate_command
    #       ship_command = navigate_command
    #       break
    #     end
    #   end
    # end

    # unless ship_command
    #   # bomb the whole fucking planet
    #   enemy_planets = planets_by_distance.select {|planet| planet.owner && planet.owner != map.me }
    #
    #   enemy_planets.each do |planet|
    #     ## and circle planet
    #     speed = Game::Constants::MAX_SPEED
    #     navigate_command = ship.navigate(planet, map, speed, max_corrections: 30, ignore_ships: true, ignore_my_ships: false)
    #     # If the move is possible, add it to the command_queue (if there are too
    #     # many obstacles on the way or we are trapped (or we reached our
    #     # destination!), navigate_command will return null; don't fret though,
    #     # we can run the command again the next turn)
    #     if navigate_command
    #       ship_command = navigate_command
    #       break
    #     end
    #   end
    # end

    command_queue << ship_command if ship_command
  end

  game.send_command_queue(command_queue)
end
