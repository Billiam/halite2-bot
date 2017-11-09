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

    entities.find do |foreign_entity|
      next if foreign_entity == ship || foreign_entity == target

      fudge = ship.radius * 2

      if foreign_entity.traveling?
        next true if intersect_segment_segment_width(ship, target, foreign_entity, foreign_entity.next_position, fudge)
      end

      next true if intersect_segment_circle(ship, target, foreign_entity, fudge)

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

  # Test whether a line segment and circle intersect.
  # alpha: The start of the line segment. (Needs x, y attributes)
  # omega: The end of the line segment. (Needs x, y attributes)
  # circle: The circle to test against. (Needs x, y, r attributes)
  # fudge: A fudge factor; additional distance to leave between the segment and circle.
  #        (Probably set this to the ship radius, 0.5.)
  # return: True if intersects, False otherwise
  def intersect_segment_circle(alpha, omega, circle, fudge=0.5)
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

    squared_closest_distance <= (circle.radius + fudge) ** 2
  end

  def position_equal?(a, b)
    a.x == b.x && a.y == b.y
  end

  def segment_to_polygon(start, terminal, width)
    line_angle = start.calculate_angle_between(terminal)

    width_angle = line_angle - 90

    offset_height = Math.sin(width_angle) * width/2
    offset_width = Math.cos(width_angle) * width/2

    # TODO: possibly sort start/terminal lines.
    # Possibly add/subtract by angle

    p1 = Position.new(start.x - offset_width, start.y - offset_height)
    p2 = Position.new(terminal.x - offset_width, terminal.y - offset_height)
    p3 = Position.new(terminal.x + offset_height, terminal.y + offset_height)
    p4 = Position.new(start.x + offset_width, start.y + offset_height)

    [
      [p1, p2],
      [p2, p3],
      [p3, p4],
      [p4, p1],
    ]
  end

  def offset_line(start, terminal, width)
    rectangle = segment_to_polygon(start, terminal, width)

    [rectangle[0], rectangle[2]]
  end

  def intersect_segment_segment_width(start_1, end_1, start_2, end_2, fudge = 0.5)
     # verify we should bother with expensive check
    return false if start_1.squared_distance_to(start_2) > (Game::Constants::MAX_SPEED * 2 + start_1.radius + start_2.radius) ** 2

    # expand lines to polygons with width
    start_line = segment_to_polygon(start_1, end_1, fudge)
    end_line = offset_line(start_2, end_2, fudge)

    start_line.product(end_line).find do |line_a, line_b|
      intersect_segment_segment(line_a[0], line_a[1], line_b[0], line_b[1])
    end
  end

  def intersect_segment_segment(start_1, end_1, start_2, end_2)
    rx = end_1.x - start_1.x
    ry = end_1.y - start_1.y

    sx = end_2.x - start_2.x
    sy = end_2.y - start_2.y

    tx = start_2.x - start_1.x
    ty = start_2.y - start_1.y

    # cross products
    u_numerator = tx * ry - ty * rx
    denominator = rx * sy - ry * sx

    if u_numerator == 0 && denominator == 0
      # lines are collinear
      if position_equal?(start_1, start_2) || position_equal?(start_1, end_2) || position_equal?(end_1, start_2) || position_equal?(end_1, end_2)
        return true
      end

      # Do they overlap? (Are all the point differences in either direction the same sign)
      return [
        start_2.x - start_1.x,
        start_2.x - end_1.x,
        end_2.x - start_1.x,
        end_2.x - end_2.x
      ].all? {|i| i < 0} ||
      [
        start_2.y - start_1.y,
        start_2.y - end_1.y,
        end_2.y - start_1.y,
        end_2.y - end_1.y
      ].all? {|i| i < 0 }
    end

    # lines are parallel
    return false if denominator == 0

    u = u_numerator / denominator
    t = (tx * sy - ty * sx) / denominator

    t.between?(0, 1) && u.between?(0, 1)
  end
end
