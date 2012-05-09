use Test::More tests => 28;

use 5.10.1;
use Fcntl qw/ :flock /;
use File::Spec;
use File::Temp qw/ tempfile tempdir /;

BEGIN { use_ok( 'Bot::Cobalt::DB' ); }

my $workdir = File::Spec->tmpdir;
my $tempdir = tempdir( CLEANUP => 1, DIR => $workdir );

my ($fh, $path) = _newtemp();
my $db;

ok( $db = Bot::Cobalt::DB->new( File => $path ), 'Cobalt::DB new()' );
can_ok( $db, 'dbopen', 'dbclose', 'put', 'get', 'dbkeys' );

ok( $db->dbopen, 'Temp database open' );

diag("This should produce a warning:");
ok( !$db->dbopen, 'Cannot reopen' );

ok( $db->File eq $path, 'Temp database File');

ok( $db->is_open, 'Temp database is_open' );

ok( $db->put('testkey', { Deep => { Hash => 1 } }), 'Database ref put()');

ok( ($db->dbkeys)[0] eq 'testkey', 'DB has expected dbkeys()');
my $ref;
ok( $ref = $db->get('testkey'), 'Database get()' );
ok( $ref->{Deep}->{Hash}, 'Database put() vs get()' );

undef $ref;

ok( $db->dbkeys, 'Database dbkeys()' );

$db->dbclose;

ok( !$db->is_open, 'Temp database !is_open' );

ok( $db->dbopen, 'Temp database reopen' );

ok( $ref = $db->get('testkey'), 'Database get() 2' );
ok( $ref->{Deep}->{Hash}, 'Original DB put() vs this get()' );

ok( $db->put('scalarkey', "A scalar"), 
  'Inserting scalar string' 
);
ok( $db->get('scalarkey') eq "A scalar",
  'Retrieve and compare scalar' 
);

ok( $db->put('intkey', 2),
  'Inserting scalar int'
);
ok( $db->get('intkey') == 2, 
  'Retrieve and compare int'
);

cmp_ok( $db->dbkeys, '==', 3, "DB has expected num. of keys");
ok( 
  my @keys = $db->dbkeys
  && 'testkey' ~~ @keys
  && 'scalarkey' ~~ @keys
  && 'intkey' ~~ @keys,
  'DB has expected keys'
);

ok( $db->del('intkey'), 'Database del() 1' );
ok( $db->del('testkey'), 'Database del() 2' );
cmp_ok( $db->dbkeys, '==', 1, "DB has expected keys after del");
is( ($db->dbkeys)[0], 'scalarkey', "DB has expected key after del");

$db->dbclose;

ok( $db->dbopen(ro => 1), 'Database RO open' );
ok( $db->get('scalarkey'), 'Database RO get' );
$db->dbclose;

sub _newtemp {
    my ($fh, $filename) = tempfile( 'tmpdbXXXXX', 
      DIR => $tempdir, UNLINK => 1 
    );
    flock $fh, LOCK_UN;
    return($fh, $filename)
}
