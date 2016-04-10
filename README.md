# Meet Ava

Ava allows you to remotely execute code from another Ruby process or another system, similar to DRb (but different). With Ava, you register individual objects and then white or black list methods to then be called remotely via Ava's client class. Ava is both simple and powerful.

See how it all works below! It's easy and (mostly) secure!

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'ava'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install ava

## Usage

Ava is comprised of three classes. The two most important are the Controller (the server) and the Client (the, well, client...). The third is called Replicant and is discussed in further detail below.

### Starting a Server

Starting an Ava Controller is simple:

```ruby
controller = Ava::Controller.new start: true, key: 'test', port: 2016
```
#### Available Params for Initialization
* __start__: When the named argument start is set to true the server is automatically started during initialization. If this is not passed in, _start_ must be called later to initiate the server.
* __key__: The secret key is the password that each client must have in order to authenticate. This is irrelevant if _encrypt_ is set to false as the key will not be needed.
* __encrypt__: Settings this to true will ensure all content sent to clients is encrypted and require the key to authenticate.
* __port__: Sets the TCP port for the server to run on. The default is 2016.

Once the server is up and running it needs to have objects registered to it that it will allow remote control over. Any Ruby object can be added and will be referenced by the name provided during registration. Names must be unique.

```ruby
# Create a couple objects to control
timer = BBLib::TaskTimer.new
cron_parser = BBLib::Cron.new '* * * * * *'

controller.register timer: timer, cron: cron_parser
```

### Setting up a Client

As soon as the items have been registered they can be controlled using a client. The following code illustrates how to create a client to connect to the server shown above.

```ruby
client = Ava::Client.new host: 'localhost', port: 2016, key: 'test'

# Get the list of registered objects from the server
client.registered_objects
#=> [:controller, :timer, :cron]
```

If the client_id is out of sync or you need to reconnect the client you can call the *get_id* method and pass in the server key. This will ask the server for a new client ID and encryption key. This will have to occur if the server is fully restarted as it will purge its known connections and keys. The call will return true if the server accepts the key.

```ruby
client.get_id 'test'
#=> true
```

__NOTE:__The key is never stored in the client, so it must be passed back in with each call to get_id if a new client_id is needed.

### Using the Client

Once a server is running and a client has been connected you may begin making calls the registered objects on the server (or to the server itself). There are a couple of ways to interact. The first is using requests.

#### Requests

Requests can be sent to the server and passed on to its objects in one of two ways. The request method allows an object name, method name and arguments to be sent to the server. The object name must match a registered object to return a result. For example:

```ruby
# Below the first argument is the object name, followed by the method to call on that object.
# Arguments can also be forwarded following the method argument.
client.request :timer, :start
#=> 0

sleep(5)

client.request :timer, :stop
#=> 5
```

Similarly, you can call a method directly on the client that matches the name of the registered object. For example:

```ruby
# Call the :next method on the cron object
client.cron :next
#=> '2016-04-10 03:14:00.000'

# You can also add additional arguments
client.cron :next, count: 2
#=> ['2016-04-10 03:14:00.000', '2016-04-10 03:15:00.000']
```

As shown above, any number of arguments may be called, whether they are ordered and explicit or named parameters. The order passed in is enforced when they are sent to the server.

#### Replicants

Replicants provide an even more convenient means to interact with remote objects hosted by Ava. Replicants are pseudo versions of the objects on the server that can be interacted with as though they existed in the local scope.

To create a Replicant all you need to do is make a call to the client using the object name as the method. See the example below.

```ruby
timer = client.timer
#=> "#<Ava::Replicant>"

# Now, we can interact with the variable timer as though it was created within the client's local scope.
timer.start :my_task
#=> 0
timer.stop :my_task
#=> 0.001213

# This makes passing arguments more natural
c = client.cron

c.next '* * * * * *', count:1, time: Time.now
#=> '2016-04-10 03:22:00.000'
```

_NOTE_: Nearly all methods in a Replicant return the result of the object from the server, so calling _class_ on a Replicant actually returns the class of the object on the server side. Some comparison operations may fail in Ava's current state such as the === operator.

### Environment

Because Ava passes deserialized objects and can reconstitute them on the client side it may be important for the client to have the same classes available as the server. There are a few methods included to help automate this where possible. These features are experimental.

```ruby
# Determine what gems were required on the server
client.required_gems
#=> ["bblib", "json", "psych", "mini_portile2", "nokogiri"]

# List the gems required on the server that are not currently required on the client
client.missings_gems
#=> ["mini_portile2", "nokogiri"]

# Attempt to import missing gems.
client.require_missing_gems
#=> {"mini_portile2" => true, "nokogiri" => true}

# Check for anything missing following the bulk include
client.missing_gems
#=> []
```

The gems must be installed on the client side in order for them to actually be imported manually, so this will not cover all cases. Also, if you prefer not to blindly import everything you can use the missing_gems method to determine what the difference in environments is and manually import only the gems you need.

### Security

Various security functions are available in Ava currently to prevent unwanted access.

#### Methods

Methods can either be blacklisted or whitelisted to allow or disallow access to them via Ava. The whitelist takes precedence over the blacklist, so a whitelisted method will still be available even if it is listed in the blacklist. By default, all methods other than :eval are accessible on objects until explicitly stated in the white or black lists.

Methods may be listed per object or across all objects.

```ruby
# Prevent access to timer's start and stop methods
controller.blacklist :timer, :start, :stop

# Allow access to timer's :tasks method
controller.whitelist :timer, :tasks

# Block access to the method :eval on all objects
controller.blacklist_global :eval

# Block all methods on the cron object
controller.blacklist_all :cron
```

Clients attempting to call blacklisted methods will raise an unauthorized error.

#### IP Filtering

IPs can be allowed via the allow_connections method. IPs can be added as explicit strings or as regular expressions to match by subnets or other. By default all IPs are allowed to connect. If allowed_connections includes any IPs or patterns all other IPs not matching its contents will be blocked.

```ruby
# Allow access to a specific IP or from any IP starting with 10.30
controller.allow_connections '10.10.156.1', /10\.30\.*/

# Passing nil will allow all connections. This is the default behavior.
controller.allow_connections nil
```

#### Encryption

Encryption is enabled by default on the controller. When asking for a client ID a matching encryption key will be sent to the client so that it can decrypt messages from the controller. Each key is specific to the IP of the Client. It is recommended that encryption remain enabled. It can be toggled via the _encrypt_ method on the Controller.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/ava. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
