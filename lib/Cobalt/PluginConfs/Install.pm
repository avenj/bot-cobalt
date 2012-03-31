package Cobalt::PluginConfs::Install;
our $VERSION = '0.001';

## Install plugin confs from this directory.
use strict;
use warnings;
use Carp;

use File::Spec;

sub new { bless {}, shift }

sub dir {
  my ($self, $setdir) = @_;
  my $current = ($setdir //= $self->{DIR}) // __FILE__;
  my ($vol, $dir) = File::Spec->splitpath($current);
  return $self->{DIR} = File::Spec->catpath($vol, $dir);
}

sub path {
  my ($self, $cfgname) = @_;
  my $fullpath = File::Spec->catpath( $self->dir, $cfgname );
  return unless -e $fullpath;
  return $fullpath
}

sub read_array {
  my ($self, $cfgname) = @_;
  my $path = $self->path($cfgname) || return;
  open my $fh, '<', $path or croak "open failed: $!";
  my @conf = <$fh>;
  close $fh;
  return \@conf;
}

sub write_array {
  my ($self, $ref, $path) = @_;
  return unless $path;
  return unless ref $ref eq 'ARRAY';
  open my $outfh, '>', $path or croak "open failed: $!";
  print $outfh @{$ref};
  close $outfh;
  return 1
}

sub inst_conf {
  my ($self, $etcdir, $cfgname) = @_;
  return unless $etcdir and $cfgname;
  
  my $contents = $self->read_array($cfgname);

  ## write to specified etcdir (usually our ->etc/plugins)
  ## write to .new instead if it exists
  
  my $dest = File::Spec->catfile($etcdir, $cfgname);
  
  return unless -e $etcdir;
  
  $dest = $dest .".new" if -e $dest;

  return $self->write_array($contents, $dest)
}

1;
__END__

=pod


=cut
