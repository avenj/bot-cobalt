use Test::More tests => 19;

## Cobalt::Utils tests

BEGIN {
  use_ok( 'Cobalt::Utils', qw/
    color
    mkpasswd passwdcmp 
    rplprintf 
    timestr_to_secs
    glob_grep glob_to_re glob_to_re_str
  / );
}

use IRC::Utils qw/has_color has_formatting/;

MKPASSWD: {
  my @alph = ( 'a' .. 'z' );
  my $passwd = join '', map { $alph[rand @alph] } 1 .. 8;
  my $bcrypted = mkpasswd($passwd);
  ok( $bcrypted, 'bcrypt-enabled mkpasswd()' );
  ok( passwdcmp($passwd, $bcrypted), 'bcrypt-enabled passwd comparison' );
  
  my $md5crypt = mkpasswd($passwd, 'md5');
  ok( $md5crypt, 'MD5 mkpasswd()' );
  ok( passwdcmp($passwd, $md5crypt), 'MD5 passwd comparison' );
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

  my @array = ( "Test array", "Another item" );
  
  ok( glob_grep('^Anoth*', @array), "glob_grep against array" );
  ok( glob_grep('*t+array$', \@array), "glob_grep against arrayref" );
  ok( !glob_grep('Non*existant', @array), "negative glob_grep against array");
  ok( !glob_grep('Non*existant', \@array), "negative glob_grep against ref");
}

COLOR: {
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
}
