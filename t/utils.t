use Test::More tests => 6;

BEGIN {
  use_ok( 'Cobalt::Utils', qw/
    mkpasswd passwdcmp 
    rplprintf 
    timestr_to_secs
    glob_grep glob_to_re glob_to_re_str
  / );
}

my @alph = ( 'a' .. 'z' );
my $passwd = join '', map { $alph[rand @alph] } 1 .. 8;
my $crypted = mkpasswd($passwd);
ok( $crypted, 'bcrypt-enabled mkpasswd()' );
ok( passwdcmp($passwd, $crypted), 'bcrypt-enabled passwd comparison' );

## rplprintf
my $tmpl = 'String %variable other %doublesig% misc %trailing';
my $vars = {
  variable => "First variable",
  doublesig => "Doubled",
  trailing  => "trailing!",
};
my $expect = 'String First variable other Doubled misc trailing!';
my $formatted = rplprintf( $tmpl, $vars );
ok($formatted eq $expect, 'rplprintf string formatting');

## timestr_to_secs
ok( timestr_to_secs('10m') == 600, 'timestr_to_secs (10m)' );
ok( timestr_to_secs('2h10m8s') == 7808, 'timestr_to_secs (2h10m8s)' );

# FIXME globs
