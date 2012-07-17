package Bot::Cobalt::Logger::Output;

use Carp;
use Moo;

use strictures 1;

use Bot::Cobalt::Common qw/:types :string/;

use POSIX ();

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
    "%date %pkg (%level%) %msg"
  },
);


## Internals.
has '_outputs' => (
  is  => 'rwp',
  isa => ArrayRef,
  
  default => sub { [] },
);


## Public.
  ## FIXME add or remove Output:: objs from _outputs
sub add {

}

sub del {

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
    $output->_write( $fmt )
  }

  1
}

1;
__END__
