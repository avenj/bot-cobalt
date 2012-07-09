package Bot::Cobalt::Conf::File::Core;

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use Bot::Cobalt::Common qw/:types/;

extends 'Bot::Cobalt::Conf::File';

has 'language' => (
  lazy => 1,
  
  is  => 'rwp',
  isa => Str,
  
  default => sub {
    my ($self) = @_;
    $self->cfg_as_hash->{Language} // 'english' ;
  },
);

has 'paths' => (
  lazy => 1,
  
  is  => 'rwp',
  isa => HashRef,
  
  default => sub {
    my ($self) = @_;
    ref $self->cfg_as_hash->{Paths} eq 'HASH' ?
      $self->cfg_as_hash->{Paths}
      : {}
  },
);

has 'irc' => (
  lazy => 1,
  
  is  => 'rwp',
  isa => HashRef,
  
  default => sub {
    my ($self) = @_;
    $self->cfg_as_hash->{IRC}
  },
);

has 'opts' => (
  lazy => 1,
  
  is  => 'rwp',
  isa => HashRef,
  
  default => sub {
    my ($self) = @_;
    $self->cfg_as_hash->{Opts}
  },
);

around 'validate' => sub {
  my ($orig, $self, $cfg) = @_;

  ## FIXME
  
  1
};


1;
__END__
