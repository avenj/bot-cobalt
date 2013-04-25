package Bot::Cobalt::DB;
our $VERSION = '0.016002';

## Simple interface to a DB_File
## Uses proper retie-after-lock technique for locking

use 5.12.1;
use strictures 1;
use Carp;

use Moo;

use DB_File;
use Fcntl qw/:DEFAULT :flock/;

use IO::File;

use Bot::Cobalt::Serializer;
use Bot::Cobalt::Common qw/:types/;

use Time::HiRes qw/sleep/;


use namespace::clean -except => 'meta';


has 'File'  => (
  is  => 'rw',
  isa => Str,

  required => 1
);

has 'Perms' => (
  is => 'rw',

  default => sub { 0644 },
);

has 'Raw'     => (
  is  => 'rw',
  isa => Bool,

  default => sub { 0 },
);

has 'Timeout' => (
  is  => 'rw',
  isa => Num,

  default => sub { 5 },
);

has 'Serializer' => (
  lazy => 1,
  is   => 'rw',
  isa  => Object,

  default => sub {
    Bot::Cobalt::Serializer->new(Format => 'JSON')
  },
);

## _orig is the original tie().
has '_orig' => (
  is  => 'rw',
  isa => HashRef,

  default => sub { {} },
);

## Tied is the re-tied DB hash.
has 'Tied'  => (
  is  => 'rw',
  isa => HashRef,

  default   => sub { {} },
);

has '_lockFH' => (
  lazy => 1,
  is   => 'rw',
  isa  => FileHandle,

  predicate => 'has_LockFH',
  clearer   => 'clear_LockFH',
);

## LOCK_EX or LOCK_SH for current open
has '_lockmode' => (
  lazy => 1,
  is  => 'rw',

  predicate => 'has_LockMode',
  clearer   => 'clear_LockMode',
);

## DB object.
has 'DB'     => (
  lazy => 1,
  is   => 'rw',
  isa  => Object,

  predicate => 'has_DB',
  clearer   => 'clear_DB',
);

has 'is_open' => (
  is => 'rw',
  isa => Bool,

  default => sub { 0 },
);

sub BUILDARGS {
  my ($class, @args) = @_;

  @args == 1 ?
    { File => $args[0] }
    : { @args }
}

sub DESTROY {
  my ($self) = @_;
  $self->dbclose if $self->is_open;
}

sub dbopen {
  my ($self, %args) = @_;
  $args{lc $_} = delete $args{$_} for keys %args;

  ## per-open timeout was specified:
  $self->Timeout( $args{timeout} )
    if $args{timeout};

  if ( $self->is_open ) {
    carp "Attempted dbopen() on already-open DB";
    return
  }

  my ($lflags, $fflags);
  if ($args{ro} || $args{readonly}) {
    $lflags = LOCK_SH | LOCK_NB  ;
    $fflags = O_CREAT | O_RDONLY ;
    $self->_lockmode(LOCK_SH);
  } else {
    $lflags = LOCK_EX | LOCK_NB;
    $fflags = O_CREAT | O_RDWR ;
    $self->_lockmode(LOCK_EX);
  }

  my $path = $self->File;

 ## proper DB_File locking:
  ## open and tie the DB to _orig
  ## set up object
  ## call a sync() to create if needed
  my $orig_db = tie %{ $self->_orig }, "DB_File", $path,
      $fflags, $self->Perms, $DB_HASH
      or confess "failed db open: $path: $!" ;
  $orig_db->sync();

  ## dup a FH to $db->fd for _lockFH
  my $fd = $orig_db->fd;
  my $fh = IO::File->new("<&=$fd")
    or confess "failed dup in dbopen: $!";

  my $timer = 0;
  my $timeout = $self->Timeout;

  ## flock _lockFH
  until ( flock $fh, $lflags ) {
    if ($timer > $timeout) {
      warn "failed lock for db $path, timeout (${timeout}s)\n";
      undef $orig_db; undef $fh;
      untie %{ $self->_orig };
      return
    }

    sleep 0.01;
    $timer += 0.01;
  }

  ## reopen DB to Tied
  my $db = tie %{ $self->Tied }, "DB_File", $path,
      $fflags, $self->Perms, $DB_HASH
      or confess "failed db reopen: $path: $!";

  ## preserve db obj and lock fh
  $self->is_open(1);
  $self->_lockFH( $fh );
  $self->DB($db);
  undef $orig_db;

  ## install filters
  ## null-terminated to be C-compat
  $self->DB->filter_fetch_key(
    sub { s/\0$// }
  );
  $self->DB->filter_store_key(
    sub { $_ .= "\0" }
  );

  ## JSONified values
  $self->DB->filter_fetch_value(
    sub {
      s/\0$//;
      $_ = $self->Serializer->ref_from_json($_)
        unless $self->Raw;
    }
  );
  $self->DB->filter_store_value(
    sub {
      $_ = $self->Serializer->json_from_ref($_)
        unless $self->Raw;
      $_ .= "\0";
    }
  );

  return 1
}

sub dbclose {
  my ($self) = @_;

  unless ($self->is_open) {
    carp "attempted dbclose on unopened db";
    return
  }

  if ($self->_lockmode == LOCK_EX) {
    $self->DB->sync();
  }

  $self->clear_DB;
  untie %{ $self->Tied }
    or carp "dbclose: untie Tied: $!";

  flock( $self->_lockFH, LOCK_UN )
    or carp "dbclose: unlock: $!";

  untie %{ $self->_orig }
    or carp "dbclose: untie _orig: $!";

  $self->clear_LockFH;
  $self->clear_LockMode;

  $self->is_open(0);

  return 1
}

sub get_tied {
  my ($self) = @_;
  confess "attempted to get_tied on unopened db"
    unless $self->is_open;

  return $self->Tied
}

sub get_db {
  my ($self) = @_;
  confess "attempted to get_db on unopened db"
    unless $self->is_open;

  return $self->DB
}

sub dbkeys {
  my ($self) = @_;
  confess "attempted 'dbkeys' on unopened db"
    unless $self->is_open;

  return wantarray ? (keys %{ $self->Tied })
                   : scalar keys %{ $self->Tied };
}

sub get {
  my ($self, $key) = @_;
  confess "attempted 'get' on unopened db"
    unless $self->is_open;

  return unless exists $self->Tied->{$key};

  return $self->Tied->{$key}
}

sub put {
  my ($self, $key, $value) = @_;
  confess "attempted 'put' on unopened db"
    unless $self->is_open;

  return $self->Tied->{$key} = $value;
}

sub del {
  my ($self, $key) = @_;
  confess "attempted 'del' on unopened db"
    unless $self->is_open;

  return unless exists $self->Tied->{$key};

  delete $self->Tied->{$key};

  return 1
}

sub dbdump {
  my ($self, $format) = @_;
  confess "attempted dbdump on unopened db"
    unless $self->is_open;
  $format = 'YAMLXS' unless $format;

  ## shallow copy to drop tied()
  my %copy = %{ $self->Tied };

  my $dumper = Bot::Cobalt::Serializer->new( Format => $format );

  $dumper->freeze(\%copy)
}

1;
__END__

=pod

=head1 NAME

Bot::Cobalt::DB - Locking Berkeley DBs with serialization

=head1 SYNOPSIS

  use Bot::Cobalt::DB;

  ## ... perhaps in a Cobalt_register ...
  my $db_path = $core->var ."/MyDatabase.db";
  my $db = Bot::Cobalt::DB->new(
    File => $db_path,
  );

  ## Open (and lock):
  $db->dbopen;

  ## Do some work:
  $db->put("SomeKey", $some_deep_structure);

  for my $key ($db->dbkeys) {
    my $this_hash = $db->get($key);
  }

  ## Close and unlock:
  $db->dbclose;


=head1 DESCRIPTION

B<Bot::Cobalt::DB> provides a simple object-oriented interface to basic
L<DB_File> (Berkeley DB 1.x) usage.

BerkDB is a fast and simple key/value store. This module uses JSON to
store nested Perl data structures, providing easy database-backed
storage for L<Bot::Cobalt> plugins.

=head2 Constructor

B<new()> is used to create a new Bot::Cobalt::DB object representing your
Berkeley DB:

  my $db = Bot::Cobalt::DB->new(
    File => $path_to_db,

   ## Optional arguments:

    # Database file mode
    Perms => $octal_mode,

    ## Locking timeout in seconds
    ## Defaults to 5s:
    Timeout => 10,

    ## Normally, references are serialized transparently.
    ## If Raw is enabled, no serialization filter is used and you're
    ## on your own.
    Raw => 0,
  );

=head2 Opening and closing

Database operations should be contained within a dbopen/dbclose:

  ## open, put, close:
  $db->dbopen || croak "dbopen failure";
  $db->put($key, $data);
  $db->dbclose;

  ## open for read-only, read, close:
  $db->dbopen(ro => 1) || croak "dbopen failure";
  my $data = $db->get($key);
  $db->dbclose;

Methods will fail if the DB is not open.

If the DB for this object is open when the object is DESTROY'd, Bot::Cobalt::DB
will attempt to close it safely.

=head2 Locking

Proper locking is done -- that means the DB is 're-tied' after a lock is
granted and state cannot change between database open and lock time.

The attempt to gain a lock will time out after five seconds (and
L</dbopen> will return boolean false).

The lock is cleared on L</dbclose>.

If the Bot::Cobalt::DB object is destroyed, it will attempt to dbclose
for you, but it is good practice to keep track of your open/close
calls and attempt to close as quickly as possible.


=head2 Methods

=head3 dbopen

B<dbopen> opens and locks the database. If 'ro => 1' is specified,
this is a LOCK_SH shared (read) lock; otherwise it is a LOCK_EX
exclusive (write) lock.

Try to call a B<dbclose> as quickly as possible to reduce locking
contention.

dbopen() will return false (and possibly warn) if the database could
not be opened (probably due to lock timeout).

=head3 is_open

Returns a boolean value representing whether or not the DB is currently
open and locked.

=head3 dbclose

B<dbclose> closes and unlocks the database.

=head3 put

The B<put> method adds an entry to the database:

  $db->put($key, $value);

The value can be any data structure serializable by JSON::XS; that is to
say, any shallow or deep data structure NOT including blessed references.

Note that keys should be properly encoded:

  my $key = "\x{263A}";
  utf8::encode($key);
  $db->put($key, $data);

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
  ## JSON::XS
  my $jsonified = $db->dbdump('JSON');

See L<Bot::Cobalt::Serializer> for more on C<freeze()> and valid formats.

A tool called B<cobalt2-dbdump> is available as a
simple frontend to this functionality. See C<cobalt2-dbdump --help>

=head1 FORMAT

B<Bot::Cobalt::DB> databases are Berkeley DB 1.x, with NULL-terminated records
and values stored as JSON. They're intended to be easily portable to
other non-Perl applications.

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
