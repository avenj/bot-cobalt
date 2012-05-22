package Bot::Cobalt::Frontend::RC;
our $VERSION = '0.002';

use strictures 1;
use Carp;

use base 'Exporter';

our @EXPORT_OK = qw/
  rc_read
  rc_write
/;

sub rc_read {
  my ($rcfile) = @_;
  croak "rc_read needs a rcfile path" unless $rcfile;

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
  my ($rcfile, $basepath) = @_;
  croak "rc_write needs rc file path and base directory path"
    unless $rcfile and $basepath;
  
  my $str = join "\n",
    '## cobalt2rc automatically generated at '.scalar localtime,
    '$BASE = $ENV{HOME} . "/'.$basepath.'";' ,
    '$ETC  = $BASE ."/etc";' ,
    '$VAR  = $BASE ."/var";' , 
    '' ;

  open my $fh, '>', $rcfile
    or croak "Unable to open rcfile: $rcfile: $!";
  print $fh $str;
  close $fh;

  return $basepath
}

1;
