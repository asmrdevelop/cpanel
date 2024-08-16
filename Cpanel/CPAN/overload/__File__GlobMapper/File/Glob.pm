package File::Glob;
use strict;

our $VERSION = '1.05';

*CORE::GLOBAL::glob = \&File::Glob::csh_glob;
sub GLOB_ERROR  { }
sub GLOB_CSH () { }
sub bsd_glob    { }
sub glob        { }
sub csh_glob    { }
1;
