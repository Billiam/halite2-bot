class Assigner::Conqueror
  attr_reader :ships

  def initialize(map)
    @map = map
    @ships = {}
  end

  def recruit(ship_id)
    ship = @map.ship(ship_id)
    return unless ship
    return if ship.docked?

    planet = weighted_planets(ship, distance: 1, docked: -1.5, defense: 2, slots: -2).find do |sorted_planet|
      next unless requires_reinforcement?(sorted_planet)

      sorted_planet
    end

    return unless planet

    @ships[ship_id] = planet.id

    true
  end

  def evict
    evicted_ships = @ships.inject([]) do |list, (ship_id, planet_id)|
      planet = @map.planet(planet_id)
      planet_needs_defense = !planet.full? || planet.closest_enemies(@map, Game::Constants::MAX_SPEED * 4 + planet.radius).to_a.size > 0

      ship = @map.ship(ship_id)
      list << ship_id if !ship || ship.docked? || !planet_needs_defense

      list
    end
    evicted_ships.each {|ship_id| @ships.delete(ship_id) }

    evicted_ships
  end

  def run_ship(ship, planet_id)
    planet = @map.planet(planet_id)

    # attack docked ships
    if planet.owned? && planet.owner != @map.me

      return @map.sort_closest(ship, planet.docked_ships).lazy.map do |target_ship|
        attack_point = ship.approach_closest_point(target_ship, Game::Constants::WEAPON_RADIUS - 0.25)
        ship.navigate(attack_point, @map, Game::Constants::MAX_SPEED, max_corrections: 18, ignore_ships: true, ignore_my_ships: false, ignore_low_value: false)
      end.find(&:itself)
    end

    # attack non-docked ships (before docking)
    defend_planet = planet.closest_enemies(@map, Game::Constants::MAX_SPEED * 4 + planet.radius).map do |target_ship|
      attack_point = ship.approach_attack(target_ship)

      ship.navigate(attack_point, @map, Game::Constants::MAX_SPEED, max_corrections: 18, ignore_ships: true, ignore_my_ships: false, ignore_low_value: false)
    end.find(&:itself)

    return defend_planet if defend_planet

    # dock
    return ship.dock(planet) if ship.can_dock?(planet)

    docking_position = ship.approach_closest_point(planet, Game::Constants::DOCK_RADIUS - 0.25)

    ship.navigate(docking_position, @map, Game::Constants::MAX_SPEED, max_corrections: 18, ignore_ships: true, ignore_my_ships: false, ignore_low_value: false)
  end

  def execute
    @ships.map do |(ship_id, enemy_target_id)|
      run_ship(@map.ship(ship_id), enemy_target_id)
    end.compact
  end

  private

  def weighted_planets(ship, distance: 1, defense: 1, docked: 1, slots: 1)
    planet_assignment_count = @ships.group_by {|_ship_id, planet_id| planet_id }.map {|planet_id, results| [planet_id, results.size] }.to_h
    planet_assignment_count.default = 0

    @map.enemy_planets.sort_by do |planet|
      slot_value = 0

      if [nil, @map.me].include?(planet.owner)
        docked_and_assigned = planet.docked_ships.size + planet_assignment_count[planet.id]
        full = planet.docking_spots - docked_and_assigned <= 0
        ships_to_consider = full ? docked_and_assigned : planet.docked_ships.size
        slot_value = planet.docking_spots - ships_to_consider
      end

      [
        (ship.calculate_distance_between(planet) * distance * 0.05) +
        (planet.docked_ships.size * docked) +
        (@map.planetary_defense[planet] * defense) +
        slot_value * slots,
        planet.id
      ]
    end
  end

  def requires_reinforcement?(planet)
    assigned = planet.docked_ships.size + @ships.count{ |(_ship_id, planet_id)| planet_id == planet.id }
    required = planet.docking_spots + planet.closest_enemies(@map, Game::Constants::MAX_SPEED * 6 + planet.radius).to_a.size + (planet.owner == @map.me ? 0 : planet.docked_ships.size * 2)

    assigned < required
  end
end
