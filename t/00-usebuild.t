use Test::More;
use Module::Build;
use Try::Tiny;
use strict; use warnings FATAL => 'all';

try {
  Module::Build->current->base_dir
} catch {
  BAIL_OUT(
    "Failed to retrieve base_dir() from Module::Build ;" .
    "are you trying to run the test suite outside of './Build'?"
  )
};

use_ok('Bot::Cobalt');

done_testing;
