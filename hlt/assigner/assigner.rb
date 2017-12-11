class Assigner::Assigner
  class << self
    attr_reader :command_types
    def register(type)
      self.command_types << type
    end

    def command_types
      @command_types ||= []
    end
  end

  def initialize(map)
    @map = map
    @commands = []
    build_commands

    @assigned_ships = []
  end

  def build_commands
    self.class.command_types.each do |type|
      @commands << type.new(@map)
    end
  end

  def update
    @commands.each do |command|
      command.update if command.respond_to?(:update)
    end

    current_ship_ids = @map.me.ships.map(&:id)

    # clean up destroyed ships
    @assigned_ships &= current_ship_ids

    unrecruited_ships = current_ship_ids - @assigned_ships
    unrecruited_ships += self.evict

    return if unrecruited_ships.empty?

    recruited_ships = self.recruit(unrecruited_ships)
    @assigned_ships += recruited_ships
  end

  def execute
    @commands.map(&:execute).flatten.compact
  end

  def recruit(available_ships)
    available_ships.select do |ship|
      @commands.find do |command|
        command.recruit(ship).tap do |rec|
          LOGGER.info("#{ship} assigned to #{command.class.name}") if rec
        end
      end
    end
  end

  def evict
   @commands.map do |command|
     command.evict
   end.flatten.compact
  end
end
