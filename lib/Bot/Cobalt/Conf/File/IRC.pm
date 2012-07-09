package Bot::Cobalt::Conf::File::IRC;

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use Bot::Cobalt::Common qw/:types/;

use Scalar::Util qw/blessed/;


extends 'Bot::Cobalt::Conf::File';


has 'core_config' => (
  required => 1,
  
  is  => 'rwp',
  isa => sub {
    die "core_config attrib needs a Bot::Cobalt::Conf::File::Core obj"
      unless blessed $_[0] and $_[0]->isa('Bot::Cobalt::Conf::File::Core')
  },
  
  trigger => sub {
    my ($self, $corecf) = @_;
    ## Set up 'Main' context from cobalt.conf.
    ## Kludgy leftovers, but a pain in the ass to fix now ...
    $self->cfg_as_hash->{Main} = $corecf->irc;
  },
);


around 'validate' => sub {
  my ($orig, $self, $cfg) = @_;

  ## FIXME

  1
};

sub list_contexts {
  my ($self) = @_;
  
  [ keys %{ $self->cfg_as_hash } ]
}

sub context {
  my ($self, $context) = @_;
  
  confess "context() needs a context name"
    unless defined $context;

  $self->cfg_as_hash->{$context}
}

1;
__END__
