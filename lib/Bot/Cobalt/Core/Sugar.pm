package Bot::Cobalt::Core::Sugar;

use 5.10.1;
use strictures 1;
use Carp;

use base 'Exporter';
our @EXPORT = qw/
  core
  broadcast
  register
  unregister
  logger
/;

sub core {
  require Bot::Cobalt::Core;
  confess "core sugar called but no Bot::Cobalt::Core instance"
    unless Bot::Cobalt::Core->is_instanced;
  Bot::Cobalt::Core->instance
}

sub register {
  core()->plugin_register( @_ )
}

sub unregister {
  core()->plugin_register( @_ )
}

sub broadcast {
  core()->send_event( @_ )
}

sub logger {
  core()->log
}

1;
