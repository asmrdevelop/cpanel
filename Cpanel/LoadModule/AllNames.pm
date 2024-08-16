package Cpanel::LoadModule::AllNames;

# cpanel - Cpanel/LoadModule/AllNames.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LoadModule::AllNames

=head1 DESCRIPTION

This module contains tools for finding “all names” of modules
to load within a given namespace.

=cut

#----------------------------------------------------------------------

use Cpanel::Autodie        qw(exists);
use Cpanel::FileUtils::Dir ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $name_path = get_loadable_modules_in_namespace($NAMESPACE)

Returns a hashref for all modules that are I<immediately> under
$NAMESPACE.

For example, if $NAMESPACE is C<Foo::Bar>, I might get back:

    {
        "Foo::Bar::Baz" => "/path/to/Foo/Bar/Baz.pm",
        # ..
    }

Note that the above hash would B<not> include C<Foo::Bar::Baz::Qux>
because that’s a level deeper.

=cut

sub get_loadable_modules_in_namespace ($ns) {
    my $reldir = ( $ns =~ tr<:></>sr );

    my %module_path;

    local $@;

    my @incdirs = @INC;

    for my $incdir (@incdirs) {
        $incdir .= "/$reldir";

        warn if !eval {
            if ( Cpanel::Autodie::exists($incdir) && -d _ ) {
                my $nodes_ar = Cpanel::FileUtils::Dir::get_directory_nodes($incdir);

                for my $name (@$nodes_ar) {
                    next if $name !~ m<\.pm\z>;

                    my $module_name = "$ns\::$name";
                    substr( $module_name, -3 ) = q<>;

                    $module_path{$module_name} ||= "$incdir/$name";
                }
            }

            1;
        };
    }

    return \%module_path;
}

1;
