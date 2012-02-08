package Cobalt::Plugin::RDB::Constants;
our $VERSION = '0.20';

use strict;
use warnings;

use Exporter 'import';

our @EXPORT = qw{
  SUCCESS
  RDB_EXISTS 
  RDB_DBFAIL 
  RDB_NOSUCH 
  RDB_NOSUCH_ITEM
  RDB_INVALID_NAME 
  RDB_NOTPERMITTED
  RDB_FILEFAILURE
};

use constant {
  SUCCESS => 1,
  RDB_EXISTS          => 2,
  RDB_DBFAIL          => 3,
  RDB_NOSUCH          => 4,
  RDB_NOSUCH_ITEM     => 5,
  RDB_INVALID_NAME    => 6,
  RDB_NOTPERMITTED    => 7,
  RDB_FILEFAILURE     => 8,
};

1;
