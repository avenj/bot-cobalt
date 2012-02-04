package Cobalt::DB;
our $VERSION = '0.05';

## ->new(File => $path)
##  To use a different lockfile:
## ->new(File => $path, LockFile => $lockpath)
## Represents a BerkDB

use 5.12.1;
use strict;
use warnings;
use Carp;

use DB_File;
use Fcntl qw/:flock/;

use Cobalt::Serializer;

use File::Spec;

sub new {
  my $self = {};
  my $class = shift;
  bless $self, $class;
  
  my %args = @_;
  unless ($args{File}) {
    croak "Constructor requires a specified File";
  }

  my $path = File::Spec->rel2abs($args{File});
  my ($vol, $dir, $dbfile) = File::Spec->splitpath($path);
  croak "no file specified" unless $dbfile;
  ## FIXME volume ... ?
  $self->{LockFile}     = $args{LockFile} ? 
                          $args{LockFile} 
                        : $dir . "/.lock.".$dbfile ;

  $self->{DatabasePath} = $path;

  $self->{Serializer} = Cobalt::Serializer->new(Format => 'JSON');
  
  $self->{Perms} = $args{Perms} ? $args{Perms} : 0644 ;

  return $self
}

sub dbopen {
  my $self = shift;

  my $path = $self->{DatabasePath};

  if (-f $self->{LockFile}) {
    ## lockfile exists, is a regular file
    ## it should've been ours (stale perhaps) with a pid
    open my $lockf_fh, '<', $self->{LockFile}
      or croak "could not open lockfile $self->{LockFile}: $!";
    my $pid = <$lockf_fh>;
    close $lockf_fh;
    unless (kill 0, $pid) {   ## stale ?
      warn "warning; clearing stale lockfile for $pid\n";
      unlink($self->{LockFile});
    }
  }

  open my $lockf_fh, '>', $self->{LockFile}
    or croak "could not open lockfile $self->{LockFile}: $!";
  flock($lockf_fh, LOCK_EX) or croak "lock failed: $lockf_fh: $!";
  print $lockf_fh $$;
  $self->{LockFH} = $lockf_fh;

  $self->{DB} = tie %{ $self->{Tied} }, "DB_File", $path,
      O_CREAT|O_RDWR, $self->{Perms}, $DB_HASH
      or croak "failed db open: $path: $!"
  ;

  ## null-terminated to be C-compat
  $self->{DB}->filter_fetch_key(
    sub { s/\0$// }
  );
  $self->{DB}->filter_store_key(
    sub { $_ .= "\0" }
  );

  ## Storable is probably faster
  ## ... but has no backwards compat guarantee
  $self->{DB}->filter_fetch_value(
    sub {
      s/\0$//;
      $_ = $self->{Serializer}->thaw($_);
    }
  );
  $self->{DB}->filter_store_value(
    sub {
      $_ = $self->{Serializer}->freeze($_);
      $_ .= "\0";
    }
  );
  return 1
}

sub get_db {
  my $self = shift;
  return $self->{DB}
}

sub dbclose {
  my $self = shift;
  $self->{DB} = undef;
  untie %{ $self->{Tied} };
  my $lockfh = $self->{LockFH};
  flock($lockfh, LOCK_UN) or carp "unlock failed: $!";
  close $lockfh;
  delete $self->{LockFH};
  unlink $self->{LockFile};
}

sub keys {
  my $self = shift;
  return keys %{ $self->{Tied} }
}

sub get {
  my ($self, $key) = @_;
  my $value = $self->{Tied}{$key} // undef;
  return $value
}

sub add { put(@_) }
sub put {
  my ($self, $key, $value) = @_;
  $self->{Tied}{$key} = $value;
  return $value
}

sub del {
  my ($self, $key) = @_;
  return undef unless exists $self->{Tied}{$key};
  delete $self->{Tied}{$key};
  return 1
}

1;
__END__

=pod

=cut
