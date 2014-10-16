require 'spec_helper'
require 'memory_profiler'

describe Ebooks::Model do
  it "does not use a ridiculous amount of memory" do
    RubyProf.start
    Ebooks::Model.consume(path("data/0xabad1dea.json"))
    result = RubyProf.stop

    require 'pry'; binding.pry

    expect(report.total_retained).to be < 100000
  end
end
