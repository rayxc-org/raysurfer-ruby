# frozen_string_literal: true

require_relative "raysurfer/version"
require_relative "raysurfer/errors"
require_relative "raysurfer/client"

module Raysurfer
  def self.client(**kwargs)
    Client.new(**kwargs)
  end
end
