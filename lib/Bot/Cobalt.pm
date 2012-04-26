package Bot::Cobalt;
our $VERSION = '0.200_46';

use 5.10.1;
use strictures 1;
use Carp;
use Moo;

require Cobalt::Core;

sub instance {
  if (@_) {
    ## Someone tried to create a new instance, but they really 
    ## wanted a Cobalt::Core.
    ##
    ## Rather than create and return something that doesn't belong to 
    ## this package/class, die out.
    ##
    ## Behavior may change.
    $_[0]->new(@_[1 .. $#_])
  }

  ## Be polite and offer up our Cobalt::Core if we have one
  ## (and if this doesn't appear to be a construction attempt)
  unless (Cobalt::Core->has_instance) {
    carp "Tried to retrieve instance but no active Cobalt::Core found";
    return
  }

  return Cobalt::Core->instance 
}

sub new {
  croak "Bot::Cobalt is a stub; it cannot be constructed.\n"
    . "See the perldoc for Cobalt::Core\n";
}

1;
__END__

=pod

FIXME

=cut
