
require 'bblib' unless defined?(BBLib)
require 'socket'
require 'json'
require 'yaml'
require 'securerandom'
require 'openssl'
require 'digest/sha1'

require_relative 'ava/version'
require_relative 'replicant/replicant'
require_relative 'replicant/chained_replicant'
require_relative 'client/client'
require_relative 'controller/controller'

module Ava
end
