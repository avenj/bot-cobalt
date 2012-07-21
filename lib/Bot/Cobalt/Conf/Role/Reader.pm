package Bot::Cobalt::Conf::Role::Reader;
our $VERSION = '0.014';

use Moo::Role;
use Carp;

use strictures 1;

use Try::Tiny;

use Scalar::Util qw/blessed/;

use Bot::Cobalt::Serializer;

has '_serializer' => (
  is  => 'ro',
  isa => sub {
    blessed $_[0] and $_[0]->isa('Bot::Cobalt::Serializer')
      or confess "_serializer needs a Bot::Cobalt::Serializer"
  },
  
  default => sub {
    Bot::Cobalt::Serializer->new
  },
);

sub readfile {
  my ($self, $path) = @_;

  confess "readfile() needs a path to read"
    unless defined $path;

  my $thawed_cf;

  try {
    $thawed_cf = $self->_serializer->readfile( $path );
  } catch {
    croak "Serializer readfile() failed for $path; $_"
  };

  $thawed_cf
}


1;
__END__
