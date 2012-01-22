package Cobalt::Plugin::Rehash;
our $VERSION = '0.10';

## HANDLES AND EATS:
##  !rehash
##
##  Rehash langs + channels.conf & plugins.conf
##
##  Does NOT rehash plugin confs
##  Plugins often do some initialization after a conf load
##  Reload them using PluginMgr's !reload function instead.
##
## Also doesn't make very many guarantees regarding consequences ...

use 5.12.1;
use strict;
use warnings;

use Cobalt::Conf;

sub new { bless {}, shift }

sub Cobalt_register {
  my ($self, $core) = splice @_, 0, 2;
  $self->{core} = $core;
  $core->plugin_register( $self, 'SERVER',
    [ 'public_cmd_rehash' ]
  );
  $core->log->info("Registered, commands: !rehash");
  return PLUGIN_EAT_NONE
}

sub Cobalt_unregister {
  my ($self, $core) = splice @_, 0, 2;
  $self->{core} = $core;
  $core->log->info("Unregistered");
  return PLUGIN_EAT_NONE
}

sub Bot_public_cmd_rehash {
  my ($self, $core) = splice @_, 0, 2;

  ## FIXME
  ##  use Cobalt::Conf to grab and reload _core_confs for channels/plugin
  ##  replace $core->cfg->{channels}/{plugins}
  ##  same for langs?

  return PLUGIN_EAT_ALL
}

1;
