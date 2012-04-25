#!/usr/bin/env perl
use strict;
use warnings;
use Module::Build;

my $class = Module::Build->subclass(
  class => 'Cobalt::Builder',
  code => q{

    sub ACTION_release {
      my $self = shift;
      $self->dispatch('wikidocs');
      ## FIXME target to pod2textify doc/ ?
      ## FIXME dispatch dist ?
    }

    sub ACTION_wikidocs {
      ## FIXME doesn't grab README / INSTALL PODs
      ## move them to Cobalt::Manual::
      ## create top-level plaintext README referencing online POD
      ## FIXME stick cobalt2-installer POD somewhere?
      my $self = shift;
      my $base = $self->base_dir;
      my $remote = 'eris.cobaltirc.org';
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

  },
);

my $build = $class->new(
  dist_name => 'Cobalt',
  dist_abstract => 'Pluggable IRC bot (cobalt2)',
  dist_author => 'Jon Portnoy <avenj@cobaltirc.org>',
  dist_version_from => 'lib/Cobalt/Core.pm',
  license => 'perl',

  recursive_test_files => 1,

  ## A passthru-to-build makefile:
  create_makefile_pl => 'small',
  
  PL_files => {
    'lib/Cobalt/Lang.pm.PL' => 'lib/Cobalt/Lang.pm',
    'bin/cobalt2-installer.PL' => 'bin/cobalt2-installer',
  },

  requires => {
   ### Core set ###
      'perl' => '5.10.1',
      'Carp' => 0,
      'Cwd'  => 0,
      'Data::Dumper'   => 0,
      'DB_File'        => 0,
      'Digest::SHA'    => 0,
      'File::Basename' => 0,
      'File::Find'     => 0,
      'File::Path'     => '2.00',
      'File::Spec'     => 0,
      'Getopt::Long'   => 0,
      'Scalar::Util'   => 0,
      'Storable'       => 0,
      
      'strictures' => '1',
      
   ### Cobalt set ###
     # Crypt
      'App::bmkpasswd' => 0,
      'Crypt::Eksblowfish' => '0.003',

     # HTTP
      'HTTP::Request'  => 0,
      'HTTP::Response' => 0,
      'URI::Escape'    => 0,
      'LWP::UserAgent' => 0,

     # Utils
      'DateTime'    => 0,
      'IRC::Utils'  => '0.12',

     # Serialization
      'JSON'        => '2.00',
      'YAML::XS'    => '0.34',
      'YAML::Syck'  => '1.18',

     # Logging
      'Log::Handler' => '0.71',

     # Moo + related
      'Moo'         => '0.009',
      'MooX::Types::MooseLike' => '0.03',
      
     # Network
       'Net::IP::Minimal' => '0.02',

     # POE::
      'POE'            => '1.311',
      'POE::Wheel::Run'        => 0,
      'POE::Filter::Reference' => 0,

      'POE::Component::Client::DNS' => 0,
      'POE::Component::IRC::State'  => '6.78',
      'POE::Component::Syndicator'  => '0.06',
      'Object::Pluggable'           => '1.27',

     # Process mgmt
      'Proc::PID::File' => '1.26',
      
     # Terminal interaction
      'Term::UI'       => 0,
      'Term::ReadLine' => 0,
  },

  recommends => {
    ### POE::
      'POE::Component::SSLify' => '1.006',

    ### Utils / misc
      # terminal interaction
      'Term::ReadKey' => 0,
      'Term::ReadLine::Perl' => 0,

    ### Storage / serialization
      'JSON::XS'    => 0,

    ### Release tools, commented for now
#      'Dir::Self' => 0,
     # templating (cpodconv/release tools)
#      'Template' => 0,
     # POD conversion
#      'Pod::Find' => 0,
#      'Pod::Simple::Wiki' => 0,
     

  },
);

$build->add_to_cleanup("lib/Cobalt/Lang.pm");
$build->add_to_cleanup("bin/cobalt2-installer");
$build->create_build_script;
