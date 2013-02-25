package Bot::Cobalt::IRC::FloodChk;
our $VERSION = '0.016000';

use Carp;
use Moo;

use Bot::Cobalt::Common qw/:types/;

use strictures;

use Time::HiRes;

## fqueue->{$context}->{$key} = []
has 'fqueue' => ( is => 'rw', isa => HashRef,
  default => sub { {} },
);

has 'count' => ( is => 'rw', isa => Num, required => 1 );
has 'in'    => ( is => 'rw', isa => Num, required => 1 );

sub check {
  my ($self, $context, $key) = @_;
  return unless defined $context and defined $key; 
  
  my $this_ref = ($self->fqueue->{$context}->{$key}//=[]);
  
  if (@$this_ref >= $self->count) {
    my $oldest_ts = $this_ref->[0];
    my $pending   = @$this_ref;
    my $ev_c      = $self->count;
    my $ev_sec    = $self->in;

    my $delayed = int(
      ($oldest_ts + ($pending * $ev_sec / $ev_c) ) - Time::HiRes::time()
    );
    
    ## Too many events in this time window:
    return $delayed if $delayed > 0;
    
    ## ...otherwise shift and push:
    shift @$this_ref;
  }
  
  ## Safe to push this ev.
  push @$this_ref, Time::HiRes::time();

  return 0
}

sub clear {
  my ($self, $context, $key) = @_;
  confess "clear() needs a context specified" 
    unless defined $context;
  
  return unless exists $self->fqueue->{$context};
  
  return delete $self->fqueue->{$context}->{$key}
    if defined $key;
  
  delete $self->fqueue->{$context}
}

sub expire {
  ## Clear keys when recent_event_time - time > $self->in
  my ($self) = @_;
  CONTEXT: for my $context (keys %{ $self->fqueue } ) {
    KEY: for my $key (keys %{ $self->fqueue->{$context} } ) {
      my @events = @{ $self->fqueue->{$context}->{$key} };
      my $latest_time = $events[-1] // next KEY;
      
      if (Time::HiRes::time() - $latest_time > $self->in) {
        ## It's been more than ->in seconds since latest event was
        ## noted. We can clear() this entry.
        $self->clear($context, $key);
      }
    } ## KEY
    
    unless (keys %{ $self->fqueue->{$context} }) {
      ## Nothing left for this context.
      $self->clear($context);
    }
  }
}

1;
__END__

=pod

=head1 NAME

Bot::Cobalt::IRC::FloodChk - Flood check utils for Bot::Cobalt

=head1 SYNOPSIS

  my $flood = Bot::Cobalt::IRC::FloodChk->new(
    count => 5,
    in    => 4,
  );
  
  ## Incoming IRC message, f.ex
  ## Throttle user to 5 messages in 4 seconds
  if ( $flood->check( $context, $nick ) ) {
    ## Flood detected
  } else {
    ## No flood, continue
  }

=head1 DESCRIPTION

This is a fairly generic flood control manager intended for 
L<Bot::Cobalt::IRC> (although it can be used anywhere you'd like to rate 
limit messages).

=head2 new

The object's constructor takes two mandatory parameters, B<count> and 
B<in>, indicating that B<count> messages (or events, or whatever) are 
allowed in a window of B<in> seconds.

=head2 check

  $flood->check( $context, $key );

If there appears to be a flood in progress, returns the number of 
seconds until it would be permissible to process more events.

Returns boolean false if there is no flood detected.

=head2 clear

Clear the tracked state for a specified context and key; if the key is 
omitted, the entire context is cleared.

=head2 expire

Check all contexts and keys in the object for stale entries that can be 
safely removed; in other words, entries whose latest recorded event was 
more than the specified B<in> seconds ago.

=head1 SEE ALSO

Algorithm is borrowed from an excellent article regarding 
L<Algorithm::FloodControl>; for a more generic rate limiting solution, 
try there.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

L<http://www.cobaltirc.org>

=cut
