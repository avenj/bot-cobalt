package Cobalt::Serializer;
our $VERSION = '0.18';

use 5.12.1;
use strict;
use warnings;
use Carp;

use Fcntl qw/:flock/;

my $Modules = {
  YAML   => 'YAML::Syck',
  YAMLXS => 'YAML::XS',

  JSON   => 'JSON',
  
  XML    => 'XML::Dumper',
};

sub new {
  ## my $serializer = Cobalt::Serializer->new( %opts )
  ## Serialize to YAML using YAML::XS:
  ## ->new()
  ## - or -
  ## ->new($format)
  ## ->new('JSON')  # f.ex
  ## - or -
  ## ->new( Format => 'JSON' )   ## --> to JSON
  ## - or -
  ## ->new( Format => 'YAML' ) ## --> to YAML1.0
  ## - and / or -
  ## Specify something with a LogMethod method, default 'error':
  ## ->new( Logger => $core->log );
  ## ->new( Logger => $core->log, LogMethod => 'crit' );
  my $self = {};
  my $class = shift;
  bless $self, $class;
  my %args;
  if (@_ > 1) {
     %args = @_;
  } else {
    $args{Format} = shift;
  }

  if ($args{Logger}) {
    $self->{LogMethod} = $args{LogMethod} ? $args{LogMethod} : 'error';
    my $logmethod = $self->{LogMethod};
    my $logger = $args{Logger};
    unless (ref $logger && $logger->can($logmethod) ) {
      carp "'Logger' specified but log method $logmethod not found";
    } else { 
      $self->{logger} = $logger; 
    }
  }

  $self->{Format} = $args{Format} ? uc($args{Format}) : 'YAMLXS' ;

  unless ($self->{Format} ~~ [ keys %$Modules ]) {
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
  my ($self, $path, $ref, $opts) = @_;
  ## $serializer->writefile($path, $ref [, { Opts });
  ## serialize arbitrary data and write it to disk
  if      (!$path) {
    $self->_log("writefile called without path argument");
    return
  } elsif (!defined $ref) {
    $self->_log("writefile called with nothing to write");
    return
  }
  my $frozen = $self->freeze($ref);
  $self->_write_serialized($path, $frozen, $opts); 
}

sub readfile {
  my ($self, $path, $opts) = @_;
  ## my $ref = $serializer->readfile($path)
  ## thaw a file into data structure
  if (!$path) {
    $self->_log("readfile called without path argument");
    return
  } elsif (!-r $path || -d $path ) {
    $self->_log("readfile called on unreadable file $path");
    return
  }
  my $data = $self->_read_serialized($path, $opts);
  my $thawed = $self->thaw($data);
  return $thawed;
}

sub version {
  my ($self) = @_;
  my $module = $Modules->{ $self->{Format} };
  eval "require $module";
  return($module, $module->VERSION);
}

## Internals

sub _log {
  my ($self, $message) = @_;
  my $method = $self->{LogMethod};
  unless ($self->{logger} && $self->{logger}->can($method) ) {
    carp "$message\n";
  } else {
    $self->{logger}->$method($message);
  }
}


sub _check_if_avail {
  my ($self, $type) = @_;
  ## see if we have this serialization method available to us
  return unless exists $Modules->{$type};
  my $module = $Modules->{$type};
  eval "require $module";
  if ($@) {
    $self->_log("$type specified but $module not available");
    return 0
  } else {
    return 1
  }
}

sub _dump_xml {
  my ($self, $data) = @_;
  require XML::Dumper;
  my $xml = XML::Dumper->new()->pl2xml($data);
  return $xml
}

sub _load_xml {
  my ($self, $xml) = @_;
  require XML::Dumper;
  my $data = XML::Dumper->new()->xml2pl($xml);
  return $data
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
  return $yaml;
}

sub _load_yamlxs {
  my ($self, $yaml) = @_;
  require YAML::XS;
  my $data = YAML::XS::Load($yaml);
  return $data;
}

sub _dump_json {
  my ($self, $data) = @_;
  require JSON;
  my $jsify = JSON->new->allow_nonref;
  $jsify->utf8(1);
  my $json = $jsify->encode($data);
  return $json;
}

sub _load_json {
  my ($self, $json) = @_;
  require JSON;
  my $jsify = JSON->new->allow_nonref;
  $jsify->utf8(1);
  my $data = $jsify->decode($json);
  return $data;
}


sub _read_serialized {
  my ($self, $path, $opts) = @_;
  return unless $path;
  if (-d $path || ! -e $path) {
    $self->_log("file not readable: $path");
    return
  }

  my $lock = 1;
  if (defined $opts && ref $opts eq 'HASH') {
    $lock = $opts->{Locking} if defined $opts->{Locking};
  }

  open(my $in_fh, '<', $path)
    or ($self->_log("open failed for $path: $!") and return);
  
  if ($lock) {
    flock($in_fh, LOCK_SH)  # blocking call
    or ($self->_log("LOCK_SH failed for $path: $!") and return);
   }

  my $data = join('', <$in_fh>);

  if ($lock) {
    flock($in_fh, LOCK_UN)
    or $self->_log("LOCK_UN failed for $path: $!");
  }

  close($in_fh)
    or $self->_log("close failed for $path: $!");

  utf8::encode($data);

  return $data;
}

sub _write_serialized {
  my ($self, $path, $data, $opts) = @_;
  return unless $path and defined $data;

  my $lock = 1;
  if (defined $opts && ref $opts eq 'HASH') {
    $lock = $opts->{Locking} if defined $opts->{Locking};
  }
  
  utf8::decode($data);

  open(my $out_fh, '>>', $path)
    or ($self->_log("open failed for $path: $!") and return);

  if ($lock) {
    flock($out_fh, LOCK_EX | LOCK_NB)
    or ($self->_log("LOCK_EX failed for $path: $!") and return);
  }

  seek($out_fh, 0, 0)
    or ($self->_log("seek failed for $path: $!") and return);
  truncate($out_fh, 0)
    or ($self->_log("truncate failed for $path") and return);

  print $out_fh $data;

  if ($lock) {
    flock($out_fh, LOCK_UN)
    or $self->_log("LOCK_UN failed for $path: $!");
  }

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
  my $serializer = Cobalt::Serializer->new('JSON');
  ## ...same as:
  my $serializer = Cobalt::Serializer->new( Format => 'JSON' );

  ## Spawn a YAML1.1 handler that logs to $core->log->crit:
  my $serializer = Cobalt::Serializer->new(
    Format => 'YAMLXS',
    Logger => $core->log,
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

  ## Do the same thing, but without locking
  $serializer->writefile( $path, $ref, { Locking => 0 } );

  ## Turn a serialized file back into a $ref
  ## Boolean false on failure
  my $ref = $serializer->readfile( $path );

  ## Do the same thing, but without locking
  my $ref = $serializer->readfile( $path, { Locking => 0 } );


=head1 DESCRIPTION

Various pieces of B<Cobalt2> need to read and write data from/to disk.

This simple OO frontend makes it trivially easy to work with a selection of 
serialization formats, automatically enabling Unicode encode/decode and 
optionally providing the ability to read/write files directly.


=head1 METHODS

=head2 new

  my $serializer = Cobalt::Serializer->new;
  my $serializer = Cobalt::Serializer->new( $format );
  my $serializer = Cobalt::Serializer->new( %opts );

Spawn a serializer instance. Will croak if you are missing the relevant 
serializer module; see L</Format>, below.

The default is to spawn a B<YAML::XS> (YAML1.1) serializer with error 
logging to C<carp>.

You can spawn an instance using a different Format by passing a simple 
scalar argument:

  $handle_syck = Cobalt::Serializer->new('YAML');
  $handle_yaml = Cobalt::Serializer->new('YAMLXS');
  $handle_json = Cobalt::Serializer->new('JSON');

Alternately, any combination of the following B<%opts> may be specified:

  $serializer = Cobalt::Serializer->new(
    Format =>
    Logger =>
    LogMethod =>
  );

See below for descriptions.

=head3 Format

Specify an input and output serialization format.

Currently available formats are:

=over

=item *

B<YAML> - YAML1.0 via L<YAML::Syck>

=item *

B<YAMLXS> - YAML1.1 via L<YAML::XS>  I<(default)>

=item *

B<JSON> - JSON via L<JSON::XS> or L<JSON::PP>

=item *

B<XML> - XML via L<XML::Dumper> I<(glacially slow)>

=back

The default is YAML I<(YAML Ain't Markup Language)> 1.1 (B<YAMLXS>)

YAML is very powerful, and the appearance of the output makes it easy for 
humans to read and edit.

JSON is a more simplistic format, often more suited for network transmission 
and talking to other networked apps. JSON is B<a lot faster> than YAML
(assuming L<JSON::XS> is available).
It also has the benefit of being included in the Perl core as of perl-5.14.

=head3 Logger

By default, all error output is delivered via C<carp>.

If you're not writing a B<Cobalt> plugin, you can likely stop reading right 
there; that'll do for the general case, and your module or application can 
worry about STDERR.

However, if you'd like, you can log error messages via a specified object's 
interface to a logging mechanism.

B<Logger> is used to specify an object that has a logging method of some 
sort.

That is to say:

  ## In a typical cobalt2 plugin . . . 
  ## assumes $core has already been set to the Cobalt core object
  ## $core provides the ->log attribute containing a Log::Handler:
  my $serializer = Cobalt::Serializer->new( Logger => $core->log );
  ## now errors will go to $core->log->$LogMethod()
  ## (log->error() by default)

  ##
  ## Meanwhile, in a stand-alone app or module . . .
  ##
  sub configure_logger {
    . . .
    ## Pick your poison ... Set up whatever logger you like
    ## Log::Handler, Log::Log4perl, Log::Log4perl::Tiny, Log::Tiny, 
    ## perhaps a custom job, whatever ...
    ## The only real requirement is that it have an OO interface
  }

  sub do_some_work {
    ## Typically, a complete logging module provides a mechanism for 
    ## easy retrieval of the log obj, such as get_logger
    ## (otherwise keeping track of it is up to you)
    my $log_obj = Log::Log4perl->get_logger('My.Logger');

    my $serializer = Cobalt::Serializer->new( Logger => $log_obj );
    ## Now errors are logged as: $log_obj->error($err)
    . . .
  }


Also see the L</LogMethod> directive.

=head3 LogMethod

When using a L</Logger>, you can specify LogMethod to change which log
method is called (typically the priority/verbosity level). 

  ## A slightly lower priority logger:
  my $serializer = Cobalt::Serializer->new(
    Logger => $core,
    LogMethod => 'warn',
  );

  ## A module using a Log::Tiny logger:
  my $serializer = Cobalt::Serializer->new(
    Logger => $self->{logger_object},
    ## Log::Tiny expects uppercase log methods:
    LogMethod => 'ERROR',
  );


Defaults to B<error>, which should work for at least L<Log::Handler>, 
L<Log::Log4perl>, and L<Log::Log4perl::Tiny>.


=head2 freeze

Turn the specified reference I<$ref> into the configured B<Format>.

  my $frozen = $serializer->freeze($ref);


Upon success returns a scalar containing the serialized format, suitable for 
saving to disk, transmission, etc.


=head2 thaw

Turn the specified serialized data (stored in a scalar) back into a Perl 
data structure.

  my $ref = $serializer->thaw($data);


(Try L<Data::Dumper> if you're not sure what your data actually looks like.)



=head2 writefile

L</freeze> the specified C<$ref> and write the serialized data to C<$path>

  print "failed!" unless $serializer->writefile($path, $ref);

Will fail with errors if $path is not writable for whatever reason; finding 
out if your destination path is writable is up to you.

Locks the file by default. You can turn this behavior off:

  $serializer->writefile($path, $ref, { Locking => 0 });

B<IMPORTANT:>
Uses B<flock> to lock the file for writing; the call is non-blocking, therefore 
writing to an already-locked file will fail with errors rather than waiting.

Will be false on apparent failure, probably with some carping.


=head2 readfile

Read the serialized file at the specified C<$path> (if possible) and 
L</thaw> the data structures back into a reference.

  my $ref = $serializer->readfile($path);

By default, attempts to gain a shared (LOCK_SH) lock on the file.
You can turn this behavior off:

  $serializer->readfile($path, { Locking => 0 });

B<IMPORTANT:>
This is not a non-blocking lock. C<readfile> will block until a lock is 
gained (to prevent data structures from "running dry" in between writes).
This is the opposite of what L</writefile> does, the general concept being 
that preserving the data existing on disk takes priority.
Turn off B<Locking> if this is not the behavior you want.

Will fail with errors if $path cannot be found or is unreadable.

If the file is malformed or not of the expected L</Format> the parser will 
whine at you.


=head2 version

Obtains the backend serializer and its VERSION for the current instance.

  my ($module, $modvers) = $serializer->version;

Returns a list of two values: the module name and its version.

  ## via Devel::REPL:
  $ Cobalt::Serializer->new->version
  $VAR1 = 'YAML::Syck';
  $VAR2 = 1.19;


=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

L<http://www.cobaltirc.org>


=head1 SEE ALSO

=over

=item *

L<YAML::Syck> -- YAML1.0: L<http://yaml.org/spec/1.0/>

=item *

L<YAML::XS> -- YAML1.1: L<http://yaml.org/spec/1.1/>

=item *

L<JSON>, L<JSON::XS> -- JSON: L<http://www.json.org/>

=item *

L<XML::Dumper>

=back


=cut
