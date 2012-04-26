use Test::More tests => 5;

BEGIN {
  use_ok( 'Bot::Cobalt::Utils', qw/
    mkpasswd passwdcmp 
  / );
}

my @alph = ( 'a' .. 'z' );
my $passwd = join '', map { $alph[rand @alph] } 1 .. 8;
my $bcrypted = mkpasswd($passwd);
ok( $bcrypted, 'bcrypt-enabled mkpasswd()' );
ok( passwdcmp($passwd, $bcrypted), 'bcrypt-enabled passwd comparison' );

my $md5crypt = mkpasswd($passwd, 'md5');
ok( $md5crypt, 'MD5 mkpasswd()' );
ok( passwdcmp($passwd, $md5crypt), 'MD5 passwd comparison' );

