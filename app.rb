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
  # oauth_consumer = OAuth::Consumer.new(CONSUMER_KEY,CONSUMER_SECRET,:site => 'http://twitter.com')
  # oauth_access_token = OAuth::AccessToken.new(oauth_consumer,ACCESS_TOKEN,ACCESS_TOKEN_SECRET)

  stream = Twitter::JSONStream.connect(
    :host    => 'userstream.twitter.com',
    :path    => '/2/user.json',
    :ssl     => true,
    :oauth => {
       :consumer_key    => CONSUMER_KEY,
       :consumer_secret => CONSUMER_SECRET,
       :access_key      => ACCESS_TOKEN,
       :access_secret   => ACCESS_TOKEN_SECRET
     }
  )

  stream.each_item do |item|
    tweet = JSON.parse(item)
    # puts tweet.inspect
    next if tweet['entities'].nil?
    unshorten(tweet) if !tweet['entities']['urls'].empty?
  end

  stream.on_error do |message|
    $stdout.print "error: #{message}\n"
    $stdout.flush
  end

end