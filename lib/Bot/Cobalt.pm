package Bot::Cobalt;
our $VERSION = '0.200_46';

use 5.10.1;
use strictures 1;
use Carp;
use Moo;

require Bot::Cobalt::Core;

sub instance {
  if (@_) {
    ## Someone tried to create a new instance, but they really 
    ## wanted a Bot::Cobalt::Core.
    ##
    ## Rather than create and return something that doesn't belong to 
    ## this package/class, die out.
    ##
    ## Behavior may change.
    $_[0]->new(@_[1 .. $#_])
  }

  ## Be polite and offer up our Bot::Cobalt::Core if we have one
  ## (and if this doesn't appear to be a construction attempt)
  unless (Bot::Cobalt::Core->has_instance) {
    carp "Tried to retrieve instance but no active Bot::Cobalt::Core found";
    return
  }

  return Bot::Cobalt::Core->instance 
}

sub new {
  croak "Bot::Cobalt is a stub; it cannot be constructed.\n"
    . "See the perldoc for Bot::Cobalt::Core\n";
}

1;
__END__

=pod

=head1 NAME

Bot::Cobalt - IRC darkbot-alike plus plugin authoring sugar

=head1 SYNOPSIS

FIXME quickstart instructions

=head1 DESCRIPTION

B<Bot::Cobalt> is the 2nd generation of the (not released on CPAN) 
B<cobalt> IRC bot.

Cobalt was originally a Perl reimplementation of Jason Hamilton's 
B<darkbot> behavior.

Bot::Cobalt is a much-improved (and CPAN-able!) revision, providing a 
pluggable IRC bot framework coupled with a core set of plugins 
replicating classic darkbot and Cobalt behavior.

The included plugin set provides a wide range of behavior.
FIXME link a doc covering core plugin summary?

IRC functionality is provided via L<POE::Component::IRC>.
The bridge to L<POE::Component::IRC> is also a plugin and can be 
easily subclassed or replaced entirely; see L<Bot::Cobalt::IRC>.

Plugin authoring is intended to be as easy as possible. Modules are 
included to provide simple frontends to IRC-related 
utilities, logging, plugin configuration, asynchronous HTTP 
sessions, data serialization and on-disk databases, and more. See 
L<Bot::Cobalt::Manual::Plugins> for more about plugin authoring.

=head1 SEE ALSO

L<Bot::Cobalt::Manual::Plugins>

L<Bot::Cobalt::Core>

L<Bot::Cobalt::IRC>

The core pieces of Bot::Cobalt are essentially sugar over these two 
L<POE> Components:

L<POE::Component::IRC>

L<POE::Component::Syndicator>

Consult their documentation for all the gory details.

Logging facilities are provided by L<Log::Handler>.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

L<http://www.cobaltirc.org>

=cut
