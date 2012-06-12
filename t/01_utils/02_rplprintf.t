use Test::More tests => 8;

BEGIN {
  use_ok( 'Bot::Cobalt::Utils', qw/
    rplprintf 
  / );
  
  use_ok( 'IRC::Utils', qw/ has_formatting / );
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

undef $formatted;
ok($formatted = rplprintf( $tmpl, %$vars ), 'rplprintf passed list' );
ok($formatted eq $expect, 'compare formatted str (list-style args)');

undef $formatted;
undef $tmpl;
my $c_vars = {
  somebold => "Some bold text",
};
$tmpl = 'String %C_BOLD %somebold %C_NORMAL%normal text';

ok($formatted = rplprintf( $tmpl, $c_vars ), 'rplprintf C_ vars (ref)' );
ok( has_formatting($formatted), 'rplprintf C_ vars has_formatting' );
