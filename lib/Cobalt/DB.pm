package Cobalt::DB;
our $VERSION = '0.17';

## ->new(File => $path)
##  To use a different lockfile:
## ->new(File => $path, LockFile => $lockpath)
##
## Interface to a DB_File (berkdb1.x interface)
## Very simplistic, no readonly locking etc.
## a better 'DB2' interface using BerkeleyDB.pm is planned ...

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

sub dbkeys {
  my $self = shift;
  croak "attempted 'dbkeys' on unopened db"
    unless $self->{DBOPEN};
  return wantarray ? (keys %{ $self->{Tied} })
                   : scalar keys %{ $self->{Tied} };
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

sub dbdump {
  my ($self, $format) = @_;
  croak "attempted dbdump on unopened db"
    unless $self->{DBOPEN};
  $format = 'YAML' unless $format;
  ## 'cross-serialize' to some other format and dump it
  
  my $copy = { };
  while (my ($key, $value) = each %{ $self->{Tied} }) {
    $copy->{$key} = $value;
  }
  
  my $dumper = Cobalt::Serializer->new( Format => $format );
  my $serial = $dumper->freeze($copy);
  return $serial;
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
  
  for my $key ($self->{DB}->dbkeys) {
    my $this_hash = $self->{DB}->get($key);
  }
  
  $self->{DB}->dbclose;


=head1 DESCRIPTION

B<Cobalt::DB> provides a simple object-oriented interface to basic 
L<DB_File> (Berkeley DB 1.x) usage.

BerkDB is a fast and simple key/value store. This module uses JSON to 
store nested Perl data structures, providing easy database-backed 
storage for B<Cobalt> plugins.

B<< Performance will suffer miserably if you don't have L<JSON::XS>! >>

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
for you, but it is good practice to keep track of your open/close 
calls and attempt to close as quickly as possible.


=head2 Methods

=head3 dbopen

B<dbopen> opens and locks the database (via an external lockfile, 
see the B<LockFile> constructor argument).

Try to call a B<dbclose> as quickly as possible to reduce locking 
contention.


=head3 dbclose

B<dbclose> closes and unlocks the database.


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


=head3 dbkeys 

B<dbkeys> will return a list of keys in list context, or the number 
of keys in the database in scalar context.


=head3 dbdump

You can serialize/export the entirety of the DB via B<dbdump>.

  ## YAML::Syck
  my $yamlified = $db->dbdump('YAML');
  ## YAML::XS
  my $yamlified = $db->dbdump('YAMLXS');
  ## JSON (::XS or ::PP)
  my $jsonified = $db->dbdump('JSON');

See L<Cobalt::Serializer> for more on C<freeze()> and valid formats.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

L<http://www.cobaltirc.org>

=cut