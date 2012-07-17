package Bot::Cobalt::Logger;
our $VERSION;

use 5.12.1;
use strictures 1;

use Carp;
use Moo;

use Scalar::Util qw/blessed/;

use Bot::Cobalt::Common qw/:types/;

use Bot::Cobalt::Logger::Output;

has 'level' => (
  required => 1,

  is => 'ro',
  writer => 'set_level',
  
  isa => sub {
    confess "Unknown log level, should be one of: error warn info debug"
      unless $_[0] ~~ [qw/error warn info debug/];
  },
);

## time_format / log_format are passed to ::Output
has 'time_format' => (
  lazy => 1,

  is  => 'rw',
  isa => Str,

  predicate => 'has_time_format',  
  
  trigger => sub {
    my ($self, $val) = @_;
    
    $self->output->time_format($val)
      if $self->has_output;
  },
);

has 'log_format' => (
  lazy => 1,
  
  is  => 'rw',
  isa => Str,
  
  predicate => 'has_log_format',
  
  trigger => sub {
    my ($self, $val) = @_;
    
    $self->output->log_format($val)
      if $self->has_output;
  },
);


has 'output' => (
  lazy => 1,

  is   => 'rwp',
  predicate => 'has_output',
  
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
      error => 1,
      warn  => 2,
      info  => 3,
      debug => 4,
    }
  },
);

sub _build_output {
  my ($self) = @_;

  my %opts;
  
  $opts{log_format} = $self->log_format
    if $self->has_log_format;

  $opts{time_format} = $self->time_format
    if $self->has_time_format;

  Bot::Cobalt::Logger::Output->new(
    %opts  
  );
}

sub _should_log {
  my ($self, $level) = @_;

  my $num_lev = $self->_levmap->{$level}
    || confess "unknown level $level";

  my $accept = $self->_levmap->{ $self->level };

  $accept >= $num_lev ? 1 : 0
}

sub _log_to_level {
  my ($self, $level) = splice @_, 0, 2;

  return 1 unless $self->_should_log($level);

  $self->output->_write(
    $level,
    [ caller(1) ],
    @_
  );

  1
}

sub debug { shift->_log_to_level( 'debug', @_ ) }
sub info  { shift->_log_to_level( 'info', @_ )  }
sub warn  { shift->_log_to_level( 'warn', @_ )  }
sub error { shift->_log_to_level( 'error', @_ ) }

1;
__END__
