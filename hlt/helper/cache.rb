module Cache
  def cache(name)
    define_method(:clear_cache) do
      @_cache = {}
    end unless method_defined? :clear_cache

    fn = instance_method(name)

    define_method(name) do |*args|
      @_cache ||= {}
      return @_cache[name][args] if @_cache.has_key?(name) && @_cache[name].has_key?(args)

      @_cache[name] ||= {}
      @_cache[name][args] = fn.bind(self).call(*args)
    end

    name
  end
end
