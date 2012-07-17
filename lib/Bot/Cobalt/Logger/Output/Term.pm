package Bot::Cobalt::Logger::Output::Term;

use strictures 1;
use Carp;

sub new {
  my $class = shift;
  my $self = [];
  bless $self, $class;
  
  $self
}

sub _write {
  my ($self, $str) = @_;
  
  local $|=1;
  
  binmode STDOUT, ":utf8";
  
  print STDOUT $str
}

1;
__END__
