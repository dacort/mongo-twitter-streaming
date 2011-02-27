require 'rubygems'
require 'bundler/setup'

require 'sinatra'
require 'em-http'
require 'json'
require 'mongo'
require 'uri'
require 'oauth/client/em_http'
require 'app'

run Sinatra::Application