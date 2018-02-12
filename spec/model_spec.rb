require 'spec_helper'
require 'memory_profiler'
require 'tempfile'

def Process.rss; `ps -o rss= -p #{Process.pid}`.chomp.to_i; end

describe Ebooks::Model do
  describe 'making tweets' do
    before(:all) { @model = Ebooks::Model.consume(path("data/0xabad1dea.json")) }

    it "generates a tweet" do
      s = @model.make_statement
      expect(s.length).to be <= 280
      puts s
    end

    it "generates an appropriate response" do
      s = @model.make_response("hi")
      expect(s.length).to be <= 280
      expect(s.downcase).to include("hi")
      puts s
    end
  end

  it "consumes, saves and loads models correctly" do
    model = nil

    report = MemoryUsage.report do
      model = Ebooks::Model.consume(path("data/0xabad1dea.json"))
    end
    expect(report.total_memsize).to be < 200000000

    file = Tempfile.new("0xabad1dea")
    model.save(file.path)

    report2 = MemoryUsage.report do
      model = Ebooks::Model.load(file.path)
    end
    expect(report2.total_memsize).to be < 4000000

    expect(model.tokens[0]).to be_a String
    expect(model.sentences[0][0]).to be_a Fixnum
    expect(model.mentions[0][0]).to be_a Fixnum
    expect(model.keywords[0]).to be_a String

    puts "0xabad1dea.model uses #{report2.total_memsize} bytes in memory"
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

    it 'handles strange unicode edge-cases' do
      file = Tempfile.new('unicode')
      file.write("💞\n💞")
      file.close

      model = Ebooks::Model.consume(file.path)
      expect(model.mentions.count).to eq 0
      expect(model.sentences.count).to eq 2

      file.unlink

      p model.make_statement
    end
  end
end
