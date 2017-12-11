require 'helper/cache'

class Assigner::Stalker
  extend Cache

  attr_reader :ships

  def initialize(map)
    @map = map
    @ships = {}
  end

  def recruit(ship_id)
    raise 'Already recruited' if @ships.key?(ship_id)

    ship = @map.ship(ship_id)
    return unless ship
    return if ship.docked? || max_assigned?

    target = @map.enemy_ships_in_range(ship, Game::Constants::MAX_SPEED * 9).find do |nearby_ship|
      next if @ships.value?(nearby_ship.owner.id)

      true
    end

    return unless target
    @ships[ship_id] = target.owner.id

    true
  end

  def evict
    evicted_ships = @ships.inject([]) do |list, (ship_id, enemy_id)|
      list << ship_id if @map.active_enemies.none? {|enemy| enemy.id == enemy_id} || !@map.ship(ship_id)

      list
    end
    evicted_ships.each {|ship_id| @ships.delete(ship_id) }

    while @ships.size > [0, max_assignments].max do
      last_key = @ships.keys.last
      evicted_ships << last_key
      @ships.delete(last_key)
    end

    evicted_ships
  end

  def update
    clear_cache
  end

  def run_ship(ship, enemy_target_id)
    enemy_target = @map.player(enemy_target_id)

    closest_enemy_ships = @map.entities_sorted_by_distance(ship) & enemy_target.ships

    ship_command = closest_enemy_ships.select(&:docked?).lazy.map do |target_ship|
      attack_point = ship.approach_attack(target_ship)
      ship.navigate(attack_point, @map, Game::Constants::MAX_SPEED, max_corrections: 18)
    end.find(&:itself)

    return ship_command if ship_command

    # no docked ships, follow enemy ships
    stalked_ship = closest_enemy_ships.first
    nav_point = ship.closest_point_to(stalked_ship, Game::Constants::MAX_SPEED * 2)
    ship.navigate(nav_point, @map, Game::Constants::MAX_SPEED, max_corrections: 18)
  end

  def execute
    @ships.map do |(ship_id, enemy_target_id)|
      run_ship(@map.ship(ship_id), enemy_target_id)
    end.compact
  end

  private

  def max_assigned?
    @ships.size >= max_assignments
  end

  cache def max_assignments
    [Math.log(@map.me.ships.size, 2.4).floor, @map.active_enemies.size].min
  end
end
