package Cobalt::DB;
our $VERSION = '0.14';

## ->new(File => $path)
##  To use a different lockfile:
## ->new(File => $path, LockFile => $lockpath)
## Represents a BerkDB

use 5.12.1;
use strict;
use warnings;
use Carp;

use DB_File;
use Fcntl qw/:DEFAULT :flock/;

use Cobalt::Serializer;

sub new {
  my $self = {};
  my $class = shift;
  bless $self, $class;
  
  my %args = @_;
  unless ($args{File}) {
    croak "Constructor requires a specified File";
  }

  my $path = $args{File};

  $self->{DatabasePath} = $path;
 
  $self->{LockFile} = $args{LockFile} // $path . ".lock";

  $self->{Serializer} = Cobalt::Serializer->new(Format => 'JSON');
  
  $self->{Perms} = $args{Perms} ? $args{Perms} : 0644 ;

  return $self
}

sub dbopen {
  my $self = shift;
  my $path = $self->{DatabasePath};

  open my $lockf_fh, '>', $self->{LockFile}
    or warn "could not open lockfile $self->{LockFile}: $!\n"
    and return;

  my $timer;
  until ( flock $lockf_fh, LOCK_EX | LOCK_NB ) {
    if ($timer > 10) {   ## 10s lock timeout
      warn "failed lock for db $path, timeout (10s)\n";
      return
    }
    select undef, undef, undef, 0.25;
    $timer += 0.25;
  }
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
  $self->{DBOPEN} = 1;
  return 1
}

sub get_tied {
  my $self = shift;
  croak "attempted to get_tied on unopened db"
    unless $self->{DBOPEN};
  return $self->{Tied}
}

sub get_db {
  my $self = shift;
  croak "attempted to get_db on unopened db"
    unless $self->{DBOPEN};
  return $self->{DB}
}

sub dbclose {
  my $self = shift;
  unless ($self->{DBOPEN}) {
    carp "attempted dbclose on unopened db";
    return
  }
  $self->{DB} = undef;
  untie %{ $self->{Tied} };
  my $lockfh = $self->{LockFH};
  close $lockfh;
  delete $self->{LockFH};
  unlink $self->{LockFile};
  $self->{DBOPEN} = 0;
  return 1
}

sub DESTROY {
  my $self = shift;
  $self->dbclose if $self->{DBOPEN};
}

sub get_path {
  return shift->{DatabasePath};
}

sub keys {
  my $self = shift;
  croak "attempted 'keys' on unopened db"
    unless $self->{DBOPEN};
  return keys %{ $self->{Tied} }
}

sub get {
  my ($self, $key) = @_;
  croak "attempted 'get' on unopened db"
    unless $self->{DBOPEN};
  my $value = $self->{Tied}{$key} // undef;
  return $value
}

sub add { put(@_) }
sub put {
  my ($self, $key, $value) = @_;
  croak "attempted 'put' on unopened db"
    unless $self->{DBOPEN};
  $self->{Tied}{$key} = $value;
  return $value
}

sub del {
  my ($self, $key) = @_;
  croak "attempted 'del' on unopened db"
    unless $self->{DBOPEN};
  return undef unless exists $self->{Tied}{$key};
  delete $self->{Tied}{$key};
  return 1
}

1;
__END__

=pod

=head1 NAME

Cobalt::DB - Locking Berkeley DBs with serialization

=head1 SYNOPSIS

  use Cobalt::DB;
  
  ## ... perhaps in a Cobalt_register ...
  my $db_path = $core->var ."/MyDatabase.db";
  $self->{DB} = Cobalt::DB->new(
    File => $db_path,
  );
  
  ## do some work:
  $self->{DB}->dbopen;
  
  $self->{DB}->put("SomeKey",
    { Some => {
        Deep => { Structure => 1, },
    }, },
  );
  
  for my $key ($self->{DB}->keys) {
    my $this_hash = $self->{DB}->get($key);
  }
  
  $self->{DB}->dbclose;


=head1 DESCRIPTION

B<Cobalt::DB> provides a simple object-oriented interface to basic 
L<DB_File> (Berkeley DB 1.x) usage.

BerkDB is a fairly simple key/value store. This module uses JSON to 
store nested Perl data structures, providing easy database-backed 
storage for B<Cobalt> plugins.

=head2 Constructor

B<new()> is used to create a new Cobalt::DB object representing your 
Berkeley DB:

  my $db = Cobalt::DB->new(
    File => $path_to_db,

   ## Optional arguments:
    Perms => $octal_mode,
    # Locking is enabled regardless
    # but you can change the location:
    LockFile => "/tmp/sharedlock",
  );

=head2 Opening and closing

Database operations should be contained within a dbopen/dbclose:

  ## open, put, close:
  $db->dbopen || croak "dbopen failure";
  $db->put($key, $data);
  $db->dbclose;
  
  ## open, read, close:
  $db->dbopen || croak "dbopen failure";
  my $data = $db->get($key);
  $db->dbclose;

Methods will fail if the DB is not open.

If the DB for this object is open when the object is DESTROY'd, Cobalt::DB 
will attempt to close it safely.

=head2 Locking

By default, a lock file will be created in the same directory as 
the database file itself.

The attempt to gain a lock will time out after ten seconds; this is 
one reason it is important to check dbopen exit status.

B<The lock file is cleared on dbclose. Be sure to always dbclose!>

If the Cobalt::DB object is destroyed, it will attempt to dbclose 
for you.

=head2 Methods

=head3 put

The B<put> method adds an entry to the database:

  $db->put($key, $value);

The value can be any data structure serializable by JSON::XS; that is to 
say, any shallow or deep data structure NOT including blessed references.

(Yes, Storable is probably faster. JSON is used because it is trivially 
portable to any language that can interface with BerkDB.)

=head3 get

The B<get> method retrieves a (deserialized) key.

  $db->put($key, { Some => 'hash' } );
  ## . . . later on . . .
  my $ref = $db->get($key);


=head3 del

The B<del> method removes a key from the database.

  $db->del($key);


=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

L<http://www.cobaltirc.org>

=cut
