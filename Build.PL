#!/usr/bin/env perl

use Module::Build;

my $build = Module::Build->new(
  dist_name => 'Cobalt',
  dist_abstract => 'Pluggable IRC bot (cobalt2)',
  dist_author => 'Jon Portnoy <avenj@cobaltirc.org>',
  dist_version_from => 'lib/Cobalt/Core.pm',
  license => 'perl',

  ## A passthru-to-build makefile:
  create_makefile_pl => 'small',

  requires => {
   ### Core set ###
      'perl' => '5.12.1',
      'Carp' => 0,
      'Data::Dumper' => 0,
      'File::Basename' => 0,
      'File::Find' => 0,
      'File::Path' => '2.00',
      'File::Spec' => 0,
      'Getopt::Long' => 0,

   ### Cobalt set ###
     # Crypt
      'Crypt::Eksblowfish' => '0.003',

     # Files
      'File::Slurp' => '9999',

     # Utils
      'IRC::Utils'  => '0.12',

     # Serialization
      'JSON'        => '2.00',
      'YAML::Syck'  => '1.18',

     # Logging
      'Log::Handler' => '0.71',

     # Moose + related
      'Moose'                => '2.00',
      'MooseX::NonMoose'     => '0.18',
      'namespace::autoclean' => '0.12',

     # POE::
      'POE'            => '1.311',

      # pocoirc6.75 contained bugfix fixing use of LocalAddr
      'POE::Component::IRC'        => '6.75',
      'POE::Component::Syndicator' => '0.06',
      'Object::Pluggable'          => '1.27',

     # Process mgmt
      'Proc::PID::File' => '1.26',
  },

  recommends => {
    ### POE::
      'POE::Component::SSLify' => '1.006',
    ### Utils / misc
      # terminal interaction
      'Term::ReadKey' => 0,

    ### Release tools, commented for now
     # templating (cpodconv/release tools)
#      'Template' => 0,
     # POD conversion
#      'Pod::Find' => 0,
#      'Pod::Simple::Wiki' => 0,
     

  },
);


$build->create_build_script;
