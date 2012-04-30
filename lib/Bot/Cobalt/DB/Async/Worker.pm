package Bot::Cobalt::DB::Async::Worker;
our $VERSION = '0.200_48';

use strictures 1;

use Storable qw/nfreeze thaw/;

use Bot::Cobalt::DB;

use bytes;

sub worker {
  binmode STDOUT;
  binmode STDIN;
  
  STDOUT->autoflush(1);
  
  my $buf = '';
  my $read_bytes;
  
  while (1) {
    if ( defined $read_bytes ) {
      if ( length $buf >= $read_bytes ) {
        my $incoming = thaw( substr($buf, 0, $read_bytes, '') );
        $read_bytes = undef;
        
        ## %opts = (
        ##   Database =>
        ##   Method =>
        ##   Key    =>
        ##   Value  =>  ## if this is a put
        ##   Event  =>
        ##   Tag    =>
        ## );
        ## ->put([ %opts ])
        
        my %args = @$incoming;
        
        for my $required (qw/Database Method Event Tag/) {
          die "Missing opt $required"
            unless $args{$required};
        }

        my $method = $args{Method};
        
        die "Missing opt Key"
          unless $method eq 'dbkeys';
        
        my $ro = 1 if $method eq 'get' or $method eq 'dbkeys';
        
        my $db = Bot::Cobalt::DB->new(
          File => $args{Database},
        );
        
        unless ( $db->dbopen(ro => $ro) ) {
          die "Failed dbopen"
        }
        
        my $retval = $db->$method($args{Key}, $args{Value});
        
        $db->dbclose;

        ## Returns:
        ##  RetVal, Event, Tag, Method, Key, Value        
        my $frozen = nfreeze( 
          [ 
            $retval, 
            $args{Event}, 
            $args{Tag}, 
            $args{Method},
            $args{Key}, 
            $args{Value}
          ] 
        );
        
        my $string = length($frozen) . chr(0) . $frozen ;
        my $wrote  = syswrite(STDOUT, $string);
        die $! unless $wrote == length $string;
        next
      }
    }
    elsif ( $buf =~ s/^(\d+)\0//) {
      $read_bytes = $1;
      next
    }
    
    my $this_read = sysread(STDIN, $buf, 4096, length($buf));
    last unless $this_read
  }
  
  exit 0
}

1;
