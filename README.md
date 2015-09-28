# KumoKeisei

A collection of utilities for dealing with AWS Cloud Formation.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'kumo_keisei'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install kumo_keisei

## Usage

```ruby
cf_opts = {
  stack: sqs_stack_name,
  base_template: "./cloudformation/sqs.json",
  env_template: "./cloudformation/environments/production.json"
}
KumoKeisei::CloudFormationStack.new(cf_opts).apply!
```

## Release

1. Upgrade version in version.rb
2. Run ./script/release-gem

## Contributing

1. Fork it ( https://github.com/[my-github-username]/kumo_keisei/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
