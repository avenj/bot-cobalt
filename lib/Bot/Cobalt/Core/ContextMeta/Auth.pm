package Bot::Cobalt::Core::ContextMeta::Auth;

use 5.10.1;
use strictures 1;

use Moo;
use Carp;

use Cobalt::Common qw/:types/;

around 'add' => sub {
  my $orig = shift;
  my $self = shift;
  
  ## FIXME
}

sub level {
  my ($self, $context, $nickname) = @_;
  
}

sub flags {
  my ($self, $context, $nickname) = @_;
  
}

sub username {
  my ($self, $context, $nickname) = @_;
  
}

1;
