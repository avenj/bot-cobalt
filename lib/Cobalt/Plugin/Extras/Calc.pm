package Cobalt::Plugin::Calc;

use 5.12.1;
use strict;
use warnings;

use Object::Pluggable::Constants qw/ :ALL /;

## Commands:


sub new { bless( {}, shift ) }

sub Cobalt_register {
  my ($self, $core) = splice @_, 0, 2;
  $core->plugin_register($self, 'SERVER',
    [ 'public_msg' ],
  );
  $core->log->info("Registered");
  return PLUGIN_EAT_NONE
}

sub Cobalt_unregister {
  my ($self, $core) = splice @_, 0, 2;
  $core->log->info("Unregistering");
  return PLUGIN_EAT_NONE
}


sub Bot_public_msg {
  my ($self, $core) = splice @_, 0, 2;
  return PLUGIN_EAT_NONE
}

1;
