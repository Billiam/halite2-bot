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
    output_klass(other).new(x + other.x, y + other.y)
  end

  def -(other)
    output_klass(other).new(x - other.x, y - other.y)
  end

  def to_s
    "Vector: (#{x}, #{y}) a: #{@angle * (180/Math::PI)} m: #{@magnitude}"
  end

  private
  def output_klass(other)
    if other.is_a?(Vector)
      Vector
    elsif other.respond_to?(:x) && other.respond_to?(:y)
      Position
    else
      raise NotImplementedError("Vector cannot be added to #{other.class}")
    end
  end
end
