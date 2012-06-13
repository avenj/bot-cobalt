package Bot::Cobalt::Plugin::RDB::AsyncSearch::Worker;
our $VERSION = '0.008';

use strict;
use warnings;

use Storable qw/nfreeze thaw/;

use bytes;

use Bot::Cobalt::DB;

sub worker {
  binmode STDOUT;
  binmode STDIN;
  
  select(STDOUT);
  $|++;
  
  my $buf = '';
  my $read_bytes;
  
  while (1) {
    if (defined $read_bytes) {
      if (length $buf >= $read_bytes) {
        my $input = thaw( substr($buf, 0, $read_bytes, '') );
        $read_bytes = undef;
        
        ## Get:
        ##  - DB path
        ##  - Unique ID
        ##  - Regex (compiled)
        my ($dbpath, $tag, $regex) = @$input;
        
        my $db = Bot::Cobalt::DB->new($dbpath);

        for (qw/INT TERM QUIT HUP/) {
          $SIG{$_} = sub {
            $db->dbclose if $db->is_open;
            die "Terminal signal, closed cleanly"
          };
        }

        unless ( $db->dbopen(ro => 1, timeout => 30) ) {
          die "Failed database open"
        }
                
        my @matches;
        
        $regex = qr/$regex/i;

        my $i;
        KEY: while (my ($dbkey, $ref) = each %{ $db->Tied }) {
          next KEY unless $ref;
          
          my $str = ref $ref eq 'HASH' ? $ref->{String} : $ref->[0] ;
          
          if ($str =~ $regex) {
            push(@matches, $dbkey);
          }
        }
        
        $db->dbclose;

        ## Return:
        ##  - DB path
        ##  - Unique ID
        ##  - Array of matching item IDs
        my $frozen = nfreeze( [ $dbpath, $tag, @matches ] );
        
        my $stream  = length($frozen) . chr(0) . $frozen ;
        my $written = syswrite(STDOUT, $stream);
        die $! unless $written == length $stream;
        exit 0
      }
    } elsif ($buf =~ s/^(\d+)\0//) {
      $read_bytes = $1;
      next
    }
    
    my $readb = sysread(STDIN, $buf, 4096, length $buf);
    last unless $readb;
  }
  
  exit 0
}

1;
