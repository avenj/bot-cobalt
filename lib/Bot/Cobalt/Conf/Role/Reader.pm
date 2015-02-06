package Bot::Cobalt::Conf::Role::Reader;

use Carp;
use strictures 1;

use Try::Tiny;

use Scalar::Util qw/blessed/;

use Bot::Cobalt::Serializer;

use Moo::Role;

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

  my $err;
  my $thawed_cf = try {
    $self->_serializer->readfile( $path )
  } catch {
    $err = $_;
    ()
  };
  confess "Serializer readfile() failed for $path; $err"
    if defined $err;

  $thawed_cf
}


1;
__END__
