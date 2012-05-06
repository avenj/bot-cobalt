package Bot::Cobalt::Plugin::Extras::Ignore;
our $VERSION = '0.200_48';

use 5.10.1;
use strict;
use warnings;

use Bot::Cobalt;
use Bot::Cobalt::Common;

sub Cobalt_register {
  my ($self, $core) = splice @_, 0, 2;
  
  return PLUGIN_EAT_NONE
}

sub Cobalt_unregister {
  my ($self, $core) = splice @_, 0, 2;
  
  return PLUGIN_EAT_NONE
}

sub Bot_public_cmd_ignore {
  ## ignore list / ignore add / ignore del
  ## glob syntax in `list` ?
}

1;
