package Whostmgr::Accounts::Remove::Cleanup::HordeMigration;

# cpanel - Whostmgr/Accounts/Remove/Cleanup/HordeMigration.pm
#                                                  Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use File::Path ();

=encoding utf-8

=head1 NAME

Whostmgr::Accounts::Remove::Cleanup::HordeMigration

=head1 SYNOPSIS

    Whostmgr::Accounts::Remove::Cleanup::HordeMigration::clean_up( $obj )

=head1 DESCRIPTION

Account removal’s Horde Migration cleanup, because of course MySQL RoundCube
can't leave things in the user's home directory.

Don't ask me why there wasn't some kind of parent/implementor pattern here,
as that would make sense but is conspicuously missing.

=head1 FUNCTIONS

=head2 clean_up( $obj )

Removes data sitting around in /var/cpanel/userhomes/cpanelroundcube/$USER.
Normally this is just dumped ics/vcf data from scripts/export_*_to_*

Accepts HASHREF of data from L<Cpanel::Config::LoadCpUserData>.

Returns undef, as the caller never checks the return value anyways.

=cut

our $cprc_dir = '/var/cpanel/userhomes/cpanelroundcube';

# So, I use this below in cleanup because I need to know what directory
# I need to remove, but would prefer not to duplicate code to do this while
# I'm simultanelously wanting to know whether or not this code needs to run
# at all, as the negative condition is simply that the user or dir does not
# exist. As such I've renamed this sub from `skip_this` as it was to something
# entirely too descriptive for clarity's sake. Hope that helps.
# As a final NB, _horde_dir2kill is being stashed in the parent module for
# later consumption by cleanup (which is kinda grody, but whatever).
sub maybe_construct_horde_dir2kill_for_cleanup_module_or_just_return_early ( $cleanup_obj = {} ) {
    return 1 if ref $cleanup_obj ne 'Whostmgr::Accounts::Remove::Cleanup';
    my $cpuser_hr = $cleanup_obj->{'_cpuser_data'};

    my $username = $cleanup_obj->{'_username'} || $cpuser_hr->{'USER'};
    return 1 if !$username;    # Why are we here then?
    $cleanup_obj->{'_horde_dir2kill'} = "${cprc_dir}/${username}";
    return 1 if !$cleanup_obj->{'_horde_dir2kill'};

    return !-d $cleanup_obj->{'_horde_dir2kill'};
}

sub clean_up ( $cleanup_obj = {} ) {
    return if ref $cleanup_obj ne 'Whostmgr::Accounts::Remove::Cleanup';
    return if maybe_construct_horde_dir2kill_for_cleanup_module_or_just_return_early($cleanup_obj);

    # OK! Now we should have _horde_dir2kill_set, as we ran the sub which sets
    # it just above here. Move on.

    my $errs;
    File::Path::remove_tree(
        $cleanup_obj->{'_horde_dir2kill'},
        {
            'safe'  => 1,
            'error' => $errs,
        }
    );
    foreach my $err ( @{$errs} ) { warn $err if $err; }

    return;
}

1;
