require 'vendor/rquad'

class Collider
  def initialize(width, height)
    @width = width
    @height = height
    @tree = RQuad::QuadTree.new(RQuad::Vector.new(0, height), RQuad::Vector.new(width, 0))
  end

  def add(element)
    @tree.add(
      RQuad::QuadTreePayload.new(
        RQuad::Vector.new(element.x.to_i, element.y.to_i),
        element
      )
    )
  end

  def nearby(position, radius)
    @tree.payloads_in_region(
      RQuad::Vector.new([position.x - radius, 0].max, [position.y + radius, @height].min),
      RQuad::Vector.new([position.x + radius, @width].min, [position.y - radius, 0].max)
    ).map(&:data)
  end
end
