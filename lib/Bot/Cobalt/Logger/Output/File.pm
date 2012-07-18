package Bot::Cobalt::Logger::Output::File;

use 5.12.1;
use strictures 1;

use Carp;

use Fcntl qw/:DEFAULT :flock/;

sub PATH   () { 0 }
sub HANDLE () { 1 }
sub MODE   () { 2 }
sub PERMS  () { 3 }

sub new {
  my $class = shift;

  my $self = [ 
    '',     ## PATH
    undef,  ## HANDLE
    undef,  ## MODE
    undef,  ## PERMS
  ];

  bless $self, $class;
  
  my %args = @_;
  $args{lc $_} = delete $args{$_} for keys %args;

  confess "new() requires a 'file' argument"
    unless defined $args{file};

  $self->file( $args{file} );

  $self->mode( $args{mode} )
    if defined $args{mode};

  $self->perms( $args{perms} )
    if defined $args{perms};

  ## Try to open/create file when object is constructed
  $self->_open or croak "Could not open specified file ".$args{file};
  $self->_close;

  $self
}

sub file {
  my ($self, $file) = @_;

  if (defined $file) {
    $self->_close if $self->_is_open;
    
    $self->[PATH] = $file
  }

  $self->[PATH]
}

sub mode {
  my ($self, $mode) = @_;
  
  return $self->[MODE] = $mode if defined $mode;
  
  $self->[MODE] //= O_WRONLY | O_APPEND | O_CREAT
}

sub perms {
  my ($self, $perms) = @_;
  
  return $self->[PERMS] = $perms if defined $perms;
  
  $self->[PERMS] //= 0666
}

sub _open {
  my ($self) = @_;

  return if $self->_is_open;

  sysopen(my $fh, $self->file, $self->mode, $self->perms)
    or warn(
      "Log file could not be opened: ", 
      join ' ', $self->file, $!
    ) and return;
  
  binmode $fh, ':utf8';
## Current code is closing / reopening after each write, so no autoflush.
## It would be nice to implement persistent open, but the catch is
## that we may end up writing to an undefined location if the file is
## deleted or moved. Win32 (and VMS, but 'eh') has no fucking clue about 
## inodes, so we need some mechanism for detecting a handle is not the 
## same path on at least Win32 before we can maintain persistently-open
## log files properly.
#  $fh->autoflush;

  $self->[HANDLE] = $fh
}

sub _close {
  my ($self) = @_;
  
  return unless $self->_is_open;
  
  close $self->[HANDLE];

  $self->[HANDLE] = undef;

  1
}

sub _is_open {
  my ($self) = @_;
  
  $self->[HANDLE]
}

sub _write {
  my ($self, $str) = @_;
  
  $self->_open;

  ## FIXME if flock fails, buffer and try next _write up to X items ?
  ## FIXME maybe we should just fail silently (and document same)?
  flock($self->[HANDLE], LOCK_EX)
    or warn "flock failure for ".$self->file
    and $self->_close and return;

  print { $self->[HANDLE] } $str;

  flock($self->[HANDLE], LOCK_UN);
  
  $self->_close;

  1
}


1;
__END__

=pod

=head1 NAME

Bot::Cobalt::Logger::Output::File - Bot::Cobalt::Logger file output

=head1 SYNOPSIS

  $output_obj->add(
    'Output::File' => {
      file => $path_to_log,
      
      ## Optional:
      # perms() defaults to 0666 and is modified by umask:
      perms => 0666,
      # mode() should be Fcntl constants suitable for sysopen()
      # defaults to O_WRONLY | O_APPEND | O_CREAT
      mode => O_WRONLY | O_APPEND | O_CREAT,
    },
  );

See L<Bot::Cobalt::Logger::Output>.

=head1 DESCRIPTION

This is a L<Bot::Cobalt::Logger::Output> writer for logging messages to a 
file.

The constructor requires a B<file> specification (the path to the actual 
file to write).

Attempts to lock the file for every write.

Expects UTF-8.

=head2 file

Retrieve or set the current file path.

=head2 perms

Retrieve or set the permissions passed to C<sysopen()>.

This should be an octal mode and will be modified by the current 
C<umask>. 

Defaults to 0666

=head2 mode

Retrieve or set the open mode passed to C<sysopen()>.

See L<Fcntl>.

Defaults to O_WRONLY | O_APPEND | O_CREAT

=head1 AUTHOR

Jon Portnoy <avenj@cobaltirc.org>

=cut
