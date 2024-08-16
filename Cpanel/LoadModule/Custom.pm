package Cpanel::LoadModule::Custom;

# cpanel - Cpanel/LoadModule/Custom.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

C<Cpanel::LoadModule::Custom>

=head1 DESCRIPTION

This module contains a dynamic module loader that will load modules from
a custom location.

=head1 SYNOPSIS

  use Cpanel::LoadModule::Custom ();

  # Get a list of the modules in /var/cpanel/perl/API
  my @modules = Cpanel::LoadModule::Custom::list_modules_for_namespace("API");

  foreach my $module (@modules) {
      Cpanel::LoadModule::Custom::load_perl_module("API::$module");
      if (my $do_thing = "API::$module"->can('do_thing')) {
          $do_thing->();
      }
  }

  my @more = qw(Email Custom);
  foreach my $module (@more) {
      # Prioritize the buildin implementations
      Cpanel::LoadModule::Custom::load_perl_module("Cpanel::API::$module", builtin_first => 1);
      if (my $do_thing = "Cpanel::API::$module"->can('do_thing')) {
          $do_thing->();
      }
  }

=cut

# It is because of this dependency that we don’t include this logic
# in Cpanel/LoadModule.pm.
use Cpanel::ConfigFiles      ();
use Cpanel::LoadModule::Name ();

use Cpanel::LoadModule ();

our $_CUSTOM_MODULES_DIR;
*_CUSTOM_MODULES_DIR = \$Cpanel::ConfigFiles::CUSTOM_PERL_MODULES_DIR;

#NOTE: This does NOT do a deep inquiry: it just lists
#the modules in a single namespace.

=head1 FUNCTIONS

=head2 list_modules_for_namespace($NAMESPACE)

List the modules availabe in the requested namespace only in the custom module directory.

The namespace is used to build the path to search.

=head3 ARGUMENTS

=over

=item $NAMESPACE - string

A path (A/B/C) or perl namespace (A::B::C). The namespace should resolve into a directory path, not
a fully specified package name as each segment is treated as a directory.

=back

=head3 RETURNS

A list of the module names in that directory. It does not return the full package name,
just the list of Perl module file names.

=cut

sub list_modules_for_namespace {
    my ($ns) = @_;
    $ns =~ s<::></>g;

    return Cpanel::LoadModule::Name::get_module_names_from_directory("$_CUSTOM_MODULES_DIR/$ns");
}

=head2 load_perl_module($MODULE, %OPTS)

Load the requested perl module based on the rules defined in the C<%OPTS>

=head3 ARGUMENTS

=over

=item $MODULE - string

The perl module name to load.

=item %OPTS - HASH

Any of the following:

=over

=item builtin_first - Boolean

When true, the built in include paths will be searched before the custom include paths. Otherwise, the custom include paths will be searched first.

The default is to search the custom include paths first to maintain backward compatability with the original design.

=back

=back

=cut

sub load_perl_module {
    my ( $module, %opts ) = @_;

    local @INC = (
        ( !$opts{builtin_first} ? ($_CUSTOM_MODULES_DIR) : () ),
        @INC,
        ( $opts{builtin_first} ? ($_CUSTOM_MODULES_DIR) : () ),
    );

    return Cpanel::LoadModule::load_perl_module($module);
}

1;
