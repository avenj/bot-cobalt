package Bot::Cobalt::Error;

use 5.12.1;
use strictures 1;

use overload
  '""'     => sub { shift->string },
  fallback => 1;

sub new {
  my $class = shift;
  bless [ @_ ], ref $class || $class
}

sub string {
  my ($self) = @_;
  join '', map { "$_" } @$self
}

sub join {
  my ($self, $delim) = @_;
  $delim //= ' ';
  return $self->new( CORE::join($delim, map { "$_" } @$self) )
}


1
