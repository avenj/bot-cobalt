package Cobalt::Plugin::RDB::Database;
our $VERSION = '0.24';

## Cobalt2 RDB manager

use 5.12.1;
use strict;
use warnings;
use Carp;

use Cobalt::DB;

use Cobalt::Plugin::RDB::Constants;
use Cobalt::Plugin::RDB::SearchCache;

use Cobalt::Utils qw/glob_to_re_str/;

use Cwd qw/abs_path/;

use Digest::SHA1 qw/sha1_hex/;

use File::Basename qw/fileparse/;
use File::Find;
use File::Path qw/mkpath/;

use Time::HiRes;


sub new {
  my $self = {};
  my $class = shift;
  bless $self, $class;
  
  my %opts = @_;
  
  $self->{core} = $opts{core};
  unless ( ref $self->{core} ) {
    croak "new() needs a core object parameter"
  }
  
  $self->{RDBDir} = $opts{RDBDir};
  unless ( $self->{RDBDir} ) {
    croak "new() needs a RDBDir parameter"
  }
  
  $self->{RDBPaths} = { };

  $self->{CacheObj} = Cobalt::Plugin::RDB::SearchCache->new(
    MaxKeys => $opts{CacheKeys} // 30,
  );

  ## initialize paths:
  $self->get_paths();
  
  return $self
}


sub get_paths {
  ## Initialization -- Find our RDBs
  my ($self) = @_;
  my $core = $self->{core};

  my $rdbdir = $self->{RDBDir};
  $core->log->debug("Using RDBDir $rdbdir");
  unless (-e $rdbdir) {
    $core->log->debug("Did not find RDBDir $rdbdir, attempting mkpath");
    mkpath($rdbdir);
  }

  unless (-d $rdbdir) {
    croak "RDBDir not a directory: $rdbdir";
  }
  
  my @paths;
  find(sub {
      return if $File::Find::fullname ~~ @paths;
      push(@paths, $File::Find::fullname)
        if $_ =~ /\.rdb$/;
    },
    $rdbdir
  );

  for my $path (@paths) {
    my $rdb_name = fileparse($path, '.rdb');
    ## attempt to open this RDB to see if it's busted:
    $self->{RDBPaths}->{$rdb_name} = $path;
    my $cdb = $self->_dbopen($rdb_name);
    unless ($cdb) {
      delete $self->{RDBPaths}->{$rdb_name};
      $core->log->error("dbopen failure for $rdb_name");
      next
    }
    $cdb->dbclose;
    $core->log->debug("mapped $rdb_name -> $path");
  }
  
  ## see if we have 'main'
  unless ( $self->dbexists('main') ) {
    $core->log->debug("No main RDB found, creating one");
    $core->log->warn("Could not create 'main' RDB")
      unless $self->createdb('main') == SUCCESS;
  }

  $core->log->debug("RDBs added");
}

sub dbexists {
  my ($self, $rdb) = @_;
  return 1 if $self->{RDBPaths}->{$rdb};
  return
}

sub createdb {
  ## Initialize an empty RDB
  ## return RDB_EXISTS, RDB_DBFAIL, SUCCESS
  my ($self, $rdb) = @_;

  return RDB_INVALID_NAME unless $rdb =~ /^[A-Za-z0-9]+$/;

  return RDB_EXISTS if $self->{RDBPaths}->{$rdb};

  $self->{core}->log->debug("creating RDB $rdb");
  
  my $path = $self->{RDBDir} ."/". $rdb .".rdb";
   # add to RDBPaths first so _dbopen can grab the path:
  $self->{RDBPaths}->{$rdb} = $path;
   # then try to open a Cobalt::DB:
  my $cdb = $self->_dbopen($rdb);
  unless ($cdb) {
    $self->{core}->log->debug("_dbopen failure for $rdb");
    delete $self->{RDBPaths}->{$rdb};
    return RDB_DBFAIL
  }

  ## these dbcloses are optional, but good practice
  ## Cobalt::DB will dbclose at DESTROY time
  $cdb->dbclose;

  $self->{core}->log->debug("created: $rdb");

  return SUCCESS  
}

sub deldb {
  my ($self, $rdb) = @_;
  my $core = $self->{core};

  return RDB_NOSUCH unless $self->{RDBPaths}->{$rdb};
  
  my $path = $self->{RDBPaths}->{$rdb};
  
  unless (-e $path && ( -f $path || -l $path ) ) {
    $core->log->error(
      "Cannot delete RDB $rdb - $path not found or not a file"
    );
    return RDB_NOSUCH
  }

  my $cdb = $self->_dbopen($rdb);
  unless ($cdb) {
    $core->log->error("Cannot delete RDB $rdb - might not be a valid DB");
    return RDB_DBFAIL
  }
  $cdb->dbclose;
  
  unless ( unlink($path) ) {
    $core->log->error("Cannot delete RDB $rdb - unlink: ${path}: $!");
    return RDB_FILEFAILURE
  }

  delete $self->{RDBPaths}->{$rdb};
  return SUCCESS
}

sub del {
  my ($self, $rdb, $key) = @_;

  return RDB_NOSUCH unless $self->{RDBPaths}->{$rdb};

  my $cdb = $self->_dbopen($rdb);
  return RDB_DBFAIL unless $cdb;

  unless ( $cdb->get($key) ) {
    $cdb->dbclose;
    return RDB_NOSUCH_ITEM
  }
  unless ( $cdb->del($key) ) {
    $cdb->dbclose;
    return RDB_DBFAIL 
  }

  $cdb->dbclose;  
  $self->{CacheObj}->invalidate($rdb);

  return SUCCESS
}

sub get {
  ## Grab a specific key from RDB
  my ($self, $rdb, $key) = @_; 
  return RDB_NOSUCH unless $self->{RDBPaths}->{$rdb};
  
  my $cdb = $self->_dbopen($rdb);
  return RDB_DBFAIL unless $cdb;
  
  my $value = $cdb->get($key);
  $value = RDB_NOSUCH_ITEM unless defined $value;
  $cdb->dbclose;
  return $value
}

sub get_keys {
  my ($self, $rdb) = @_;
  return RDB_NOSUCH unless $self->{RDBPaths}->{$rdb};
  my $cdb = $self->_dbopen($rdb);
  return RDB_DBFAIL unless $cdb;
  my @keys = $cdb->keys || ();
  $cdb->dbclose;
  return @keys
}

sub put {
  my ($self, $rdb, $ref) = @_;
  ## Add new entry to RDB
  ## Return the item's key
  return RDB_NOSUCH unless $self->{RDBPaths}->{$rdb};
  
  my $cdb = $self->_dbopen($rdb);
  return RDB_DBFAIL unless $cdb;

  my $key = $self->_gen_unique_key($cdb, $rdb, $ref);

  unless ( $cdb->put($key, $ref) ) {
    $cdb->dbclose;
    return RDB_DBFAIL 
  }
  $self->{CacheObj}->invalidate($rdb);
  $cdb->dbclose;
  return $key
}

sub random {
  my ($self, $rdb) = @_;
  ## Grab a random entry from specified rdb
  return RDB_NOSUCH unless $self->{RDBPaths}->{$rdb};
  
  my $cdb = $self->_dbopen($rdb);
  return RDB_DBFAIL unless $cdb;
  
  my @dbkeys = $cdb->keys;
  unless (@dbkeys) {
    $cdb->dbclose;
    return RDB_NOSUCH_ITEM
  }
  
  my $randkey = $dbkeys[rand @dbkeys];
  my $ref = $cdb->get($randkey);
  unless (ref $ref) {
    $cdb->dbclose;
    return RDB_NOSUCH_ITEM
  }
  $cdb->dbclose;
  ## add the key 'DBKEY' to this hash:
  $ref->{DBKEY} = $randkey;
  return $ref
}

sub search {
  my ($self, $rdb, $glob) = @_;
  ## Search RDB entries, get an array(ref) of matching keys
  $glob = '*' unless $glob;
  
  return RDB_NOSUCH unless $self->{RDBPaths}->{$rdb};

  ## hit the search cache first
  my @cached_result = $self->{CacheObj}->fetch($rdb, $glob);
  
  if (@cached_result) { 
    return wantarray ? @cached_result : [ @cached_result ]
  }

  my $re = glob_to_re_str($glob);
  $re = qr/$re/i;

  my $cdb = $self->_dbopen($rdb);
  return RDB_DBFAIL unless $cdb;

  my @matches;  
  for my $dbkey ($cdb->keys) {
    my $ref = $cdb->get($dbkey) // next;
    my $str = $ref->{String} // '';
    push(@matches, $dbkey) if $str =~ $re;
  }
  
  $cdb->dbclose;
  
  ## Push resultset to the SearchCache
  $self->{CacheObj}->cache($rdb, $glob, [ @matches ]);
  
  return wantarray ? @matches : [ @matches ] ;
}

sub _dbopen {
  my ($self, $rdb) = @_;
  my $core = $self->{core};
  my $path = $self->{RDBPaths}->{$rdb};
  unless ($path) {
    $core->log->error("_dbopen failed; no path for $rdb?");
    return
  }

  my $cdb = Cobalt::DB->new(
    File => $path,
  );
  
  unless ( $cdb->dbopen ) {
    $core->log->error("Cobalt::DB dbopen failure for $rdb");
    return
  }
  
  ## Return the $cdb obj for this rdb
  return $cdb
}

sub _gen_unique_key {
  ## _gen_unique_key($cdb, $rdb, $ref)
  ##  Create unique key for this rdb item
  my ($self, $cdb, $rdb, $ref) = @_;
  
  unless (ref $cdb and $cdb->{Tied}) {
    warn "_gen_unique_key cannot find Cobalt::DB tied hash";
  }

  my $stringified = $ref->{String} .rand. Time::HiRes::time();
  my $digest = sha1_hex($stringified);
  
  ## start at 4, add back chars if it's not unique:
  my @splitd = split //, $digest;
  my $newkey = join '', splice(@splitd, -4);
  $newkey .= pop @splitd while exists $cdb->{Tied}{$newkey} and @splitd;
  return $newkey  
}

1;
