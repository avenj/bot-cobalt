use 5.12.1;
use Test::More tests => 17;

use Fcntl qw/ :flock /;
use File::Temp qw/ tempfile tempdir /;

## Test JSON, YAML (Cobalt::Serializer)

BEGIN {
  use_ok( 'Cobalt::Serializer' );
}

my $hash = {
  Scalar => "A string",
  Int => 3,
  Array => [ "Item", "Another" ],
};

JSON: {
  my $js_ser = Cobalt::Serializer->new( 'JSON' );
  can_ok($js_ser, 'freeze');
  my $json = $js_ser->freeze($hash);
  ok( $json, 'JSON freeze');

  can_ok($js_ser, 'thaw');
  my $json_thawed = $js_ser->thaw($json);
  ok( $json_thawed, 'JSON thaw');

  is_deeply($hash, $json_thawed, 'JSON comparison' );
}

JSONRW: {
  my $js_ser = Cobalt::Serializer->new( 'JSON' );
  can_ok($js_ser, 'readfile', 'writefile' );

  my ($fh, $fname) = _newtemp();
  ok( $js_ser->writefile($fname, $hash), 'JSON file write');
  
  my $jsref;
  ok( $jsref = $js_ser->readfile($fname), 'JSON file read');
  
  is_deeply($hash, $jsref, 'JSON file read-write compare' );
}

YAML: {
  my $yml_ser = Cobalt::Serializer->new();
  my $yml = $yml_ser->freeze($hash);
  ok( $yml, 'YAML freeze');

  my $yml_thawed = $yml_ser->thaw($yml);
  ok( $yml_thawed, 'YAML thaw');

  is_deeply($hash, $yml_thawed, 'YAML comparison' );
}

YAMLRW: {
  my $yml_ser = Cobalt::Serializer->new();
  can_ok($yml_ser, 'readfile', 'writefile' );

  my ($fh, $fname) = _newtemp();
  ok( $yml_ser->writefile($fname, $hash), 'YAML file write');
  
  my $ymlref;
  ok( $ymlref = $yml_ser->readfile($fname), 'YAML file read');
  
  is_deeply($hash, $ymlref, 'YAML file read-write compare' );
}

sub _newtemp {
    my ($fh, $filename) = tempfile( 'tmpdbXXXXX', 
      DIR => tempdir( CLEANUP => 1 ), UNLINK => 1
    );
    flock $fh, LOCK_UN;
    return($fh, $filename)
}
