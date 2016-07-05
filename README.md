``# KumoKeisei [![Build status](https://badge.buildkite.com/fdbcc9783971fc3c18903abe78ccb4a7a4ebe1bdbbb753c502.svg)](https://buildkite.com/redbubble/kumo-keisei-gem)

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

### Basic Usage

The basic usage will give you a CloudFormation stack named `{application}-{type}-{environment}`. The default type is `nodes`

```ruby
application_name = "myapp"
environment_name = "production"
my_stack = KumoKeisei::Stack.new(stack_name, environment_name)

stack_config = {
  config_path: File.join('/app', 'env', 'config'),
  template_path: File.join('/app', 'env', 'cloudformation', 'myapp.json'),
}

my_stack.apply! stack_config
```

### Changing the stack type

Specify the `type` in an options object passed to the `KumoKeisei::Stack` constructor. For example the following will give you a `myapp-vpc-production` stack e.g:
```ruby
vpc_stack_options = {
  type: 'vpc'
}
vpc_stack = KumoKeisei::Stack.new('myapp', 'production', vpc_stack_options)
```

### Timeouts

You can tune each of the timeouts by passing options to the Stack constructor:
```ruby
stack_options = {
  confirmation_timeout: 0.5,
  waiter_delay: 20,
  waiter_attempts: 90,
}

KumoKeisei::Stack.new(stack_name, environment_name, stack_options)
```

*confirmation_timeout*: how long to wait for a user to confirm delete actions
*waiter_delay*: how long to wait between checking Cfn for completion of delete and update actions
*waiter_attempts*: how many times to retry checking that a Cfn delete or update was successful

### CloudFormation Templates, Parameter Templates and Configuration Files

The **CloudFormation Template** is a json file (e.g. app.json) describing a related set of Amazon resources using the [CloudFormation DSL](http://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/gettingstarted.templatebasics.html). You pass it it's location by specifying the `template_path` in the object passed to `apply!`,

The **Parameter Template** is a file prescribing the Cfn parameters [Embedded Ruby](http://www.stuartellis.eu/articles/erb/) form. It must be in the same folder holding the CloudFormation Template, named `{app_name}.yml.erb`.

The **Configuration Files** are a set of files in `yml` format prescribing configuration values for a given environment. They must be in the folder given by `config_path`, in the form of `{environment}.yml` and `{environment}_secrets.yml`

[KumoKi](https://github.com/redbubble/kumo_ki_gem) will be used to decrypt the _secrets_ files.

### Configuration Hierarchy

Configuration will be loaded from the following sources:

1. `common.yml` and `common_secrets.yml` if they exist.
2. `{environment}.yml` and `{environment}_secrets.yml` or `development.yml` and `development_secrets.yml` if environment specific config does not exist.

### Injecting Configuration

You can also inject configuration at run time by adding it to the object provided to the `apply!` call:

```ruby
stack_config = {
  config_path: File.join('/app', 'env', 'config'),
  template_path: File.join('/app', 'env', 'cloudformation', 'myapp.json'),
  injected_config: {
    'Seed' => random_seed,
  }
}
stack.apply!(stack_config)
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
1. Interact with the gem's classes. `KumoKeisei::Stack.new(...).apply!`
