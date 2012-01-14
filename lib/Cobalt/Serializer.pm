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
  ## ->new( Logger => $core, LogMethod => 'emerg' );
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
      $self->{LogMethod} = $args{LogMethod} ? $args{LogMethod} : 'emerg';
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
  ## ->thaw($data)
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
  my $level = $self->{LogMethod} // 'emerg';
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

__END__

=pod

=head1 NAME

Cobalt::Serializer - easy data serialization

=head1 SYNOPSIS

  use Cobalt::Serializer;

  ## Spawn a YAML1.0 handler:
  my $serializer = Cobalt::Serializer->new;

  ## Spawn a JSON handler
  my $serializer = Cobalt::Serializer->new( Format => 'JSON' );

  ## Spawn a YAML1.1 handler that logs to $core->log->crit:
  my $serializer = Cobalt::Serializer->new(
    Format => 'YAMLXS',
    Logger => $core,
    LogMethod => 'crit',
  );

  ## Serialize some data to our Format:
  my $ref = { Stuff => { Things => [ 'a', 'b'] } };
  my $frozen = $serializer->freeze( $ref );

  ## Turn it back into a Perl data structure:
  my $thawed = $serializer->thaw( $frozen );

  ## Serialize some $ref to a file at $path
  ## The file will be overwritten
  ## Returns false on failure
  $serializer->writefile( $path, $ref );

  ## Turn a serialized file back into a $ref
  ## Boolean false on failure
  my $ref = $serializer->readfile( $path );


=head1 DESCRIPTION

Various pieces of B<Cobalt2> need to read and write data from/to disk.

This simple OO frontend makes it trivially easy to work with a selection of 
serialization formats.

Currently supported:

=over

=item L<YAML::Syck> (YAML 1.0)

=item L<YAML::XS> (YAML1.1)

=item L<JSON>

=back


=head1 METHODS

=head2 new

  my $serializer = $serializer->new;
  my $serializer = $serializer->new( %opts );

Spawn a serializer instance.

The default is to spawn a YAML (1.0 spec) serializer with no logger.

Optionally, any combination of the following B<%opts> may be specified:

=head3 Format

Specify a serialization format.

Currently available formats are:

=over

=item *

B<YAML> - YAML1.0 via L<YAML::Syck>

=item *

B<YAMLXS> - YAML1.1 via L<YAML::XS>

=item *

B<JSON> - JSON via L<JSON::XS> or L<JSON::PP>

=back

The default is B<YAML>

=head3 Logger

By default, all user-directed output is printed via C<carp>.
There should be no output unless something goes wrong.

If you're not writing a B<Cobalt> plugin, you can likely stop reading now.

Alternately, you can log error messages via a specified object's 
interface to a logging mechanism.

B<Logger> is used to specify an object that has a C<log> attribute.

The C<log> method of the object specified is typically expected to return 
a reference to a logger's object; the logger is expected to handle a 
L</LogMethod>, 

That is to say:

  ## in a cobalt2 plugin . . . 
  ## $core provides the ->log attribute containing a Log::Handler
  my $serializer = Cobalt::Serializer->new( Logger => $core );
  ## now errors will go to $core->log->$LogMethod()
  ## (log->emerg() by default)

This is kludgy and should be fixed, as should the confusing nature of 
the log attribute vs the log() builtin.

Also see the L</LogMethod> directive.

=head3 LogMethod

When using a L</Logger>, you can specify LogMethod to change which log
method is called (typically the verbosity level to display messages at). 

  ## A slightly lower priority logger
  my $serializer = Cobalt::Serializer->new(
    Logger => $core,
    LogMethod => 'warn',
  );

Defaults to B<emerg>, a high-priority message. It's probably safe to leave 
this alone; it will work for at least L<Log::Handler> and L<Log::Log4perl>.


=head2 freeze

  my $frozen = $serializer->freeze($ref);

Turn the specified reference I<$ref> into the configured B<Format>.

Upon success returns a scalar containing the serialized format, suitable for 
saving to disk, transmission, etc.


=head2 thaw

  my $ref = $serializer->thaw($data);

Turn the specified serialized data (stored in a scalar) back into a Perl 
data structure.

(Try L<Data::Dumper> if you're not sure what your data actually looks like.)



=head2 writefile

  print "failed!" unless $serializer->writefile($path, $ref);

L</freeze> the specified C<$ref> and write the serialized data to C<$path>

Will fail with errors if $path is not writable for whatever reason; finding 
out if your destination path is writable is up to you.

Uses B<flock> to lock the file for writing; the call is non-blocking, therefore 
writing to an already-locked file will fail with errors rather than waiting.

Will be false on apparent failure, probably with some carping.


=head2 readfile

  my $ref = $serializer->readfile($path);

Read the serialized file at the specified C<$path> (if possible) and 
L</thaw> the data structures back into a reference.

Will fail with errors if $path cannot be found or is unreadable.

If the file is malformed or not of the expected B<Format> the parser will 
whine at you.


=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

L<http://www.cobaltirc.org>


=cut
