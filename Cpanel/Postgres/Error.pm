package Cpanel::Postgres::Error;

# cpanel - Cpanel/Postgres/Error.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

#cf. http://www.postgresql.org/docs/9.4/static/errcodes-appendix.html
use constant {
    connection_exception          => '08000',
    connection_failure            => '08006',
    dependent_objects_still_exist => '2BP01',
    invalid_catalog_name          => '3D000',
    duplicate_object              => '42710',
    undefined_object              => '42704',
    admin_shutdown                => '57P01',
};

sub get_name_for_error {
    my ($str) = @_;

    my $this_func_name = ( caller 0 )[3];
    $this_func_name =~ s<.+::><>;

    for my $k ( keys %Cpanel::Postgres::Error:: ) {
        next if $k eq $this_func_name;

        #If you do $module->can('foo'), then $module’s symbol table
        #will contain entries for both 'can' and 'foo'. But if you
        #call $module->can('can'), Perl throws an exception for misuse
        #of can().
        next if $k eq 'can';

        next if !__PACKAGE__->can("$k");

        return $k if __PACKAGE__->$k() eq $str;
    }

    return undef;
}

1;
