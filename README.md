# KumoKeisei [![Build status](https://badge.buildkite.com/fdbcc9783971fc3c18903abe78ccb4a7a4ebe1bdbbb753c502.svg)](https://buildkite.com/redbubble/kumo-keisei-gem)

A collection of utilities wrapping the libraries for dealing with AWS Cloud Formation.

## Installation

This gem is automatically installed in the rbdevtools container, so any `apply-env` or `deploy` scripts have access to it.

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

#### Ruby Versions

This gem is tested with Ruby (MRI) versions 1.9.3 and 2.2.3.

## Release

1. Upgrade version in VERSION
2. Run ./script/release-gem

## Contributing

1. Fork it ( https://github.com/[my-github-username]/kumo_keisei/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Testing changes

Changes to the gem can be manually tested end to end in a project that uses the gem (i.e. http-wala).

1. First start the dev-tools container: `kumo tools debug non-production`
1. gem install specific_install
1. Re-install the gem: `gem specific_install https://github.com/redbubble/kumo_keisei_gem.git -b <your_branch>`
1. Fire up a console: `irb`
1. Require the gem: `require "kumo_keisei"`
1. Interact with the gem's classes. `KumoKeisei::CloudFormationStack.new(...).apply!`

## Testing changes by deploying a stack

1. Turn off auto-updating by setting `KUMOTOOLS_ENABLE_PULL=1` in `~/.kumo/kumorc`
1. Start the dev-tools container
1. Uninstall the kumo_keisei gem from the container
1. Build the gem locally: `gem build kumo_keisei.gemspec`
1. Copy the gem into the container: `docker cp kumo_keisei-x.x.x.gem <container-id>:/app`
1. Switch to the container shell and install the gem
1. Commit the docker container: `docker commit <container-id> redbubble/kumo-tools:latest`
1. Test the deploy by running `kumo apply-env <env-name>`
