package Bot::Cobalt::Plugin::RDB::Database;
our $VERSION = '0.008';

## Frontend to managing RDB-style Bot::Cobalt::DB instances
## I regret writing this.
##
## We may have a lot of RDBs.
## This plugin tries to make it easy to operate on them discretely
## with a minimum of angst in the frontend app.
##
## If there is no DB in our RDBDir named 'main' it is initialized.
##
## If an error occurs, the first argument returned will be boolean false.
## The error as a simple string is available via the 'Error' method.
## These values are only 'sort-of' human readable; they're holdovers from 
## the previous constant retvals, and typically translated into langset 
## RPLs by Plugin::RDB.
##
## Our RDB interfaces typically take RDB names; we map them to paths and 
## attempt to switch our ->{CURRENT} Bot::Cobalt::DB object appropriately.
##
## The frontend doesn't have to worry about dbopen/dbclose, which works 
## for RDBs because access is almost always a single operation and we 
## can afford to open / lock / access / unlock / close every call.

use 5.10.1;
use strict;
use warnings;
use Carp;

use Bot::Cobalt::DB;

use Bot::Cobalt::Plugin::RDB::SearchCache;

use Bot::Cobalt::Utils qw/ glob_to_re_str /;

use Cwd qw/ abs_path /;

use Digest::SHA qw/sha256_hex/;

use File::Path qw/mkpath/;

use File::Spec;

use Time::HiRes;

use List::Util qw/shuffle/;

use POE;

sub new {
  my $self = {};
  my $class = shift;
  bless $self, $class;

  my %opts = @_;
  
  require Bot::Cobalt::Core;
  my $core = Bot::Cobalt::Core->instance;
  $self->{core} = $core;

  my $rdbdir = $opts{RDBDir};  
  $self->{RDBDir} = $rdbdir;
  unless ( $self->{RDBDir} ) {
    croak "new() needs a RDBDir parameter"
  }
  
  $self->{CacheObj} = Bot::Cobalt::Plugin::RDB::SearchCache->new(
    MaxKeys => $opts{CacheKeys} // 30,
  );
  
  $core->log->debug("Using RDBDir $rdbdir");
  
  unless (-e $rdbdir) {
    $core->log->debug("Did not find RDBDir $rdbdir, attempting mkpath");
    mkpath($rdbdir);
  }
  
  unless (-d $rdbdir) {
    $core->log->error("$rdbdir not a directory");
    return
  }
  
  unless ( $self->dbexists('main') ) {
    $core->log->debug("No main RDB found, creating one");
    
    unless ( $self->createdb('main') ) {
      my $err = $self->Error;
      $core->log->warn("Could not create 'main' RDB: $err");
    }
  }
  
  return $self
}

sub dbexists {
  my ($self, $rdb) = @_;
  my $path = $self->path_from_name($rdb);
  return 1 if -e $path;
  return
}

sub Error {
  my ($self, $err) = @_;
  return $self->{ERRORMSG} = $err if defined $err;
  return $self->{ERRORMSG}
}

sub path_from_name {
  my ($self, $rdb) = @_;
  
  return File::Spec->catfile(
    $self->{RDBDir},
    $rdb .".rdb"
  );
}

sub createdb {
  my ($self, $rdb) = @_;
  
  $self->Error(0);
  
  unless ($rdb && $rdb =~ /^[A-Za-z0-9]+$/) {
    $self->Error("RDB_INVALID_NAME");
    return 0
  }

  if ( $self->dbexists($rdb) ) {
    $self->Error("RDB_EXISTS");
    return 0
  }
  
  my $core = $self->{core};
  $core->log->debug("attempting to create RDB $rdb");
  
  my $path = $self->path_from_name($rdb);

  $self->_rdb_switch($rdb);
  my $db = $self->{CURRENT};
  unless ( ref $db ) {
    $core->log->error("Could not switch to RDB $rdb at $path");
    $self->Error("RDB_DBFAIL");
    return 0
  }
  
  unless ( $db->dbopen ) {
    $core->log->error("dbopen failure for $rdb in createdb");
    $self->Error("RDB_DBFAIL");
    return 0
  }
  
  $db->dbclose;
  
  $core->log->info("Created RDB $rdb");
  
  return 1
}

sub deldb {
  my ($self, $rdb) = @_;
  my $core = $self->{core};

  $self->Error(0);
  
  unless ( $self->dbexists($rdb) ) {
    $self->Error("RDB_NOSUCH");
    return 0
  }
  
  $self->_rdb_switch($rdb);
  my $db = $self->{CURRENT};
  unless ( ref $db ) {
    $core->log->error("deldb failure; cannot switch to $rdb");
    $self->Error("RDB_DBFAIL");
    return 0
  }
  
  unless ( $db->dbopen ) {
    $core->log->error("dbopen failure for $rdb in deldb");
    $core->log->error("Refusing to unlink, admin should investigate.");
    $self->Error("RDB_DBFAIL");
    return 0
  }
  $db->dbclose;
  $self->{CURRENT} = undef;
  undef $db;

  my $cache = $self->{CacheObj};
  $cache->invalidate($rdb);

  my $path = $self->path_from_name($rdb);
  unless ( unlink($path) ) {
    $core->log->error("Cannot unlink RDB $rdb at $path: $!");
    $self->Error("RDB_FILEFAILURE");
    return 0
  }
    
  $core->log->info("Deleted RDB $rdb");
  
  return 1
}

sub del {
  my ($self, $rdb, $key) = @_;
  my $core = $self->{core};
  
  $self->Error(0);
  
  unless ( $self->dbexists($rdb) ) {
    $self->Error("RDB_NOSUCH");
    return 0
  }
  
  $self->_rdb_switch($rdb);
  my $db = $self->{CURRENT};
  
  unless ( ref $db ) {
    $core->log->error("del failure; cannot switch to $rdb");
    $self->Error("RDB_DBFAIL");
    return 0
  }
  
  unless ( $db->dbopen ) {
    $core->log->error("dbopen failure for $rdb in del");
    $self->Error("RDB_DBFAIL");
    return 0
  }
  
  unless ( $db->get($key) ) {
    $db->dbclose;
    $core->log->debug("no such item: $key in $rdb");
    $self->Error("RDB_NOSUCH_ITEM");
    return 0
  }
  
  unless ( $db->del($key) ) {
    $db->dbclose;
    $core->log->warn("failure in db->del for $key in $rdb");
    $self->Error("RDB_DBFAIL");
    return 0
  }
  
  ## invalidate search cache
  my $cache = $self->{CacheObj};
  $cache->invalidate($rdb);
  
  $db->dbclose;
  return 1
}

sub get {
  my ($self, $rdb, $key) = @_;
  my $core = $self->{core};

  $self->Error(0);

  unless ( $self->dbexists($rdb) ) {
    $self->Error("RDB_NOSUCH");
    return 0
  }
  
  $self->_rdb_switch($rdb);
  my $db = $self->{CURRENT};
  
  unless ( ref $db ) {
    $core->log->error("get failure; cannot switch to $rdb");
    $self->Error("RDB_DBFAIL");
    return 0
  }
  
  unless ( $db->dbopen(ro => 1) ) {
    $core->log->error("dbopen failure for $rdb in get");
    $self->Error("RDB_DBFAIL");
    return 0
  }
  
  my $value = $db->get($key);
  unless ( defined $value ) {
    $self->Error("RDB_NOSUCH_ITEM");
    $db->dbclose;
    return 0
  }
  
  $db->dbclose;
  
  return $value
}

sub get_keys {
  my ($self, $rdb) = @_;
  return unless $self->dbexists($rdb);
  my $core = $self->{core};
  
  $self->_rdb_switch($rdb);
  my $db = $self->{CURRENT};
  unless ( ref $db ) {
    $core->log->error("get_keys failure; cannot switch to $rdb");
    return
  }
  
  unless ( $db->dbopen(ro => 1) ) {
    $core->log->error("dbopen failure for $rdb in get_keys");
    return
  }
  
  my @dbkeys = $db->dbkeys;
  $db->dbclose;
  return wantarray ? @dbkeys : scalar(@dbkeys) ;
}

sub put {
  my ($self, $rdb, $ref) = @_;
  
  $self->Error(0);
  unless ( $self->dbexists($rdb) ) {
    $self->Error("RDB_NOSUCH");
    return 0
  }
  
  my $core = $self->{core};
  
  $self->_rdb_switch($rdb);
  my $db = $self->{CURRENT};
  unless ( ref $db ) {
    $core->log->error("put failure; cannot switch to $rdb");
    $self->Error("RDB_DBFAIL");
    return 0
  }
  
  unless ( $db->dbopen ) {
    $core->log->error("dbopen failure for $rdb in put");
    $self->Error("RDB_DBFAIL");
    return 0
  }
  
  my $newkey = $self->_gen_unique_key($ref);
  
  unless ( $db->put($newkey, $ref) ) {
    $db->dbclose;
    $self->Error("RDB_DBFAIL");
    return 0
  }

  $db->dbclose;
  
  my $cache = $self->{CacheObj};
  $cache->invalidate($rdb);

  return $newkey
}

sub random {
  my ($self, $rdb) = @_;
  
  $self->Error(0);
  unless ( $self->dbexists($rdb) ) {
    $self->Error("RDB_NOSUCH");
    return 0
  }

  my $core = $self->{core};
  
  $self->_rdb_switch($rdb);
  my $db = $self->{CURRENT};
  unless ( ref $db ) {
    $core->log->error("random failure; cannot switch to $rdb");
    $self->Error("RDB_DBFAIL");
    return 0
  }
  
  unless ( $db->dbopen(ro => 1) ) {
    $core->log->error("dbopen failure for $rdb in random");
    $self->Error("RDB_DBFAIL");
    return 0
  }
  
  my @dbkeys = $db->dbkeys;
  unless (@dbkeys) {
    $db->dbclose;
    $self->Error("RDB_NOSUCH_ITEM");
    return 0
  }
  
  my $randkey = $dbkeys[rand @dbkeys];
  my $ref = $db->get($randkey);
  unless (ref $ref) {
    $db->dbclose;
    $core->log->error("Broken DB? item $randkey in $rdb not a ref");
    $self->Error("RDB_DBFAIL");
    return 0
  }
  $db->dbclose;
  
  return $ref
}

sub cache_check {
  my ($self, $rdb, $glob) = @_;
  my $cache = $self->{CacheObj};
  
  my @matches = $cache->fetch($rdb, $glob);
  return @matches
}

sub cache_push {
  my ($self, $rdb, $glob, $ref) = @_;
  my $cache = $self->{CacheObj};
  
  $cache->cache($rdb, $glob, $ref);
}

sub search {
  my ($self, $rdb, $glob, $wantone) = @_;

  $self->Error(0);
  unless ( $self->dbexists($rdb) ) {
    $self->Error("RDB_NOSUCH");
    return 0
  }  

  my $core = $self->{core};
  
  $self->_rdb_switch($rdb);
  my $db = $self->{CURRENT};
  unless ( ref $db ) {
    $core->log->error("search failure; cannot switch to $rdb");
    $self->Error("RDB_DBFAIL");
    return 0
  }
  
  ## hit search cache first
  my $cache = $self->{CacheObj};
  my @matches = $cache->fetch($rdb, $glob);
  if (@matches) {
    if ($wantone) {
      return (shuffle @matches)[-1];
    } else {
      return wantarray ? @matches : [ @matches ] ;
    }
  }

  my $re = glob_to_re_str($glob);
  $re = qr/$re/i;

  unless ( $db->dbopen(ro => 1) ) {
    $core->log->error("dbopen failure for $rdb in search");
    $self->Error("RDB_DBFAIL");
    return 0
  }
  
  my @dbkeys = $db->dbkeys;
  for my $dbkey (shuffle @dbkeys) {
    my $ref = $db->get($dbkey) // next;
    my $str = ref $ref eq 'HASH' ? $ref->{String} : $ref->[0] ;
    if ($str =~ $re) {
      if ($wantone) {
        ## plugin only cares about one match, short-circuit
        $db->dbclose;
        return $dbkey
      } else {
        push(@matches, $dbkey);
      }
    }
  }
  
  $db->dbclose;

  ## WANTONE but we didn't find any, return
  return undef if $wantone;
  
  ## push back to cache
  $cache->cache($rdb, $glob, [ @matches ] );
  
  return wantarray ? @matches : [ @matches ] ;
}

sub _gen_unique_key {
  my ($self, $ref) = @_;
  my $db = $self->{CURRENT} 
           || croak "_gen_unique_key called but no db to check";
  my $stringified = "$ref" . Time::HiRes::time();
  my $digest = sha256_hex($stringified);
  my @splitd = split //, $digest;
  my $newkey = join '', splice(@splitd, -4);
  $newkey .= pop @splitd while exists $db->Tied->{$newkey} and @splitd;
  ## regen 0000 keys:
  return $newkey || $self->_gen_unique_key($ref)
}

sub _rdb_switch {
  my ($self, $rdb) = @_;
  
  undef $self->{CURRENT};
  
  my $core = $self->{core};
  my $path = $self->path_from_name($rdb);
  unless ($path) {
    $core->log->error("_rdb_switch failed; no path for $rdb");
    return
  }
  
  $self->{CURRENT} = Bot::Cobalt::DB->new(
    File => $path,
  );
}

1;
__END__
