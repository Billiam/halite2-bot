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
game = Game.new("OffsetLines")
# We print our start message to the logs
LOGGER = game.logger
game.logger.info("Starting my Opportunity bot!")

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

  # game.logger.error(assignments.map {|k, v| "#{k} => #{v}"})
  max_assignments = map.me.ships.size - 2

  if assignments.size < max_assignments
    active_enemies = map.active_enemies

    if active_enemies.size > assignments.size
      self_location = map.me.average_location

      # TODO: pull into map method
      # TODO: Evaluate average vs median distances (find enemy core)
      sorted_enemies = active_enemies.sort_by do |player|
        location = player.average_location
        (location[:x] - self_location[:x])**2 + (location[:y] - self_location[:y])**2
      end

      available_ships = map.me.ships.reject(&:docked?).reject {|ship| assignments.key?(ship.id) }

      sorted_enemies.each do |enemy|
        # If ship already assigned to a player
        unless assignments.value?(enemy.id)
          # find a ship without an assignment
          available_ship = available_ships.shift
          break unless available_ship

          assignments[available_ship.id] = enemy.id
          break if assignments.size >= max_assignments
        end
      end
    end
  else
    game.logger.info("Unassigning ships")

    while assignments.size > [0, max_assignments].max do
      assignments.delete(assignments.keys.last)
    end
  end

  explodable_planets = map.planets.map do |planet|
    explosion_radius = [planet.radius, Game::Constants::DOCK_RADIUS].max + planet.radius + 0.5
    count = map.ships.inject(0) do |sum, ship|
      in_radius = planet.calculate_distance_between(ship) < explosion_radius
      cost_modifier = ship.owner == map.me ? -1 : 1
      sum + cost_modifier * (in_radius ? 1 : 0)
    end

    expending = planet.health / Game::Constants::BASE_SHIP_HEALTH
    expending += planet.docking_spots if planet.owner == map.me

    value = count - expending

    { planet: planet, value: value } if value > 3
  end.compact.sort_by do |data|
    -data[:value]
  end

  # For each ship we control
  map.me.ships.each do |ship|
    # skip if the ship is docked
    next if ship.docked?
    next if Time.now - start_time > 1.6

    ship_command = nil
    nearby_entities = map.entities_sorted_by_distance(ship)
    planets_by_distance = nearby_entities.select { |entity| entity.is_a? Planet }

    enemy_target_id = assignments[ship.id]
    if enemy_target_id
      # assigned tasks
      enemy_target = map.player(enemy_target_id)

      closest_enemy_ships = nearby_entities & enemy_target.ships
      ship_command = closest_enemy_ships.select(&:docked?).lazy.map do |target_ship|
        attack_point = ship.approach_closest_point(target_ship, Game::Constants::WEAPON_RADIUS + attack_fudge)
        next :skip if attack_point.x == ship.x && attack_point.y == ship.y

        ship.navigate(attack_point, map, speed, max_corrections: 45, angular_step: 3)
      end.find(&:itself)

      unless ship_command
        stalked_ship = closest_enemy_ships.first
        # no docked ships, follow enemy ships
        if ship.calculate_distance_between(stalked_ship) < 10
          # RUN!
          game.logger.error("too close to ship, should retreat")
        else
          nav_point = ship.closest_point_to(stalked_ship, Game::Constants::MAX_SPEED + Game::Constants::WEAPON_RADIUS + Game::Constants::SHIP_RADIUS * 2)
          ship_command = ship.navigate(nav_point, map, speed, max_corrections: 30, angular_step: 6)
        end
      end

      ship_command = :skip unless ship_command
    end

    unless ship_command
      # reinforce
      non_full_planets = planets_by_distance.first(4).select {|planet| !planet.full? && [map.me, nil].include?(planet.owner) }
      ship_command = non_full_planets.lazy.map do |planet|
        ship.dock(planet) if ship.can_dock?(planet)
      end.find(&:itself)
    end

    unless ship_command
      # bomb
      ship_command = explodable_planets.lazy.map do |planet|
        game.logger.info("#{ship.id} trying to attack #{planet[:planet].id}")
        ship.navigate(planet[:planet], map, speed, max_corrections: 30, angular_step: 3, ignore_ships: true, ignore_my_ships: false)
      end.find(&:itself)
    end

    unless ship_command
      # conquer
      ship_command = map.target_planets_by_weight(ship, distance: 1, defense: -1.5).lazy.map do |target_planet|
        if target_planet.owned?
          next map.sort_closest(ship, target_planet.docked_ships).lazy.map do |target_ship|
            attack_point = ship.approach_closest_point(target_ship, Game::Constants::WEAPON_RADIUS + attack_fudge)
            # TODO: Try to attack only one
            # TODO: Try to navigate to planet range
            ship.navigate(attack_point, map, speed, max_corrections: 30, angular_step: 3, ignore_ships: true, ignore_my_ships: false)
          end.find(&:itself)
        end

        docking_position = ship.approach_closest_point(target_planet, Game::Constants::DOCK_RADIUS)
        ship.navigate(docking_position, map, speed, max_corrections: 30, angular_step: 3)
      end.find(&:itself)
    end

    command_queue << ship_command if ship_command && ship_command != :skip
  end

  game.send_command_queue(command_queue)
end
