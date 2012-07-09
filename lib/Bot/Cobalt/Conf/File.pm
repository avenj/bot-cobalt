package Bot::Cobalt::Conf::File;

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use Bot::Cobalt::Common qw/:types/;

use Bot::Cobalt::Serializer;

use Try::Tiny;

has 'path' => (
  required => 1,

  is  => 'rwp',
  isa => Str,
);

has 'cfg_as_hash' => (
  lazy => 1,
  
  is  => 'rwp',
  isa => HashRef, 
  
  builder => '_build_cfg_hash',
);


with 'Bot::Cobalt::Conf::Role::Reader';


sub _build_cfg_hash {
  my ($self) = @_;
  
  my $cfg = $self->readfile( $self->path );

  try {
    $self->validate($cfg)
  } catch {
    croak "Conf validation failed for ". $self->path .": $_"
  };
  
  $cfg
}

sub validate {
  my ($self, $cfg) = @_;
  
  1
}

1;
__END__
