require 'spec_helper'
require 'memory_profiler'

def Process.rss; `ps -o rss= -p #{Process.pid}`.chomp.to_i; end

describe Ebooks::Model do
  it "does not use a ridiculous amount of memory" do
    report = MemoryUsage.report do
      model = Ebooks::Model.consume(path("data/0xabad1dea.json"))
    end

    expect(report.total_memsize).to be < 1000000000
  end
end
