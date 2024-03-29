require 'entity'
require 'position'
require 'vector'

# A ship in the game.

# id: The ship ID.
# x: The ship x-coordinate.
# y: The ship y-coordinate.
# radius: The ship radius.
# owner: The player ID of the owner, if any. If nil, the ship is not owned.
# health: The ship's remaining health.
# docking_status: one of (UNDOCKED, DOCKED, DOCKING, UNDOCKING)
# planet: The ID of the planet the ship is docked to, if applicable.
class Ship < Entity

  class DockingStatus
    UNDOCKED  = 0
    DOCKING   = 1
    DOCKED    = 2
    UNDOCKING = 3
    ALL = [UNDOCKED, DOCKING, DOCKED, UNDOCKING].freeze
  end

  attr_reader :health, :docking_status, :planet, :vector

  def initialize(player_id, ship_id, x, y, hp, status, progress, planet_id)
    @id = ship_id
    @x, @y = x, y
    @owner = player_id
    @radius = Game::Constants::SHIP_RADIUS
    @health = hp
    @docking_status = status
    @docking_progress = progress
    @planet = planet_id if @docking_status != DockingStatus::UNDOCKED
    @vector = Vector.new(0, 0)
  end

  def traveling?
    !@vector.no_magnitude?
  end

  def next_position
    @vector + self
  end

  def docked?
    self.docking_status != DockingStatus::UNDOCKED
  end

  # Generate a command to accelerate this ship.
  # magnitude: The speed through which to move the ship
  # angle: The angle to move the ship in. Should always be a positive number, but %360 fixes that.
  # return: The command string to be passed to the Halite engine.
  def thrust(magnitude, angle)
    raise "Ship should not thrust twice" if @has_thrust
    @has_thrust = true

    thrust_angle = Integer(angle % 360)
    thrust_magnitude = Integer(magnitude)

    return :skip if thrust_magnitude == 0

    @vector = Vector.from_angle(thrust_angle, thrust_magnitude)
    "t #{id} #{thrust_magnitude} #{thrust_angle}"
  end

  # Generate a command to dock to a planet.
  # planet: The planet object to dock to
  # return: The command string to be passed to the Halite engine.
  def dock(planet)
    "d #{id} #{planet.id}"
  end

  # Generate a command to undock from the current planet.
  # return: The command string to be passed to the Halite engine.
  def undock
    "u #{id}"
  end

  # Determine wheter a ship can dock to a planet
  # planet: the Planet you are attempting to dock at
  # return: true if can dock, false if no
  def can_dock?(planet)
    squared_distance_to(planet) <= (planet.radius + Game::Constants::DOCK_RADIUS + Game::Constants::SHIP_RADIUS) ** 2 && ! planet.full?
  end

  def can_attack?(ship)
    squared_distance_to(ship) <= (Game::Constants::WEAPON_RADIUS + Game::Constants::SHIP_RADIUS * 2) ** 2
  end

  # Move a ship to a specific target position (Entity).
  # It is recommended to place the position itself here, else navigate will
  # crash into the target. If avoid_obstacles is set to True (default), it
  # will avoid obstacles on the way, with up to max_corrections corrections.
  # Note that each correction accounts for angular_step degrees difference,
  # meaning that the algorithm will naively try max_correction degrees before
  # giving up (and returning None). The navigation will only consist of up to
  # one command; call this method again in the next turn to continue navigating
  # to the position.

  # target: The Entity to which you will navigate
  # map: The map of the game, from which obstacles will be extracted
  # speed: The (max) speed to navigate. If the obstacle is near, it will adjust
  # avoid_obstacles: Whether to avoid the obstacles in the way (simple
  #                  pathfinding).
  # max_corrections: The maximum number of degrees to deviate per turn while
  #                  trying to pathfind. If exceeded returns None.
  # angular_step: The degree difference to deviate if the path has obstacles
  # ignore_ships: Whether to ignore ships in calculations (this will make your
  #               movement faster, but more precarious)
  # ignore_planets: Whether to ignore planets in calculations (useful if you
  #                 want to crash onto planets)
  # return: The command trying to be passed to the Halite engine or nil if
  #         movement is not possible within max_corrections degrees.
  def navigate(target,
      map,
      speed,
      avoid_obstacles: true,
      max_corrections: 90,
      angular_step: 1,
      ignore_ships: false,
      ignore_planets: false,
      ignore_my_ships: false,
      ignore_low_value: false
  )
    return if max_corrections <= 0
    distance = calculate_distance_between(target)
    angle = calculate_angle_between(target)

    ignore = []
    ignore << :ships if ignore_ships
    ignore << :low_value if ignore_low_value
    ignore << :planets if ignore_planets
    ignore << :my_ships if ignore_my_ships

    if avoid_obstacles && map.any_obstacles_between?(self, target, ignore)
      angle_addition = (angular_step.even? ? -0.5 : 0.5) * ( angular_step ** 2 )

      delta_radians = (angle + angle_addition)/180 * Math::PI
      new_target_dx = Math.cos(delta_radians) * distance
      new_target_dy = Math.sin(delta_radians) * distance
      new_target = Position.new(x + new_target_dx, y + new_target_dy)

      return navigate(
        new_target,
        map,
        speed,
        avoid_obstacles: true,
        max_corrections: max_corrections-1,
        angular_step: angular_step + 1,
        ignore_ships: ignore_ships,
        ignore_planets: ignore_planets,
        ignore_my_ships: ignore_my_ships,
        ignore_low_value: ignore_low_value
      )
    end

    speed = [distance.ceil, speed].min
    thrust(speed, angle)
  end

  # Uses the IDs of players and planets and populates the owner and planet params
  # with the actual objects representing each, rather than the IDs.
  # players: hash of Player objects keyed by id
  # planets: hash of Planet objects keyed by id
  def link(players, planets)
    @owner = players[@owner]
    @planet = planets[@planet]
  end

  # Parse multiple ship data, given tokenized input
  # player_id: The ID of the player who owns the ships
  # tokens: The tokenized input
  # return: the hash of Ships and unused tokens
  def self.parse(player_id, tokens)
    ships = {}
    count_of_ships = Integer(tokens.shift)

    count_of_ships.times do
      ship_id, ship, tokens = parse_single(player_id, tokens)
      ships[ship_id] = ship
    end

    return ships, tokens
  end

  # Parse a single ship's data, given tokenized input from the game
  # player_id: The ID of the player who owns the ships
  # tokens: The tokenized input
  # return: the ship id, ship object, and unused tokens
  def self.parse_single(player_id, tokens)
    # The _ variables are deprecated in this implementation, but the data is still
    # being sent from the Halite executable.
    # They were: velocity x, velocity y, and weapon cooldown
    id, x, y, hp, _, _, status, planet, progress, _, *tokens = tokens

    id = Integer(id)

    # player_id, ship_id, x, y, hp, docking_status, progress, planet_id
    ship = Ship.new(player_id, id,
                    Float(x), Float(y),
                    Integer(hp),
                    Integer(status), Integer(progress),
                    Integer(planet))
    return id, ship, tokens
  end
end
