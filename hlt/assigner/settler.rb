class Assigner::Settler
  attr_reader :ships

  def initialize(map)
    @map = map
    @ships = {}
  end

  def recruit(ship_id)
    ship = @map.ship(ship_id)
    return unless ship
    return if ship.docked?

    planets_by_distance = @map.entities_sorted_by_distance(ship).select { |entity| entity.is_a? Planet }.first(4)
    available_planet = planets_by_distance.find do |planet|
      [@map.me, nil].include?(planet.owner) &&
        requires_reinforcement?(planet) &&
        ship.squared_distance_to(planet) < (planet.radius + Game::Constants::MAX_SPEED * 3) ** 2
    end

    return unless available_planet
    @ships[ship_id] = available_planet.id

    true
  end

  def evict
    evicted_ships = @ships.inject([]) do |list, (ship_id, planet_id)|
      ship = @map.ship(ship_id)

      planet = @map.planet(planet_id)

      list << ship_id if !ship || ship.docked? || ! [nil, @map.me].include?(planet.owner) || (planet.full? || planet.closest_enemies(@map, Game::Constants::MAX_SPEED * 4 + planet.radius).to_a.size == 0)
      list
    end
    evicted_ships.each {|ship_id| @ships.delete(ship_id) }

    evicted_ships
  end

  def run_ship(ship, planet_id)
    planet = @map.planet(planet_id)

    defend_planet = planet.closest_enemies(@map, Game::Constants::MAX_SPEED * 4 + planet.radius).map do |target_ship|
      attack_point = ship.approach_attack(target_ship)

      ship.navigate(attack_point, @map, Game::Constants::MAX_SPEED, max_corrections: 18, ignore_ships: true, ignore_my_ships: false, ignore_low_value: false)
    end.find(&:itself)
    return defend_planet if defend_planet

    return ship.dock(planet) if ship.can_dock?(planet)

    docking_position = ship.approach_closest_point(planet, Game::Constants::DOCK_RADIUS)
    ship.navigate(docking_position, @map, Game::Constants::MAX_SPEED, max_corrections: 18, ignore_ships: true, ignore_my_ships: false, ignore_low_value: false)
  end

  def execute
    @ships.map do |(ship_id, enemy_target_id)|
      run_ship(@map.ship(ship_id), enemy_target_id)
    end.compact
  end

  private

  def requires_reinforcement?(planet)
    assigned = planet.docked_ships.size + @ships.count{ |(_ship_id, planet_id)| planet_id == planet.id }
    required = planet.docking_spots + planet.closest_enemies(@map, Game::Constants::MAX_SPEED * 4 + planet.radius).to_a.size

    assigned < required
  end
end
