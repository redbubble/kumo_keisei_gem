# KumoKeisei [![Build status](https://badge.buildkite.com/fdbcc9783971fc3c18903abe78ccb4a7a4ebe1bdbbb753c502.svg)](https://buildkite.com/redbubble/kumo-keisei-gem) [![Code Climate](https://codeclimate.com/github/redbubble/kumo_keisei_gem/badges/gpa.svg)](https://codeclimate.com/github/redbubble/kumo_keisei_gem)

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

### Basic Usage

The basic usage will give you a CloudFormation stack named `{application}-{environment}`.

```ruby
application_name = "myapp"
environment_name = "production"
my_stack = KumoKeisei::Stack.new(application_name, environment_name)

stack_config = {
  config_path: File.join('/app', 'env', 'config'),
  template_path: File.join('/app', 'env', 'cloudformation', 'myapp.json'),
}

my_stack.apply! stack_config
```

### Stack Naming

We are using APPNAME-ENVNAME (e.g `redbubble-staging`) as our naming convention for cloudformation stacks.

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

The **CloudFormation Template** is a json file (e.g. app.json) describing a related set of Amazon resources using the [CloudFormation DSL](http://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/gettingstarted.templatebasics.html). You pass the location by specifying the `template_path` in the object passed to `apply!`,

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

## Upgrading from `KumoKeisei::CloudFormationStack` to `KumoKeisei::Stack`

`KumoKeisei::CloudFormationStack` is deprecated and should be replaced with a `KumoKeisei::Stack` which has an environment object (`KumoConfig::EnvironmentConfig`).

Previously you would pass through cloudformation template and json parameter files directly.

E.g.:
```ruby
  app_name = "foo"
  environment_name = "staging"
  stack = KumoKeisei::CloudFormationStack.new("#{app_name}-#{environment_name}", "./cloudformation/#{app_name}.json", "./cloudformation/#{environment_name}.json")
  stack.apply!
```

With the new `Stack` object, you need to pass in the location of the template and config:
```ruby
app_name = "foo"
environment_name = "staging"

stack_config = {
  config_path: File.join('/app', 'env', 'config'),
  template_path: File.join('/app', 'env', 'cloudformation', '#{app_name}.json'),
}

stack = KumoKeisei::Stack.new(app_name, environment_name)
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

### Automated AWS Integration Tests

You can test the Cloudformation responsibilities of this gem by extending the integration tests at `spec/integration`.

To run these tests you need a properly configured AWS environment (with AWS_DEFAULT_REGION, AWS_ACCESS_KEY and AWS_SECRET_ACCESS_KEY set) and then run `./script/integration_test.sh`.

If you run this within a Buildkite job then you will have a stack named "kumokeisei-test-$buildnumber" created and torn down for each integration test context. If you run this outside of a Buildkite job then the stack will be named "kumokeisei-test-$username".
