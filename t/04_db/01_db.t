use Test::More tests => 15;

use Fcntl qw/ :flock /;
use File::Spec;
use File::Temp qw/ tempfile tempdir /;

BEGIN { use_ok( 'Cobalt::DB' ); }

my $workdir = File::Spec->tmpdir;
my $tempdir = tempdir( CLEANUP => 1, DIR => $workdir );

my ($fh, $path) = _newtemp();
my $db;

ok( $db = Cobalt::DB->new( File => $path ), 'Cobalt::DB new()' );
can_ok( $db, 'dbopen', 'dbclose', 'put', 'get', 'dbkeys' );

ok( $db->dbopen, 'Temp database open' );

ok( $db->put('testkey', { Deep => { Hash => 1 } }), 'Database ref put()');

my $ref;
ok( $ref = $db->get('testkey'), 'Database get()' );
ok( $ref->{Deep}->{Hash}, 'Database put() vs get()' );

undef $ref;

ok( $db->dbkeys, 'Database dbkeys()' );

$db->dbclose;

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

$db->dbclose;

sub _newtemp {
    my ($fh, $filename) = tempfile( 'tmpdbXXXXX', 
      DIR => $tempdir, UNLINK => 1 
    );
    flock $fh, LOCK_UN;
    return($fh, $filename)
}
