module Cache
  def cache(name)
    define_method(:clear_cache) do
      @_cache = {}
    end unless method_defined? :clear_cache

    fn = instance_method(name)

    define_method(name) do |*args|
      @_cache ||= {}
      return @_cache[name] if @_cache.has_key?(name)
      @_cache[name] = fn.bind(self).call(*args)
    end

    name
  end
end
