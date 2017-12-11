class Assigner::Assaulter
  attr_reader :ships

  def initialize(map)
    @map = map
    @ships = {}
  end

  def recruit(ship_id)
    ship = @map.ship(ship_id)
    return unless ship
    return if ship.docked?

    enemy = (@map.entities_sorted_by_distance(ship) & @map.enemy_ships).first

    return unless enemy

    @ships[ship_id] = enemy.id

    true
  end

  def evict
    evicted_ships = @ships.inject([]) do |list, (ship_id, enemy_id)|
      ship = @map.ship(ship_id)
      enemy_ship = @map.ship(enemy_id)
      list << ship_id if !ship || ship.docked? || !enemy_ship

      list
    end
    evicted_ships.each {|ship_id| @ships.delete(ship_id) }

    evicted_ships
  end

  def run_ship(ship, enemy_id)
    enemy_ship = @map.ship(enemy_id)

    attack_point = ship.approach_attack(enemy_ship)
    ship.navigate(attack_point, @map, Game::Constants::MAX_SPEED, max_corrections: 18, ignore_ships: true, ignore_my_ships: false, ignore_low_value: false)
  end

  def execute
    @ships.map do |(ship_id, enemy_target_id)|
      run_ship(@map.ship(ship_id), enemy_target_id)
    end.compact
  end
end
