require 'objspace'

module MemoryUsage
  MemoryReport = Struct.new(:total_memsize)

  def self.full_gc
    GC.start(full_mark: true)
  end

  def self.report(&block)
    rvalue_size = GC::INTERNAL_CONSTANTS[:RVALUE_SIZE]

    full_gc
    GC.disable

    total_memsize = 0

    generation = nil
    ObjectSpace.trace_object_allocations do
      generation = GC.count
      block.call
    end

    ObjectSpace.each_object do |obj|
      next unless generation == ObjectSpace.allocation_generation(obj)
      memsize = ObjectSpace.memsize_of(obj) + rvalue_size
      # compensate for API bug
      memsize = rvalue_size if memsize > 100_000_000_000
      total_memsize += memsize
    end

    GC.enable
    full_gc

    return MemoryReport.new(total_memsize)
  end
end
