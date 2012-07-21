package Bot::Cobalt::Frontend::RC;
our $VERSION = '0.014';

use strictures 1;

use Carp;
use Try::Tiny;

use File::Spec;
use Cwd ();

use Bot::Cobalt::Serializer;

use base 'Exporter';

our @EXPORT_OK = qw/
  rc_read
  rc_write
/;

sub rc_read {
  my ($rcfile) = @_;
  croak "rc_read needs a rcfile path" unless $rcfile;

  my $generic_crappy_err = sub {
    warn(
      "Errors reported during rcfile parse\n",
      "You may have an old, incompatible, or broken rcfile.\n",
      "Path: $rcfile\n",
      "Try running cobalt2-installer\n"
    );
  };

  my $rc_h;
  try {
    $rc_h = Bot::Cobalt::Serializer->new->readfile($rcfile);
  } catch {
    $generic_crappy_err->();
    croak "Could not rc_read(); readfile said $_"
  };
  
  unless ($rc_h && ref $rc_h eq 'HASH') {
    $generic_crappy_err->();
    croak "rc_read ($rcfile) expected to receive a hash"
  }

  my ($BASE, $ETC, $VAR) = @$rc_h{'BASE', 'ETC', 'VAR'};
  
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

  unless ( File::Spec->file_name_is_absolute($basepath) ) {
    my $homedir = $ENV{HOME} || Cwd::cwd();
    $basepath = File::Spec->catdir( $homedir, $basepath );
  }

  my $rc_h = {
    BASE => $basepath,
    ETC  => File::Spec->catdir( $basepath, 'etc' ),
    VAR  => File::Spec->catdir( $basepath, 'var' ),
  };

  ## Return $basepath on success, otherwise croak out.
  try {
    Bot::Cobalt::Serializer->new->writefile(
      $rcfile, $rc_h
    );
    $basepath
  } catch {
    croak "rc_write() failure in call to Serializer; $rcfile $_"
  }
}

1;
__END__

=pod

=head1 NAME

Bot::Cobalt::Frontend::RC - Read and write instance RC files

=head1 SYNOPSIS

  use Bot::Cobalt::Frontend::RC qw/ rc_read rc_write /;
  
  my ($base, $etc, $var) = rc_read($rcfile_path);
  
  rc_write($rcfile_path, $base_path);

=head1 DESCRIPTION

L<Bot::Cobalt> RC files are small per-instance YAML configuration files 
used by the default frontends to determine the location of configuration 
('etc') and dynamic data ('var') directories.

An example RC file might look like:

  ---
  BASE: /home/cobalt/cobalt2
  ETC: /home/cobalt/cobalt2/etc
  VAR: /home/cobalt/cobalt2/var

=head2 rc_read

rc_read() takes the path to a preexisting RC file and returns a list of 
three elements; the base directory path, 'etc' path, and 'var' path, 
respectively.

=head2 rc_write

rc_write() takes the path to the destination RC file and a base 
directory path from which 'etc' and 'var' directories are constructed.

Returns the actual (parsed) base path on success, croaks on failure.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
