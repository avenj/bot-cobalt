package Bot::Cobalt::Logger::Output;

use Carp;
use Moo;

use strictures 1;

use Bot::Cobalt::Common qw/:types :string/;

use POSIX ();

use Try::Tiny;

## Configurables.
has 'time_format' => (
  is  => 'rw',
  isa => Str,
  
  default => sub {
    ## strftime
    "%Y-%m-%d %H:%M:%S"
  },
);

has 'log_format' => (
  is  => 'rw',
  isa => Str,
  
  default => sub {
    ## rplprintf
    "%time %pkg (%level%) %msg"
  },
);


## Internals.
has '_outputs' => (
  is  => 'rwp',
  isa => ArrayRef,
  
  default => sub { [] },
);


## Public.
sub add {
  my ($self, @args) = @_;
  
  unless (@args && @args % 2 == 0) {
    confess "add() expects an even number of arguments, ",
         "mapping an Output class to constructor arguments"
  }
  
  my $prefix = 'Bot::Cobalt::Logger::' ;
  
  CONFIG: while (my ($subclass, $opts) = splice @args, 0, 2) {
    confess "add() expects constructor arguments to be a HASH"
      unless ref $opts eq 'HASH';

    my $target_pkg = $prefix . $subclass;

    { local $@;
      eval "require $target_pkg";
      
      if (my $err = $@) {
        carp "Could not add $subclass: $err";
        next CONFIG
      }
    }

    my $new_obj = try {
      $target_pkg->new(%$opts)
    } catch {
      carp "Could not add $subclass, new() died: $_";
      undef
    } or next CONFIG;

    push( @{ $self->_outputs }, $new_obj )
  }  ## CONFIG

  1
}


## Private.
sub _format {
  my ($self, $level, $caller, @strings) = @_;
  
  rplprintf( $self->log_format,
    level => $level,

    ## Actual message.
    msg  => join(' ', @strings),  

    time => POSIX::strftime( $self->time_format, localtime ),

    ## Caller details, split out.
    pkg  => $caller->[0],
    file => $caller->[1],
    line => $caller->[2],
    sub  => $caller->[3],
  )
   . "\n"
}

sub _write {
  my $self = shift;

  my $fmt = $self->_format( @_ );

  for my $output (@{ $self->_outputs }) {
    $output->_write(
      ## Output classes can provide their own _format
      $output->can('_format') ?  $output->_format( @_ )
        : $self->_format( @_ )
    )
  }

  1
}

1;
__END__
