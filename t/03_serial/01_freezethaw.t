use 5.12.1;
use Test::More tests => 9;

BEGIN {
  use_ok( 'Bot::Cobalt::Serializer' );
}

my $hash = {
  Scalar => "A string",
  Int => 3,
  Array => [ qw/Two Items/ ],
  Hash  => { Some => { Deep => 'Hash' } },
};

JSON: {
  my $js_ser = Bot::Cobalt::Serializer->new( 'JSON' );
  can_ok($js_ser, 'freeze', 'thaw');
  my $json = $js_ser->freeze($hash);
  ok( $json, 'JSON freeze');

  my $json_thawed = $js_ser->thaw($json);
  ok( $json_thawed, 'JSON thaw');

  is_deeply($hash, $json_thawed, 'JSON comparison' );
}

YAML: {
  my $yml_ser = Bot::Cobalt::Serializer->new();
  can_ok($yml_ser, 'freeze', 'thaw');
  my $yml = $yml_ser->freeze($hash);
  ok( $yml, 'YAML freeze');

  my $yml_thawed = $yml_ser->thaw($yml);
  ok( $yml_thawed, 'YAML thaw');

  is_deeply($hash, $yml_thawed, 'YAML comparison' );
}
