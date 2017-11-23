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
game = Game.new("QuadTree")
# We print our start message to the logs
LOGGER = game.logger
game.logger.info("Starting my Opportunity bot!")

# TODO: extract:
# Commander
# Strategies

speed = Game::Constants::MAX_SPEED
assignments = {}
attack_fudge = 0.25
while true
  # TURN START
  # Update the map for the new turn and get the latest version
  start_time = Time.now

  game.update_map
  map = game.map
  # Here we define the set of commands to be sent to the Halite engine at the
  # end of the turn
  command_queue = []

  # update assignments
  assignments = assignments.select { |ship_id, player_id| map.ship(ship_id) && map.player_active?(map.player(player_id)) }

  active_enemies = map.active_enemies
  active_enemy_ids = active_enemies.map(&:id)

  # Remove inactive enemies from assignments
  assignments.keep_if do |_ship_id, enemy_id|
    active_enemy_ids.include?(enemy_id)
  end

  max_assignments = [(map.me.ships.size / 2.0 - 0.5).floor, active_enemies.size].min
  if assignments.size < max_assignments

    available_ships = map.me.ships.reject(&:docked?).reject {|ship| assignments.key?(ship.id) }
    available_ships.each do |ship|
      target = map.enemy_ships_in_range(ship, Game::Constants::MAX_SPEED * 9).find do |nearby_ship|
        next if assignments.value?(nearby_ship.owner.id)

        true
      end
      next unless target
      assignments[ship.id] = target.owner.id
      break if assignments.size >= max_assignments
    end
  else
    # Remove extra assignments
    while assignments.size > [0, max_assignments].max do
      assignments.delete(assignments.keys.last)
    end
  end

  # explodable_planets = map.planets.map do |planet|
  #   kill_distance = planet.radius + [planet.radius, Game::Constants::DOCK_RADIUS].max * 0.8
  #
  #   targets = planet.closest_enemies(map, kill_distance).lazy.inject(0) do |count, ship|
  #     cost_modifier = ship.owner == map.me ? -1 : 1
  #     count + (1 * cost_modifier)
  #   end
  #
  #   expenditure = (planet.health / Game::Constants::BASE_SHIP_HEALTH).ceil
  #   expenditure += planet.docking_spots if planet.owner == map.me
  #
  #   value = targets - expenditure
  #
  #   [planet, value] if value > 3
  # end.compact.sort_by do |(_planet, value)|
  #   -value
  # end.map do |(planet, _value)|
  #   planet
  # end

  # For each ship we control
  map.me.ships.each do |ship|
    # skip if the ship is docked
    next if ship.docked?
    next if Time.now - start_time > 1.6

    ship_command = nil
    nearby_entities = map.entities_sorted_by_distance(ship)
    planets_by_distance = nearby_entities.select { |entity| entity.is_a? Planet }

    # Planet Defense
    unless ship_command
      ship_command = (planets_by_distance & map.my_planets).select do |planet|
        ship.squared_distance_to(planet) < (Game::Constants::MAX_SPEED * 4 + planet.radius) ** 2
      end.map do |planet|
        # TODO: prevent dithering between close ships by including closest to attacking ship in consideration
        planet.closest_enemies(map, Game::Constants::MAX_SPEED * 6 + planet.radius).map do |target_ship|
          attack_point = ship.approach_closest_point(target_ship, 3)
          ship.navigate(attack_point, map, speed, max_corrections: 18, ignore_ships: true, ignore_my_ships: false)
        end.find(&:itself)
      end.find(&:itself)
    end

    # Task Assignment
    unless ship_command
      enemy_target_id = assignments[ship.id]
      if enemy_target_id
        enemy_target = map.player(enemy_target_id)

        closest_enemy_ships = nearby_entities & enemy_target.ships
        ship_command = closest_enemy_ships.select(&:docked?).lazy.map do |target_ship|
          attack_point = ship.approach_closest_point(target_ship, Game::Constants::WEAPON_RADIUS)
          next :skip if attack_point.x == ship.x && attack_point.y == ship.y

          ship.navigate(attack_point, map, speed, max_corrections: 18)
        end.find(&:itself)

        unless ship_command
          stalked_ship = closest_enemy_ships.first
          # no docked ships, follow enemy ships
          if ship.squared_distance_to(stalked_ship) < 10 ** 2
            # RUN!
            game.logger.error("too close to ship, should retreat")
          else
            nav_point = ship.closest_point_to(stalked_ship, Game::Constants::MAX_SPEED + Game::Constants::WEAPON_RADIUS + Game::Constants::SHIP_RADIUS * 2)
            ship_command = ship.navigate(nav_point, map, speed, max_corrections: 18)
          end
        end

        ship_command = :skip unless ship_command
      end
    end

    # Reinforce and Settle
    unless ship_command
      non_full_planets = planets_by_distance.first(4).select {|planet| !planet.full? && [map.me, nil].include?(planet.owner) }
      ship_command = non_full_planets.lazy.map do |planet|
        ship.dock(planet) if ship.can_dock?(planet)
      end.find(&:itself)
    end

    # unless ship_command
    #   # bomb
    #   ship_command = explodable_planets.lazy.map do |(planet, value)|
    #     game.logger.info("#{ship.id} trying to attack #{planet[:planet].id}")
    #     ship.navigate(planet[:planet], map, speed, max_corrections: 30, angular_step: 3, ignore_ships: true, ignore_my_ships: false)
    #   end.find(&:itself)
    # end

    # Conquer
    unless ship_command
      ship_command = map.target_planets_by_weight(ship, distance: 1, defense: -1.5).lazy.map do |target_planet|
        if target_planet.owned?
          next map.sort_closest(ship, target_planet.docked_ships).lazy.map do |target_ship|
            attack_point = ship.approach_closest_point(target_ship, Game::Constants::WEAPON_RADIUS + attack_fudge)
            # TODO: Try to attack only one
            ship.navigate(attack_point, map, speed, max_corrections: 18, ignore_ships: true, ignore_my_ships: false)
          end.find(&:itself)
        end

        docking_position = ship.approach_closest_point(target_planet, Game::Constants::DOCK_RADIUS)
        ship.navigate(docking_position, map, speed, max_corrections: 18)
      end.find(&:itself)
    end

    command_queue << ship_command if ship_command && ship_command != :skip
  end

  game.send_command_queue(command_queue)
end
