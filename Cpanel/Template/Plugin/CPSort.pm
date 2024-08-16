package Cpanel::Template::Plugin::CPSort;

# cpanel - Cpanel/Template/Plugin/CPSort.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use base 'Template::Plugin';
use Cpanel::Sort;

#######IMPORTANT!!!!
# THIS LIBRARY ADOPTS THE NOMENCLATURE THAT "cpsort" IS *CASE-SENSITIVE*.
# THIS IS DIFFERENT FROM TT'S OWN "sort", WHICH IS CASE-INSENSITIVE.
# TO GET A CASE-INSENSITIVE SORT, ADD 'case' => 0 TO A SORT FIELD.

sub load {
    my ( $class, $context ) = @_;

    $context->define_vmethod( 'list', 'cpsort', \&Cpanel::Sort::list_sort );
    $context->define_vmethod( 'hash', 'cpsort', \&Cpanel::Sort::hash_sort );

    return $class;
}

1;
