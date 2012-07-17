package Bot::Cobalt::Logger;
our $VERSION;

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use Scalar::Util qw/blessed/;

use 'Bot::Cobalt::Common' qw/:types/;

with 'Bot::Cobalt::Core::Role::Singleton';

has 'level' => (
  required => 1,
  
  isa => sub {
    die "Unknown log level $_[0]"
      unless $_[0] ~~ qw/error warn info debug/;
  },
);


has '_output' => (
  lazy => 1,

  is   => 'rwp',
  
  isa => sub {
    confess "Not a Bot::Cobalt::Logger::Output subclass"
      unless blessed $_[0] and $_[0]->isa('Bot::Cobalt::Logger::Output')
  },
  
  builder => '_build_output',
);

has '_levmap' => (
  is  => 'ro',
  isa => HashRef,
  
  default => sub {
    {
#      fatal => 0,
      error => 1,
      warn  => 2,
      info  => 3,
      debug => 4,
    }
  },
);

sub _build_output {
  my ($self) = @_;

  ## FIXME
  ##  figure out what needs passed to Logger::Output
  
  
  $output_obj
}

sub _should_log {
  my ($self, $level) = @_;

  my $num_lev = $self->_levmap->{$level}
    || confess "unknown level $level";

  my $accept = $self->_levmap->{ $self->level };

  ## Is the target level less/equal accepted level?  
  $accept >= $num_lev ? 1 : 0
}

sub _log_to_level {
  my ($self, $level) = splice @_, 0, 2;

  return unless $self->_should_log($level);

  $self->_output->write(
    $level,
    [ caller(1) ],
    @_
  );

  1
}

sub debug { shift->_log_to_level( @_ ) }
sub info  { shift->_log_to_level( @_ ) }
sub warn  { shift->_log_to_level( @_ ) }
sub error { shift->_log_to_level( @_ ) }

1;
__END__
