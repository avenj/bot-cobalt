package Bot::Cobalt::Conf::File::Channels;

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use Bot::Cobalt::Common qw/:types/;

extends 'Bot::Cobalt::Conf::File';


sub context {
  my ($self, $context) = @_;
  
  croak "context() requires a server context identifier"
    unless defined $context;

  $self->cfg_as_hash->{$context}
}


around 'validate' => sub {
  my ($orig, $self, $cfg) = @_;

  ## FIXME

  1
};


1;
__END__
