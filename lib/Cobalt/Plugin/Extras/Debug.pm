package Cobalt::Plugin::Extras::Debug;
our $VERSION = '0.002';

## Simple 'dump to stdout' debug functions
##
## IMPORTANT: NO ACCESS CONTROLS!
## Intended for debugging, you don't want to load on a live bot.
##
## Dumps to STDOUT, there is no IRC output.
##
## Commands:
##  !dumpcfg
##  !dumpstate
##  !dumptimers
##  !dumpservers
##  !dumplangset
##
##  - avenj@cobaltirc.org

use Data::Dumper;
use Object::Pluggable::Constants qw/ PLUGIN_EAT_NONE /;

sub new { bless {}, shift }

sub Cobalt_register {
  my ($self, $core) = splice @_, 0, 2;
  $self->{core} = $core;
  my @events = map { 'public_cmd_'.$_ } 
    qw/
      dumpcfg 
      dumpstate 
      dumptimers 
      dumpservers
      dumplangset
    / ;
  $core->plugin_register( $self, SERVER,
    [ @events ] 
  );
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
  print(Dumper $core->cfg);
  return PLUGIN_EAT_NONE
}

sub Bot_public_cmd_dumpstate {
  my ($self, $core) = splice @_, 0, 2;
  $core->log->warn("dumpstate called (debugger)");
  print(Dumper $core->State);
  return PLUGIN_EAT_NONE
}

sub Bot_public_cmd_dumptimers {
  my ($self, $core) = splice @_, 0, 2;
  $core->log->warn("dumptimers called (debugger)");
  print(Dumper $core->TimerPool);
  return PLUGIN_EAT_NONE
}

sub Bot_public_cmd_dumpservers {
  my ($self, $core) = splice @_, 0, 2;
  $core->log->warn("dumpservers called (debugger)");
  print(Dumper $core->Servers);
  return PLUGIN_EAT_NONE
}

sub Bot_public_cmd_dumplangset {
  my ($self, $core) = splice @_, 0, 2;
  $core->log->warn("dumplangset called (debugger)");
  print(Dumper $core->lang);
  return PLUGIN_EAT_NONE
}

1;
