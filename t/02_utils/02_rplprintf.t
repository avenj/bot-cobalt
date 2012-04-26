use Test::More tests => 3;

BEGIN {
  use_ok( 'Bot::Cobalt::Utils', qw/
    rplprintf 
  / );
}

my $tmpl = 'String %variable other %doublesig% misc %trailing';
my $vars = {
    variable => "First variable",
    doublesig => "Doubled",
    trailing  => "trailing!",
};

my $expect = 'String First variable other Doubled misc trailing!';
my $formatted;
ok($formatted = rplprintf( $tmpl, $vars ), 'rplprintf format str');
ok($formatted eq $expect, 'compare formatted str');
