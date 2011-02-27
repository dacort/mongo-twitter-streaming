STREAMING_URL = 'https://userstream.twitter.com/2/user.json'
CONSUMER_KEY = ENV['CONSUMER_KEY']
CONSUMER_SECRET = ENV['CONSUMER_SECRET']
ACCESS_TOKEN = ENV['ACCESS_TOKEN']
ACCESS_TOKEN_SECRET = ENV['ACCESS_TOKEN_SECRET']

configure do
  if ENV['MONGOHQ_URL']
    uri = URI.parse(ENV['MONGOHQ_URL'])
    conn = Mongo::Connection.from_uri(ENV['MONGOHQ_URL'])
    DB = conn.db(uri.path.gsub(/^\//, ''))
  else
    DB = Mongo::Connection.new.db("twitter_links")
  end
  
  DB.create_collection("urls")
  DB.create_collection("domains")


end

get '/' do
  content_type 'text/html', :charset => 'utf-8'
  @tweets = DB['urls'].find({}, :limit => 10, :sort => [[ '$natural', :desc ]])
  erb :index
end

def unshorten(tweet)
  puts "Doing some shit with #{tweet['entities']['urls'].inspect}"
  tweet['entities']['urls'].each do |data|
    if data['expanded_url']
      url = URI.parse data['expanded_url']
      puts "Inserting #{url.inspect}"
      DB['urls'].update({:url => url.to_s}, {"$addToSet" => {"users" => {
        "short_url" => data['url'],
        "screen_name" => tweet['user']['screen_name'],
        "user_id" => tweet['user']['id'],
        "status_id" => tweet['id'],
        "link" => "http://twitter.com/#!/#{tweet['user']['screen_name']}/status/#{tweet['id']}"
      }}}, :upsert => true)
      puts "url inserted"
      DB['domains'].update({:domain => url.host}, {"$addToSet" => {"users" => {
        "short_url" => data['url'],
        "screen_name" => tweet['user']['screen_name'],
        "user_id" => tweet['user']['id'],
        "status_id" => tweet['id'],
        "link" => "http://twitter.com/#!/#{tweet['user']['screen_name']}/status/#{tweet['id']}"
      }}}, :upsert => true)
      puts "domain inserted"
    else
      http = EventMachine::HttpRequest.new("http://api.unshort.me/?r=#{data['url']}&t=json").get
     
      http.callback {

        resp = JSON.parse(http.response)
        if resp['success'] == "true"
          url = URI.parse resp['resolvedURL']
          DB['urls'].update({:url => url.to_s}, {"$addToSet" => {"users" => {
            "short_url" => data['url'],
            "screen_name" => tweet['user']['screen_name'],
            "user_id" => tweet['user']['id'],
            "status_id" => tweet['id'],
            "link" => "http://twitter.com/#!/#{tweet['user']['screen_name']}/status/#{tweet['id']}"
          }}}, :upsert => true)
          DB['domains'].update({:domain => url.host}, {"$addToSet" => {"users" => {
            "short_url" => data['url'],
            "screen_name" => tweet['user']['screen_name'],
            "user_id" => tweet['user']['id'],
            "status_id" => tweet['id'],
            "link" => "http://twitter.com/#!/#{tweet['user']['screen_name']}/status/#{tweet['id']}"
          }}}, :upsert => true)
        end
      }

      http.errback {
        puts "Oh, this shit failed!"
      }
    end
  end
end

EM.schedule do
  oauth_consumer = OAuth::Consumer.new(CONSUMER_KEY,CONSUMER_SECRET,:site => 'http://twitter.com')
  oauth_access_token = OAuth::AccessToken.new(oauth_consumer,ACCESS_TOKEN,ACCESS_TOKEN_SECRET)

  request = EM::HttpRequest.new(STREAMING_URL)
  http = request.get(:head => {"User-Agent " => "Booya/1.2"}) do |client|
    oauth_consumer.sign!(client,oauth_access_token)
  end
  buffer = ""
  begin
    http.stream do |chunk|
      buffer += chunk
      # puts "I got a chunk!"
      puts "Buffer is currently #{buffer.inspect}"
      while line = buffer.slice!(/.+\r?\n/)
        puts line.inspect
        next if line == "\r\n"
        tweet = JSON.parse(line)
        # puts tweet.inspect
        next if tweet['entities'].nil?
        unshorten(tweet) if !tweet['entities']['urls'].empty?
      end
    end
  rescue Exception => e
    puts "WTF HAPPENED?! #{e.inspect}"
  end

  http.callback {
    puts "Hunh: #{http.response_header}"
  }
  http.errback { |err|
    puts "IKILLYOU: #{http.inspect}"
  }
end