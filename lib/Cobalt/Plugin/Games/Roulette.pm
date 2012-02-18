package Cobalt::Plugin::Games::Roulette;
our $VERSION = '0.003';

use 5.12.1;
use strict;
use warnings;

use Cobalt::Utils qw/color/;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;
  my %args = @_;
  $self->{core} = $args{core} if ref $args{core};
  return $self
}

sub execute {
  my ($self, $msg) = @_;
  my $cyls = 5;

  my $context = $msg->{context};
  my $nick = $msg->{src_nick};

  my $loaded = $self->{Cylinder}->{$context}->{$nick}->{Loaded}
               //= int rand($cyls);

  if ($loaded == 0) {
    delete $self->{Cylinder}->{$context}->{$nick};
    return color('bold', 'BANG!')
  }
  --$self->{Cylinder}->{$context}->{$nick}->{Loaded};
  return 'Click . . .'
}

1;
__END__
