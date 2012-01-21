package Cobalt::Plugin::Extras::Debug;
our $VERSION = '0.001';

## Simple 'dump to stdout' debug functions
## - avenj@cobaltirc.org

use Data::Dumper;
use Object::Pluggable::Constants qw/ PLUGIN_EAT_NONE /;

sub new { bless {}, shift }

sub Cobalt_register {
  my ($self, $core) = splice @_, 0, 2;
  $self->{core} = $core;
  $core->log->info("Loaded DEBUG");
  $core->log->warn(
    "You probably don't want to use this plugin on a live bot."
  );
  return PLUGIN_EAT_NONE
}

sub Cobalt_unregister {
  my ($self, $core) = splice @_, 0, 2;
  $core->log->info("Unloaded DEBUG");
  return PLUGIN_EAT_NONE
}

sub Bot_public_cmd_dumpcfg {
  my ($self, $core) = splice @_, 0, 2;
  $core->log->warn("dumpcfg called (debugger)");
  print Dumper $core->cfg;
  return PLUGIN_EAT_NONE
}

sub Bot_public_cmd_dumpstate {
  my ($self, $core) = splice @_, 0, 2;
  $core->log->warn("dumpstate called (debugger)");
  print Dumper $core->State;
  return PLUGIN_EAT_NONE
}

1;
