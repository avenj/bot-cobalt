#!/usr/bin/env perl
use strict;
use warnings;
use Module::Build;

my $class = Module::Build->subclass(
  class => 'Bot::Cobalt::Builder',
  code => q{

    sub ACTION_release {
      my $self = shift;
      $self->dispatch('versionify');
      $self->dispatch('wikidocs');
      $self->dispatch('dist');
    }

    sub ACTION_wikidocs {
      my $self = shift;
      my $base = $self->base_dir;
      my $remote = $ENV{DOC_UPLOAD} || die "Need ENV DOC_UPLOAD";
      chdir($base."/tools/release/docs");
      $self->do_system(qw{"./pod2doku"});
      $self->do_system(
        'rsync',
        '-rv',
        '--stats',
        '--progress',
        'wikidoc/',
        $remote.
         ':public_html/docs/wiki/data/pages/bots/cobalt/docs',
      );
      chdir($base);
    }
    
    sub ACTION_versionify {
      my $self = shift;
      my $base = $self->base_dir;
      my $vers = $self->dist_version;
      ++$|;
      print "Versionifying ";
      require File::Find;
      File::Find->import('find');
      my $x;
      find(sub {
          if ($_ =~ /\.pm(.in)?$/) {
            my $path = $File::Find::name;
            open my $fh, '<', $path
              or die "open: $path $!";
            my @thisf = readline($fh);
            close $fh;
            
            my $package_l = shift @thisf || return;
            my $pkg;
            unless (($pkg) = $package_l =~ /^package\s+(\S+)$/) {
              warn "\nSkipping, no package: $path\n";
              return
            }
            
            ++$x;
            print ". ";
            
            my $v_line = "our \$VERSION = '$vers';\n";
            
            if ($thisf[0] =~ /VERSION/) {
              $thisf[0] = $v_line
            } else {
              unshift(@thisf, $v_line)
            }
            
            unshift(@thisf, $package_l);
            
            open $fh, '>', $path
              or die "open: $path $!";
            print $fh @thisf;
            close $fh;
          }
        },
        $base."/lib", $base."/tools"
      );
      print "\n$x modules\n";
    }

  },
);

my $build = $class->new(
  module_name => 'Bot::Cobalt',
  dist_abstract => 'Pluggable IRC bot (cobalt2)',
  dist_author => 'Jon Portnoy <avenj@cobaltirc.org>',
  license => 'perl',
  
  create_readme => 1,

  recursive_test_files => 1,

  ## A passthru-to-build makefile:
  create_makefile_pl => 'small',
  
  PL_files => {
    'lib/Bot/Cobalt/Lang.pm.PL' => 'lib/Bot/Cobalt/Lang.pm',
    'bin/cobalt2-installer.PL' => 'bin/cobalt2-installer',
  },
  
  configure_requires => {
    'Module::Build' => '0.38',
  },
  
  build_requires => {
    'Test::More' => 0,
    'Test::Cmd'  => 0,

    'Data::Dumper'   => 0,
    'File::Find'     => 0,
    'File::Spec'     => 0,
    'File::Temp'     => 0,
    'Fcntl' => 0,
  },

  requires => {
   ### Core set ###
      'perl' => '5.10.1',
      'Carp' => 0,
      'Cwd'  => 0,
      'Exporter' => 0,
      'Fcntl'    => 0,
      'Data::Dumper'   => 0,
      'DB_File'        => 0,
      'Digest::SHA'    => 0,
      'File::Find'     => 0,
      'File::Spec'     => 0,
      'File::Basename' => 0,
      'File::Path'     => '2.00',
      'Getopt::Long'   => 0,
      'IO::File'       => 0,
      'IO::Handle'     => 0,
      'List::Util'     => 0,
      'POSIX'          => 0,
      'Scalar::Util'   => 0,
      'Storable'       => 0,
      'Time::HiRes'    => 0,
      
      'strictures' => '1',
      
   ### Cobalt set ###
     # Crypt
      'App::bmkpasswd' => 0,

     # HTTP
      'HTTP::Request'  => 0,
      'HTTP::Response' => 0,
      'URI::Escape'    => 0,

     # Utils
      'DateTime'      => 0,
      'IRC::Utils'    => '0.12',
      'Term::ReadKey' => 0,

     # Serialization
      'JSON'        => '2.00',
      'YAML::XS'    => '0.34',

     # Logging
      'Log::Handler' => '0.71',

     # Moo + related
      'Moo'         => '0.091',
      'MooX::Types::MooseLike' => '0.03',
      
     # Network
      'Net::IP::Minimal' => '0.02',

     # POE::
      'POE'            => '1.311',

      'POE::Component::Client::DNS'  => 0,
      'POE::Component::Client::HTTP' => '0.945',
      'POE::Component::Client::Keepalive' => '0',
      'POE::Component::IRC::State'  => '6.78',
      'POE::Component::Syndicator'  => '0.06',
      'Object::Pluggable'           => '1.27',

     # Process mgmt
      'Proc::PID::File' => '1.26',
  },

  recommends => {
    ### POE::
      'POE::Component::SSLify' => '1.006',

    ### Utils / misc
      # terminal interaction
      'Term::ReadLine::Perl' => 0,

    ### Storage / serialization
      'JSON::XS'    => 0,
      'YAML::Syck'  => '1.18',

    ### Release tools, commented for now
#      'Dir::Self' => 0,
     # templating (cpodconv/release tools)
#      'Template' => 0,
     # POD conversion
#      'Pod::Select' => 0,
#      'Pod::Find'   => 0,
#      'Pod::Simple::Wiki' => 0,
  },
);

$build->add_to_cleanup("lib/Bot/Cobalt/Lang.pm");
$build->add_to_cleanup("bin/cobalt2-installer");
$build->create_build_script;

__END__
Bacon.
