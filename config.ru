require 'rubygems'
require 'bundler/setup'

require 'sinatra'
require 'em-http'
require 'twitter/json_stream'
require 'json'
require 'mongo'
require 'uri'
require 'app'

run Sinatra::Application