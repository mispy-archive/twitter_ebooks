require 'spec_helper'
require 'memory_profiler'
require 'tempfile'

def Process.rss; `ps -o rss= -p #{Process.pid}`.chomp.to_i; end

describe Ebooks::Model do
  describe 'making tweets' do
    before(:all) { @model = Ebooks::Model.consume(path("data/0xabad1dea.json")) }

    it "generates a tweet" do
      s = @model.make_statement
      expect(s.length).to be <= 140
      puts s
    end

    it "generates an appropriate response" do
      s = @model.make_response("hi")
      expect(s.length).to be <= 140
      expect(s.downcase).to include("hi")
      puts s
    end
  end

  it "does not use a ridiculous amount of memory" do
    report = MemoryUsage.report do
      model = Ebooks::Model.consume(path("data/0xabad1dea.json"))
    end

    expect(report.total_memsize).to be < 1000000000
  end

  describe '.consume' do
    it 'interprets lines with @ as mentions' do
      file = Tempfile.new('mentions')
      file.write('@m1spy hello!')
      file.close

      model = Ebooks::Model.consume(file.path)
      expect(model.sentences.count).to eq 0
      expect(model.mentions.count).to eq 1

      file.unlink
    end

    it 'interprets lines without @ as statements' do
      file = Tempfile.new('statements')
      file.write('hello!')
      file.close

      model = Ebooks::Model.consume(file.path)
      expect(model.mentions.count).to eq 0
      expect(model.sentences.count).to eq 1

      file.unlink
    end
  end
end
