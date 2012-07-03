package Bot::Cobalt::Plugin::RDB::Error;

use 5.12.1;
use strictures 1;

use overload
  '""'     => sub { shift->error },
  fallback => 1;

sub new {
  my $class = shift;
  
  bless [ $_[0] ], $class
}

sub error {
  my ($self, $error) = @_;
  
  defined $error ? $self->new($error) : $self->[0]
}

1
