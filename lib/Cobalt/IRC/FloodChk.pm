package Cobalt::IRC::FloodChk;
our $VERSION = '2.00_45';

use Moo;
use Cobalt::Common qw/:types/;

## fqueue->{$context}->{$key} = []
has 'fqueue' => ( is => 'rw', isa => HashRef,
  default => sub { {} },
);

has 'count' => ( is => 'rw', isa => Int, required => 1 );
has 'in'    => ( is => 'rw', isa => Int, required => 1 );

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
      ($oldest_ts + ($pending * $ev_sec / $ev_c) ) - time
    );
    
    ## Too many events in this time window:
    return $delayed if $delayed > 0;
    
    ## ...otherwise shift and push:
    shift @$this_ref;
  }
  
  ## Safe to push this ev.
  push @$this_ref, time;

  return 0
}

sub clear {
  my ($self, $context, $key) = @_;
  return unless defined $context and defined $key;
  
  return unless exists $self->fqueue->{$context};
  
  return delete $self->fqueue->{$context}->{$key}
    if $key;
  return delete $self->fqueue->{$context}
}

1;
__END__

=pod

=head1 NAME

Cobalt::IRC::FloodChk - Flood check utils for Cobalt::IRC

=head1 SYNOPSIS

  my $flood = Cobalt::IRC::FloodChk->new(
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
L<Cobalt::IRC> (although it can be used anywhere you'd like to rate 
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

=head1 SEE ALSO

Conceptually borrowed from L<Algorithm::FloodControl>

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

L<http://www.cobaltirc.org>

=cut
