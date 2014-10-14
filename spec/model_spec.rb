require 'spec_helper'
require 'objspace'

describe Ebooks::Model do
  it "does stuff" do
    model = Ebooks::Model.load(path("data/0xabad1dea.model"))
  end
end
