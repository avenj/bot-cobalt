package Cobalt::Serializer;
our $VERSION = '0.10';

use 5.12.1;
use strict;
use warnings;
use Carp;

use Fcntl qw/:flock/;

use constant Modules => {
  YAML   => 'YAML::Syck',
  YAMLXS => 'YAML::XS',

  JSON   => 'JSON',
};

sub new {
  ## my $serializer = Cobalt::Serializer->new( %opts )
  ## Serialize to YAML using YAML::Syck:
  ## ->new()
  ## -or-
  ## ->new( Format => 'JSON' )   ## --> to JSON
  ## -or-
  ## ->new( Format => 'YAMLXS' ) ## --> to YAML1.1
  ##
  ## Specify something with a 'log' method:
  ## ->new( Logger => $core );
  ## ->new( Logger => $core, LogLevel => 'emerg' );
  my $self = {};
  my $class = shift;
  bless $self, $class;
  my %args = @_;

  if ($args{Logger}) {
    my $logger = $args{Logger};
    unless (ref $logger && $logger->can('log') ) {
      carp "'Logger' specified but no log method found";
    } else { 
      $self->{logger} = $logger; 
      $self->{LogLevel} = $args{LogLevel} ? $args{LogLevel} : 'emerg';
    }
  }

  $self->{Format} = $args{Format} ? uc($args{Format}) : 'YAML' ;

  unless ($self->{Format} ~~ [ keys Modules ]) {
    croak "unknown format $self->{Format} specified";
  }

  unless ($self->_check_if_avail($self->{Format}) ) {
    croak "format $self->{Format} not available";
  }

  return $self;
}

sub freeze {
  ## ->freeze($ref)
  ## serialize arbitrary data structure
  my ($self, $ref) = @_;
  return unless defined $ref;
  ## _dump_yaml _dump_yamlxs etc
  my $method = lc( $self->{Format} );
  $method = "_dump_".$method;
  my $frozen = $self->$method($ref);
  return $frozen;
}

sub thaw {
  ## ->thaw($ref)
  ## deserialize data in specified Format
  my ($self, $data) = @_;
  return unless defined $data;
  my $method = lc( $self->{Format} );
  $method = "_load_".$method;
  my $thawed = $self->$method($data);
  return $thawed;
}

sub writefile {
  my ($self, $path, $ref) = @_;
  ## $serializer->writefile($path, $ref);
  ## serialize arbitrary data and write it to disk
  if      (!$path) {
    $self->_log("writefile called without path argument");
    return
  } elsif (!defined $ref) {
    $self->_log("writefile called with nothing to write");
    return
  }
  my $frozen = $self->freeze($ref);
  $self->_write_serialized($path, $frozen); 
}

sub readfile {
  my ($self, $path) = @_;
  ## my $ref = $serializer->readfile($path)
  ## thaw a file into data structure
  if (!$path) {
    $self->_log("readfile called without path argument");
    return
  } elsif (!-r $path || -d $path ) {
    $self->_log("readfile called on unreadable file $path");
    return
  }
  my $data = $self->_read_serialized($path);
  my $thawed = $self->thaw($data);
  return $thawed;
}


## Internals

sub _log {
  my ($self, $message) = @_;
  my $level = $self->{LogLevel} // 'emerg';
  unless ($self->{logger} && $self->{logger}->log->can($level) ) {
    carp "$message\n";
  } else {
    $self->{logger}->log->$level($message);
  }
}


sub _check_if_avail {
  my ($self, $type) = @_;
  ## see if we have this serialization method available to us
  return unless exists Modules->{$type};
  my $module = Modules->{$type};
  eval "require $module";
  if ($@) {
    $self->_log("$type specified but $module not available");
    return 0
  } else {
    return 1
  }
}


sub _dump_yaml {
  my ($self, $data) = @_;
  ## turn a data structure into YAML1.0
  require YAML::Syck;
  no warnings;
  $YAML::Syck::ImplicitTyping = 1;
  $YAML::Syck::ImplicitUnicode = 1;
  use warnings;
  my $yaml = YAML::Syck::Dump($data);
  return $yaml;
}

sub _load_yaml {
  my ($self, $yaml) = @_;
  ## turn YAML1.0 into a data structure
  require YAML::Syck;
  no warnings;
  $YAML::Syck::ImplicitTyping = 1;
  $YAML::Syck::ImplicitUnicode = 1;
  use warnings;
  my $data = YAML::Syck::Load($yaml);
  return $data;
}

sub _dump_yamlxs {
  my ($self, $data) = @_;
  ## turn data into YAML1.1
  require YAML::XS;
  my $yaml = YAML::XS::Dump($data);
  utf8::decode($yaml);
  return $yaml;
}

sub _load_yamlxs {
  my ($self, $yaml) = @_;
  require YAML::XS;
  utf8::encode($yaml);
  my $data = YAML::XS::Load($yaml);
  return $data;
}

sub _dump_json {
  my ($self, $data) = @_;
  require JSON;
  my $json = JSON::encode_json($data);
  return $json;
}

sub _load_json {
  my ($self, $json) = @_;
  require JSON;
  my $data = JSON::decode_json($json);
  return $data;
}


sub _read_serialized {
  my ($self, $path) = @_;
  return unless $path;
  if (-d $path || ! -e $path) {
    $self->_log("file not readable: $path");
    return
  }

  open(my $in_fh, '<', $path)
    or ($self->_log("open failed for $path: $!") and return);
  flock($in_fh, LOCK_SH)
    or ($self->_log("LOCK_SH failed for $path: $!") and return);

  my $data = join('', <$in_fh>);

  flock($in_fh, LOCK_UN)
    or $self->_log("LOCK_UN failed for $path: $!");
  close($in_fh)
    or $self->_log("close failed for $path: $!");

  return $data;
}

sub _write_serialized {
  my ($self, $path, $data) = @_;
  return unless $path and defined $data;

  open(my $out_fh, '>>', $path)
    or ($self->_log("open failed for $path: $!") and return);
  flock($out_fh, LOCK_EX | LOCK_NB)
    or ($self->_log("LOCK_EX failed for $path: $!") and return);

  seek($out_fh, 0, 0)
    or ($self->_log("seek failed for $path: $!") and return);
  truncate($out_fh, 0)
    or ($self->_log("truncate failed for $path") and return);

  print $out_fh $data;

  close($out_fh)
    or $self->_log("close failed for $path: $!");

  return 1
}

1;
