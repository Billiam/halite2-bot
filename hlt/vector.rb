require 'position'

class Vector < Position
  def self.from_angle(angle, magnitude)
    angle = angle * Math::PI / 180

    new(magnitude * Math.cos(angle), magnitude * Math.sin(angle), angle, magnitude)
  end

  def initialize(x, y, angle=0, magnitude=0)
    @x = x
    @y = y
    @angle = angle
    @magnitude = magnitude
  end

  def no_magnitude?
    @x == 0 && @y == 0
  end

  def +(other)
    if other.is_a?(Vector)
      klass = Vector
    elsif other.respond_to?(:x) && other.respond_to?(:y)
      klass = Position
    else
      raise NotImplementedError("Vector cannot be added to #{other.class}")
    end

    klass.new(other.x + x, other.y + y)
  end
end
