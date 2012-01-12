package Cobalt::Plugin::Games;

use 5.12.1;
use strict;
use warnings;

use Object::Pluggable::Constants qw/ :ALL /;


## FIXME Read in config of games to load & command mapping


sub new { bless( {}, shift ) }

sub Cobalt_register {
  my ($self, $core) = @_;

  $core->plugin_register($self, 'SERVER',
    [ 'public_msg' ],
  );

  $core->log->info("Registered");
  return PLUGIN_EAT_NONE
}

sub Cobalt_unregister {
  my ($self, $core) = @_;
  $core->log->info("Unregistering core IRC plugin");
  return PLUGIN_EAT_NONE
}


sub Bot_public_msg {
  my ($self, $core) = splice @_, 0, 2;
  my $context = ${$_[0]};
  my $msg = ${$_[1]};

  return PLUGIN_EAT_NONE
}

1;
