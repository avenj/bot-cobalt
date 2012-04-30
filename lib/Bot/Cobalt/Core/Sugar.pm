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

sub broadcast {
  core()->send_event( @_ )
}

sub logger {
  core()->log
}

sub register {
  core()->plugin_register( @_ )
}

sub unregister {
  core()->plugin_register( @_ )
}

1;
__END__

=pod

=head1 NAME

Bot::Cobalt::Core::Sugar - Exported sugar for Bot::Cobalt plugins

=head1 SYNOPSIS

  use Bot::Cobalt;

  ## Call core methods . . .
  my $u_lev = core->auth->level($context, $nickname);
  my $p_cfg = core->get_plugin_cfg($self);  
  
  # Call plugin_register
  register( $self, 'SERVER', [ 'public_msg' ] );
  
  ## Call send_event
  broadcast( 'message', $context, $channel, $string );
  
  ## Call core->log
  logger->warn("A warning");

=head1 DESCRIPTION

This module provides the sugar imported when you 'use Bot::Cobalt';
these are simple functions that wrap L<Bot::Cobalt::Core> methods.

=head2 core

Returns the L<Bot::Cobalt::Core> singleton for the running instance.

=head2 broadcast

  broadcast( $event, @args );

Wraps the B<send_event> method available via L<Bot::Cobalt::Core>; 
syndicates events to the plugin pipeline.

=head2 logger

  logger->info("Log message");

Wrapper for core->log->$method

=head2 register

  register( $self, 'SERVER', [ @events ]);

Wrapper for core->plugin_register; see L<Bot::Cobalt::Manual::Plugins>

=head2 unregister

Wrapper for core->plugin_unregister

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

L<http://www.cobaltirc.org>

=cut
