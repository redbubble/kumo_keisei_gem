# KumoKeisei

A collection of utilities wrapping the libraries for dealing with AWS Cloud Formation.

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
stack_name = "my_awesome_stack"
template = "./cloudformation/environment_template.json"
template_params = "./cloudformation/environments/production/params.json"

KumoKeisei::CloudFormationStack.new(stack_name, template, template_params).apply!
```

## Dependencies

#### AWS CLI

This gem requires the aws cli to be installed. If you don't have it, it won't work!!

#### Ruby Versions

This gem is tested with Ruby (MRI) versions 1.9.3 and 2.2.3.

## Release

1. Upgrade version in kumo_keisei.rb
2. Run ./script/release-gem

## Contributing

1. Fork it ( https://github.com/[my-github-username]/kumo_keisei/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
