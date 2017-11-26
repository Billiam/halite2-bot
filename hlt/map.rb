require 'player'
require 'planet'
require 'ship'
require 'position'
require 'helper/cache'
require 'collider'

# Map which houses the current game information/metadata.

# my_id: Current player id associated with the map
# width: Map width
# height: Map height
class Map
  extend Cache
  attr_reader :my_id, :width, :height

  def initialize(player_id, width, height)
    @my_id = player_id
    @width = width
    @height = height
    @players = {}
    @planets = {}
    @planet_defense = {}
  end

  # return: Array of all players
  def players
    @players.values
  end

  cache def enemy_players
    players - [me]
  end

  # Fetch player by id
  # id: the id (integer) of the desired player
  # return: The player associated with id
  def player(id)
    @players[id]
  end

  # return: The bot's Player object
  def me
    player(my_id)
  end

  # return: Array of all Planets
  def planets
    @planets.values
  end

  # Fetch a planet by ID
  # id: the ID of the desired planet
  # return: a Planet
  def planet(id)
    @planets[id]
  end

  cache def ships
    players.flat_map(&:ships)
  end

  def ship(ship_id)
    players.lazy.flat_map(&:ships).find {|ship| ship.id == ship_id }
  end

  def update(input)
    tokens = input.split
    @players, tokens = Player::parse(tokens)
    @planets, tokens = Planet::parse(tokens)
    raise if tokens.length != 0
    clear_cache
    update_collider
    link
  end

  cache def collider
    Collider.new(@width.to_i, @height.to_i)
  end

  def update_collider
    (ships + planets).each do |entity|
      collider.add(entity)
    end
  end

  # Fetch all entities in relationship to the entered entity keyed by distance
  # entity: the source entity to find distances from
  # return: Hash containing all entities with their designated distances
  def nearby_entities_by_distance(entity)
    # any new key is initialized with an empty array
    result = Hash.new { |h, k| h[k] = [] }

    (ships + planets).each do |foreign_entity|
      next if entity == foreign_entity
      result[entity.calculate_distance_between(foreign_entity)] << foreign_entity
    end
    result
  end

  def entities_in_range(entity, radius)
    collider.nearby(entity, radius)
  end

  def ships_in_range(entity, radius)
    entities_in_range(entity, radius).select do |nearby_entity|
      nearby_entity.is_a? Ship
    end
  end

  def enemy_ships_in_range(entity, radius)
    ships_in_range(entity, radius).reject do |nearby_entity|
      nearby_entity.owner == me
    end
  end

  cache def planetary_defense
    enemy_defenses = ships.reject {|ship| ship.owner == me || ship.docked? }


    planets.map do |planet|
      # number of enemy ships in area
      defense = enemy_defenses.count do |enemy_ship|
        planet.squared_distance_to(enemy_ship) <= (planet.radius + 5 + 4) ** 2
      end

      [planet, defense]
    end.to_h
  end

  cache def active_enemies
    enemy_players.select {|player| player_active?(player) }
  end

  def player_active?(player)
    player.ships.any? || player_planets(player).any?
  end

  def player_planets(player)
    planets.select { |planet| planet.owner == player }
  end

  cache def enemy_ships
    ships - me.ships
  end

  cache def my_planets
    player_planets(me)
  end

  cache def enemy_planets
    planets - my_planets
  end

  def target_planets_by_weight(entity, distance: 1, defense: 1)
    enemy_planets.sort_by do |planet|
      entity.calculate_distance_between(planet) * distance * 0.05 + planet.docked_ships.size * defense
    end
  end

  def entities_sorted_by_distance(entity)
    sort_closest(entity, (ships + planets).reject { |foreign_entity| entity == foreign_entity })
  end

  def sort_closest(entity, foreign_entities)
    foreign_entities.sort_by do |foreign_entity|
      entity.squared_distance_to(foreign_entity)
    end
  end

  def closest_of(entity, foreign_entities)
    foreign_entities.min_by do |foreign_entity|
      entity.squared_distance_to(foreign_entity)
    end
  end

  # Check whether there is a straight-line path to the given point, without
  # obstacles in between.
  # ship: Source entity
  # target: target entity
  # ignore: Array of entity types to ignore
  # return: Whether there are any obstacles
  def any_obstacles_between?(ship, target, ignore=[])
    entities = []
    entities.concat(planets) unless ignore.include?(:planets)
    entities.concat(ships) unless ignore.include?(:ships)
    entities.concat(me.ships) if !ignore.include?(:my_ships) && ignore.include?(:ships)

    target_distance= ship.calculate_distance_between(target)
    short_vector = nil

    # LOGGER.error("#{ship.id} heading to (#{target.x}, #{target.y})") if [0,1].include?(ship.id)

    entities.find do |foreign_entity|
      next if foreign_entity == ship || foreign_entity == target

      fudge = ship.radius * 2

      if foreign_entity.traveling?
        # Ignore distant collisions before calculating moving circles
        # Floor thrust angle to match actual thrust limits
        thrust_angle = Integer(ship.calculate_angle_between(target))
        short_vector ||= Vector.from_angle(thrust_angle, [target_distance, Game::Constants::MAX_SPEED].min)

        next false if ship.squared_distance_to(foreign_entity) > (Game::Constants::MAX_SPEED * 2) ** 2
        next true if intersect_moving_circle?(ship, short_vector, foreign_entity, foreign_entity.vector)
      end

      next true if intersect_segment_circle?(ship, target, foreign_entity, fudge)

      false
    end
  end

  private

  # Update each ship + planet with the completed player and planet objects
  def link
    (planets + ships).each do |entity|
      entity.link(@players, @planets)
    end
  end

  def distance_to_line2(start_1, end_1, target)
    line_length2 = start_1.squared_distance_to(end_1)

    # Line is zero length, so distance is from any point on line
    return start_1.squared_distance_to(target) if line_length2 == 0

    t = ((target.x - start_1.x) * (end_1.x - start_1.x) + (target.y - start_1.y) * (end_1.y - start_1.y)) / line_length2
    # clamp to 0 - 1
    t = [0, [1, t].min].max

    closest_point = {
      x: start_1.x + t * (end_1.x - start_1.x),
      y: start_1.y + t * (end_1.y - start_1.y)
    }

    # if [start_1.id, target.id].sort == [0,1]
    #   LOGGER.error({id: start_1.id, start: {x: start_1.x, y: start_1.y}, end: {x: end_1.x, y: end_1.y}, target: {x: target.x, y: target.y}, closest: closest_point, t: t}.inspect)
    #   LOGGER.error([target.x - closest_point[:x], target.y - closest_point[:y]].inspect)
    #   LOGGER.error("Distance: #{ (target.x - closest_point[:x]) ** 2 + (target.y - closest_point[:y]) ** 2}")
    #   LOGGER.error("Distance to beat: #{(start_1.radius + target.radius) ** 2}")
    # end
    (target.x - closest_point[:x]) ** 2 + (target.y - closest_point[:y]) ** 2
  end

  def intersect_moving_circle?(entity_1, vector_1, entity_2, vector_2, fudge = 0.1)
    # combine vectors to create single moving circle
    if [entity_1.id, entity_2.id].sort == [0,1]
      e1_end = vector_1 + entity_1
      e2_end = vector_2 + entity_2

      # LOGGER.error({e1: {x: entity_1.x, y: entity_1.y}, e1_end: {x: e1_end.x, y: e1_end.y}, e2: {x: entity_2.x, y: entity_2.y}, e2_end: {x: e2_end.x, y: e2_end.y}})
    end
    combined_vector = vector_1 - vector_2

    distance_to_line2(entity_1, combined_vector + entity_1, entity_2) < (entity_1.radius + entity_2.radius + fudge) ** 2
  end

  # Test whether a line segment and circle intersect.
  # alpha: The start of the line segment. (Needs x, y attributes)
  # omega: The end of the line segment. (Needs x, y attributes)
  # circle: The circle to test against. (Needs x, y, r attributes)
  # fudge: A fudge factor; additional distance to leave between the segment and circle.
  #        (Probably set this to the ship radius, 0.5.)
  # return: True if intersects, False otherwise
  def intersect_segment_circle?(alpha, omega, circle, fudge=0.5)
    dx = omega.x - alpha.x
    dy = omega.y - alpha.y

    a = dx**2 + dy**2
    b = -2 * (alpha.x**2 - alpha.x*omega.x - alpha.x*circle.x + omega.x*circle.x +
              alpha.y**2 - alpha.y*omega.y - alpha.y*circle.y + omega.y*circle.y)

    # c = (alpha.x - circle.x)**2 + (alpha.y - circle.y)**2

    if a == 0.0
      # Start and end are the same point
      return alpha.squared_distance_to(circle) <= (circle.radius + fudge) ** 2
    end

    # Time along segment when closest to the circle (vertex of the quadratic)
    t = [-b / (2 * a), 1.0].min
    if t < 0
      return false
    end

    closest_x = alpha.x + dx * t
    closest_y = alpha.y + dy * t
    squared_closest_distance = Position.new(closest_x, closest_y).squared_distance_to(circle)

    # LOGGER.error("checking collision: #{squared_closest_distance}") if [alpha.id, circle.id].sort == [0,1]

    squared_closest_distance <= (circle.radius + fudge) ** 2
  end
end
