# Capataz

Provides Ruby code execution control by defining rules for syntax and runtime behavior.   

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'capataz'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install capataz

## Usage

Take for example the following Ruby code:

```ruby
class A
  attr_reader :value, :secret_value
  def initialize
    @value = rand(10)
    @secret_value = rand(value)
  end
end

class B < A; end
```

So you can configure your code syntax and runtime rules
```ruby
Capataz.config do

  deny_declarations_of :module, :class

  deny_invoke_of :constantize

  allowed_constants A

  deny_for A, :secret_value
  
  maximum_iterations 100
  
  maximum_invocations_of '+': 5
end
```

And then you can control your Ruby code execution by evaluating it with `Capataz` 

```ruby
Capataz.eval <<-RUBY
class C
end
RUBY #ERROR: can not define classes

Capataz.eval <<-RUBY
B.new
RUBY #ERROR: Illegal access to constant B 

Capataz.eval <<-RUBY
'B'.constantize.new
RUBY #ERROR: invoking method constantize is not allowed

Capataz.eval <<-RUBY
A.new.value
RUBY # 5 (a random value)

Capataz.eval <<-RUBY
A.new.secret_value
RUBY #ERROR: undefined method secret_value for #<A:0x000000022e7960>

Capataz.eval <<-RUBY
s = 0
100.times { s += 1 }
s
RUBY # 100

Capataz.eval <<-RUBY
s = 0
101.times { s += 1 }
s
RUBY #ERROR: Maximum allowed iterations exceeded

Capataz.eval <<-RUBY
s = 0
10.times { 10.times { s += 1 } }
s
RUBY # 100

Capataz.eval <<-RUBY
s = 0
11.times { 10.times { s += 1 } }
s
RUBY #ERROR: Maximum allowed iterations exceeded

Capataz.eval <<-RUBY
s = 0
5.times { s = s + 1 }
s
RUBY # 5

Capataz.eval <<-RUBY
s = 0
6.times { s = s + 1 }
s
RUBY #ERROR: Maximum allowed invocations for '+' exceeded

Capataz.eval <<-RUBY
[1,2,3,4,5,6].inject(&:+)
RUBY # 21 (the + operator is invoked 5 times to sum 6 numbers)

Capataz.eval <<-RUBY
[1,2,3,4,5,6,7].inject(&:+)
RUBY #ERROR: Maximum allowed invocations for '+' exceeded
```


## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release` to create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

1. Fork it ( https://github.com/macarci/capataz/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
