#!/usr/bin/env ruby
# encoding: utf-8

require 'json'

freqmap = {}

data = File.read("data/ANC-all-count.txt")
data = data.unpack("C*").pack("U*")

data.lines.each do |l|
  vals = l.split("\t")
  
  freqmap[vals[0]] = vals[-1].to_i
end

File.open("data/wordfreq.json", 'w') do |f|
  f.write(JSON.dump(freqmap))
end
