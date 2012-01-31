package Cobalt::Plugin::Extras::TempConv;
our $VERSION = '1.01';

## RECEIVES AND EATS:
##  _public_cmd_tempconv  ( !tempconv )
##  _public_cmd_temp      ( !temp )

use 5.12.1;
use strict;
use warnings;

use Object::Pluggable::Constants qw/ :ALL /;
use Cobalt::Utils qw/ color /;

use constant MAX_TEMP => 100_000_000_000;

sub new { bless {}, shift }

sub Cobalt_register {
  my ($self, $core) = splice @_, 0, 2;
  $self->{core} = $core;
  $core->plugin_register( $self, 'SERVER',
    [ 
      'public_cmd_temp',
      'public_cmd_tempconv',
    ],
  );
  $core->log->info("Registered, cmds: temp tempconv");
  return PLUGIN_EAT_NONE
}

sub Cobalt_unregister {
  my ($self, $core) = splice @_, 0, 2;
  $core->log->info("Unregistering");
  return PLUGIN_EAT_NONE
}

## !temp(conv):
sub Bot_public_cmd_tempconv { Bot_public_cmd_temp(@_) }
sub Bot_public_cmd_temp {
  my ($self, $core) = splice @_, 0, 2;
  my $context = ${ $_[0] };  my $msg = ${ $_[1] };
  $self->respond($context, $msg);
  return PLUGIN_EAT_ALL
}

## Command handler:
sub respond {
  my ($self, $context, $msg) = @_;
  my $core = $self->{core};

  my $str = shift @{ $msg->{message_array} } || '';
  my ($temp, $type) = $str =~ /(-?\d+\.?\d*)?(\w)?/;
  $temp = 0   unless $temp;
  $temp = MAX_TEMP if $temp > MAX_TEMP;
  $type = 'F' unless $type;
  my ($f, $k, $c) = (0)x3;
  given (uc $type) {
    ($f, $k, $c) = ( $temp, _f2k($temp), _f2c($temp) ) when 'F';
    ($f, $k, $c) = ( _c2f($temp), _c2k($temp), $temp ) when 'C';
    ($f, $k, $c) = ( _k2f($temp), $temp, _k2c($temp) ) when 'K';
  }
  $_ = sprintf("%.2f", $_) for ($f, $k, $c);
  my $resp = color( 'bold', "(${f}F)" )
             . " == " .
             color( 'bold', "(${c}C)" )
             . " == " .
             color( 'bold', "(${k}K)" );
  my $channel = $msg->{channel};
  $core->send_event( 'send_message', $context, $channel, $resp );
}

## Conversion functions:
sub _f2c {  (shift(@_) - 32    ) * (5/9)  }
sub _f2k {  (shift(@_) + 459.67) * (5/9)  }

sub _c2f {  shift(@_) * (9/5) + 32  }
sub _c2k {  shift(@_) + 273.15      }

sub _k2f {  shift(@_) * (9/5) - 459.67  }
sub _k2c {  shift(@_) - 273.15          }

1;
