use Test::More tests => 4;


BEGIN {
  use_ok( 'Bot::Cobalt::Utils', qw/
    color
  / );
}

use IRC::Utils qw/has_color has_formatting/;

my $format;
ok( 
    $format = color('bold') 
            . "Bold text" 
            . color('teal') 
            . "Teal text" 
            . color('normal'),
    "Format string: bold, teal"
);

ok( has_formatting($format), "color() string has formatting" );
ok( has_color($format), "color() string has color" );
