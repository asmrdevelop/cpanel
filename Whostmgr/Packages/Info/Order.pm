# cpanel - Whostmgr/Packages/Info/Order.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::Packages::Info::Order;

use cPstrict;

=head1 NAME

Whostmgr::Packages::Info::Order

=head1 DESCRIPTION

Lightweight order specification for keys defined in Whostmgr::Packages::Info.
This module may be used with or without also loading Whostmgr::Packages::Info.

=cut

#----------------------------------------------------------------------

use Whostmgr::Packages::Info::Modular ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 my $keys_ref = Whostmgr::Packages::Info::Order::get_display_order(type => ..., uppercase => 0|1)

Returns an array ref of keys corresponding to the default info returned by C<get_defaults()>,
in the order most appropriate for presentation to the user (related options grouped
together).

C<type> must be one of:

=over

=item * numeric - Return only numeric items

=item * non-numeric - Return only non-numeric items

=item * all - Return all items

=back

C<uppercase> is an optional boolean which will cause the returned keys to be
uppercase. This is needed in some contexts where the keys are expected to
match the values from the cp user file.

=cut

use constant _NUMERICS => (
    'quota',
    'bwlimit',
    'maxftp',
    'maxpop',
    'maxlst',
    'maxsql',
    'maxsub',
    'maxpark',
    'maxaddon',
    'maxpassengerapps',
    'max_email_per_hour',
    'max_defer_fail_percentage',
    'max_emailacct_quota',
    'max_team_users',
);

use constant _NON_NUMERICS => (
    'cpmod',
    'cgi',
    'hasshell',
    'featurelist',
    'language',
    'ip',
    'digestauth',
);

sub get_display_order {
    my %opts = @_;

    my $type = $opts{type};
    if ( !$type || $type !~ /^(?:numeric|non-numeric|all)$/ ) {
        require Carp;
        Carp::croak(q{You must specify a type: One of numeric, non-numeric, or all});
    }

    my $uc = $opts{uppercase};

    my @items;

    if ( $type eq 'numeric' || $type eq 'all' ) {
        push @items, _NUMERICS;
    }

    if ( $type eq 'non-numeric' || $type eq 'all' ) {
        push @items, _NON_NUMERICS;
    }

    _insert_modular_components( \@items, $type );

    if ($uc) {
        $_ = uc for @items;
    }

    return \@items;
}

sub _insert_modular_components ( $items_ar, $needed_type ) {

    my @components = Whostmgr::Packages::Info::Modular::get_enabled_components();
    if ( $needed_type ne 'all' ) {
        @components = grep { ( $_->type() eq 'numeric' ) eq ( $needed_type eq 'numeric' ) } @components;
    }

    # This doesn’t currently tolerate a case where an enabled component
    # would sort before a disabled one. That’s a possible iteration.

    my %sort_before = map { $_->name_in_api() => $_->package_insert_before() } @components;

  INSERT_LOOP:
    while (%sort_before) {
        for my $name ( sort keys %sort_before ) {
            for my $i ( 0 .. $#$items_ar ) {
                if ( $items_ar->[$i] eq $sort_before{$name} ) {
                    splice @$items_ar, $i, 0, $name;
                    delete $sort_before{$name};
                    next INSERT_LOOP;
                }
            }
        }

        my @extras = sort keys %sort_before;
        die "Leftover modular insertion: @extras";
    }

    return;
}

1;
