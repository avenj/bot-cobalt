use Test::More tests => 10;

BEGIN {
  use_ok( 'Cobalt::Utils', qw/
    mkpasswd passwdcmp 
    rplprintf 
    timestr_to_secs
    glob_grep glob_to_re glob_to_re_str
  / );
}

MKPASSWD: {
  my @alph = ( 'a' .. 'z' );
  my $passwd = join '', map { $alph[rand @alph] } 1 .. 8;
  my $crypted = mkpasswd($passwd);

  ok( $crypted, 'bcrypt-enabled mkpasswd()' );
  ok( passwdcmp($passwd, $crypted), 'bcrypt-enabled passwd comparison' );
}

RPLPRINTF: {
  my $tmpl = 'String %variable other %doublesig% misc %trailing';
  my $vars = {
    variable => "First variable",
    doublesig => "Doubled",
    trailing  => "trailing!",
  };

  my $expect = 'String First variable other Doubled misc trailing!';
  my $formatted = rplprintf( $tmpl, $vars );
  ok($formatted eq $expect, 'rplprintf string formatting');
}

TIMESTR: {
  ok( timestr_to_secs('10m') == 600, 'timestr_to_secs (10m)' );
  ok( timestr_to_secs('2h10m8s') == 7808, 'timestr_to_secs (2h10m8s)' );
}

GLOBS: {
  my $globs = {
    'th*ngs+stuff' => 'th.*ngs\sstuff',
    '^an?chor$'    => '^an.chor$',
  };

  for my $glob (keys %$globs) {
    my $regex;
    ok( $regex = glob_to_re_str($glob), "Convert glob" )
      or diag("Could not convert $glob to regex");
    ok( $regex eq $globs->{$glob}, "Compare glob<->regex" )
      or diag(
        "Expected: ".$globs->{$glob},
        "\nGot: ".$regex,
      );
  }

}
