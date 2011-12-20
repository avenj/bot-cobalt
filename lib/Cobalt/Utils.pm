package Cobalt::Utils;

our $VERSION = '0.10';

use 5.12.1;
use strict;
use warnings;

use Crypt::Eksblowfish::Bcrypt;

require Exporter;
our @ISA = qw(Exporter);

our @EXPORT = qw/
  timestr_to_secs
  mkpasswd
  passwdcmp
/;

sub timestr_to_secs {
  ## turn something like 2h3m30s into seconds
  my $timestr = shift;
  my($hrs,$mins,$secs,$total);
  ## FIXME add days ?
  if ($timestr =~ m/(\d+)h/)
    { $hrs = $1; }
  if ($timestr =~ m/(\d+)m/)
    { $mins = $1; }
  if ($timestr =~ m/(\d+)s/)
    { $secs = $1; }
  $total = $secs;
  $total += (int $mins * 60) if $mins;
  $total += (int $hrs * 3600) if $hrs;
  return int($total)
}

sub passwdcmp {
  my $pwd   = shift || return;
  my $crypt = shift || return;

  if ( index($crypt, '$2a$') == 0 ) ## bcrypted
  {
    return 0 unless $crypt eq
      Crypt::Eksblowfish::Bcrypt::bcrypt($pwd, $crypt);
  }
  else  ## some crypt() method, hopefully we have it!
  {
    return 0 unless $crypt eq crypt($pwd, $crypt);
  }

  return $crypt
}

sub mkpasswd {
  my ($pwd, $type, $cost) = @_;

  $type = 'bcrypt' unless $type;

  # generate a new passwd based on $type

  # a default (randomized) salt ..
  # we can use it for MD5 or build on it for SHA
  my @p = ('a' .. 'z', 'A' .. 'Z', 0 .. 9, '_',);
  my $salt = join '', map { $p[rand@p] } 1 .. 8;

  given ($type)
  {
    when (/sha-?512/i) {  ## SHA-512: glibc-2.7+
        ## unfortunately mostly only glibc has support in crypt()
        ## SHA has variable length salts (up to 16)
        ## varied salt lengths can (maybe) slow down attacks
        ## (so says Drepper, anyway)
        $salt .= $p[rand@p] for 1 .. rand 8;
        $salt = '$6$'.$salt.'$';
    }

    when (/sha-?256/i) {  ## SHA-256: glibc-2.7+
        $salt .= $p[rand@p] for 1 .. rand 8;
        $salt = '$5$'.$salt.'$';
    }

    when (/^bcrypt$/i) {  ## Bcrypt via Crypt::Eksblowfish
        ## blowfish w/ cost factor
        ## cost value is configurable, but 08 is a good choice.
        ## has to be a two digit power of 2. pad with 0 as needed
        $cost //= '08';
        ## bcrypt expects 16 octets of salt:
        $salt = join('', map { chr(int(rand(256))) } 1 .. 16);
        ## ...base64-encoded via bcrypt's en_base64:
        $salt = Crypt::Eksblowfish::Bcrypt::en_base64( $salt );
        ## actual settings string to feed bcrypt ($2a$COST$SALT)
        $salt = join('', '$2a$', $cost, '$', $salt);
        return Crypt::Eksblowfish::Bcrypt::bcrypt($pwd, $salt)
    } 

    default {  ## defaults to MD5 -- portable, fast, but weak
        $salt = '$1$'.$salt.'$';
    }

  }

  return crypt($pwd, $salt)
}


1;

=pod

=head1 NAME

Cobalt::Utils

=head1 DESCRIPTION

Simple utility functions for Cobalt2 and plugins


=head1 FUNCTIONS


=head2 Date and time

=head3 timestr_to_secs

Converts a string such as "2h10m" into seconds.

  my $delay_s = timestr_to_secs('1h33m10s');


=head2 Password handling

=head3 mkpasswd

Simple interface for creating hashed passwords:

  ## create a bcrypted password (work cost 08)
  ## bcrypt is blowfish with a work cost factor.
  ## if hashes are stolen, they'll be slow to break
  ## see http://codahale.com/how-to-safely-store-a-password/
  my $hashed = mkpasswd($password);

  ## you can specify method options . . .
  ## here's bcrypt with a lower work cost factor.
  ## (must be a two-digit power of 2, possibly padded with 0)
  my $hashed = mkpasswd($password, 'bcrypt', '06');

  ## Available methods:
  ##  bcrypt (preferred)
  ##  SHA-256 or -512 (glibc2.7+ only)
  ##  MD5 (fast, portable, weak)
  my $sha_passwd = mkpasswd($password, 'sha512');

=head3 passwdcmp

  return passwdcmp($password, $hashed);

Returns the hash if the cleartext password is a match.
Otherwise, returns 0.

=head1 AUTHOR

Jon Portnoy (avenj)
http://www.cobaltirc.org

=cut
