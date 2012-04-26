package Bot::Cobalt::Frontend::RC;
our $VERSION = 0;

use strictures 1;
use Carp;

use base 'Exporter';

my @EXPORT = qw/
  rc_read
/;

sub rc_read {
  my ($rcfile) = @_;

  open my $fh, '<', $rcfile
    or croak "Unable to read rcfile: $rcfile: $!";

  my $rcstr;
  { local $/; $rcstr = <$fh>; }

  close $fh;
  
  my ($BASE, $ETC, $VAR);
  eval $rcstr;
  if ($@) {
    croak "Errors reported during rcfile parse: $@"
  }
  
  unless ($BASE && $ETC && $VAR) {
    warn "rc_read; could not find BASE, ETC, VAR\n";
    warn "BASE: $BASE\nETC: $ETC\nVAR: $VAR\n";
    
    croak "Cannot continue without a valid rcfile"
  }
    
  return ($BASE, $ETC, $VAR)
}

sub rc_write {
  
}

1;
