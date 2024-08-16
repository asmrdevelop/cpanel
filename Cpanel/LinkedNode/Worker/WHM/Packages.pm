package Cpanel::LinkedNode::Worker::WHM::Packages;

# cpanel - Cpanel/LinkedNode/Worker/WHM/Packages.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Try::Tiny;

use Cpanel::CommandQueue                 ();
use Cpanel::Features::Lists::Propagate   ();
use Cpanel::LinkedNode::Alias::Constants ();    # PPI USE OK - Constants
use Cpanel::LinkedNode::Worker::WHM      ();

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::Worker::WHM::Packages - Methods for managing packages across linked nodes

=head1 SYNOPSIS

    use Cpanel::LinkedNode::Worker::WHM::Packages ();

    Cpanel::LinkedNode::Worker::WHM::Packages::create_or_update_package( $package_settings );

    Cpanel::LinkedNode::Worker::WHM::Packages::kill_package_if_exists( $package_name );

=head1 DESCRIPTION

This module provides methods for managing packages across linked server nodes. The methods
will execute API methods on the linked nodes and execute the local actions required to
create, update, and delete packages. If any of the remote API calls or the local action
fails the methods will rollback the changes so the packages are in their preexisting state.

If there are no linked nodes on the server, only the local package will be created or
updated.

=head1 METHODS

=head2 Whostmgr::LinkedNode::Worker::WHM::Packages::create_or_update_package( $package_settings )

Creates a package with the specified settings, or updates the package if it already exists.

This method calls the C<addpkg> or C<editpkg> WHM API 1 methods on the remote nodes,
depending on whether or not the package already exists.

On rollback, either the C<killpkg> or C<editpkg> WHM API 1 methods are called on the remote
nodes, depending on whether C<addpkg> or C<editpkg> respectively was called.

=over

=item Input

=over

=item C<HASHREF> - Package settings

A C<HASHREF> of package settings identical to what C<Whostmgr::Packages::Mod::_modpkg>
expects.

This C<HASHREF> must include a C<pkgname> or C<name> key that identifies the package. Both
settings are allowed to provide parity with the pre-existing package logic, C<pkgname> is
preferred over C<name>.

=back

=item Output

=over

Returns the result of the C<Whostmgr::Packages::Mod::__modpkg> local action on success, dies
otherwise.

=back

=back

=cut

sub create_or_update_package ($package_settings) {
    if ( !$package_settings ) {
        require Cpanel::Exception;
        die Cpanel::Exception->create_raw("You must specify the package settings.");
    }

    my $pkgname = get_pkgname_from_package_settings($package_settings);

    require Whostmgr::Packages;
    require Whostmgr::Packages::Mod;
    $pkgname = Whostmgr::Packages::Mod::_get_package_name_for_user($pkgname);

    my $is_edit = 0;
    my %pkg_existed;

    if ( defined $package_settings->{'edit'} && $package_settings->{'edit'} eq 'yes' ) {
        $is_edit = 1;
        $pkg_existed{Cpanel::LinkedNode::Alias::Constants::LOCAL} = _load_local_package_if_exists($pkgname);
    }

    # We need to save & reload the package before sending the parameters onto the remote nodes
    # because the settings that get saved will be adjusted based on the package owner privileges.
    # When __modpkg gets run on the remote nodes, it will be run as root so no the parameters
    # will be saved as-is without privilege based adjustments.  By saving and reloading
    # the package locally first, we can send the corrected values to the remote nodes.
    my @local_results = _do_or_die( \&Whostmgr::Packages::Mod::__modpkg, $package_settings );
    $package_settings = _reload_package( $pkgname, $is_edit );

    my $local_action = sub {
        return @local_results;
    };

    my $local_undo = sub {

        my $original_pkg = $pkg_existed{Cpanel::LinkedNode::Alias::Constants::LOCAL};

        if ( !$original_pkg ) {
            return _do_or_die( \&Whostmgr::Packages::__killpkg, { pkg => $pkgname } );
        }
        else {

            _fix_package_settings( $pkgname, $original_pkg, 1 );

            return _do_or_die( \&Whostmgr::Packages::Mod::__modpkg, $original_pkg );
        }

    };

    # Several tests that predate the feature list propagation here expect
    # to get here without having defined a “featurelist”. Those may be
    # artificial tests, but for now we ignore a missing “featurelist”.
    #
    my $featurelist = $package_settings->{'featurelist'};

    my $undo_feature_list_cr;

    my $remote_action = sub ($node_obj) {
        my $feature_list_cr;

        my $cq = Cpanel::CommandQueue->new();

        if ( length $featurelist ) {
            ( $feature_list_cr, $undo_feature_list_cr ) = Cpanel::Features::Lists::Propagate::get_do_and_undo( $node_obj->get_remote_api(), $featurelist );
            $cq->add( $feature_list_cr, $undo_feature_list_cr, 'undo featurelist sync' );
        }

        $cq->add(
            sub {
                my $original_pkg = _ensure_remote_node_has_package_and_is_in_sync( $node_obj, $package_settings, $pkgname );

                if ($original_pkg) {
                    $pkg_existed{ $node_obj->alias() } = $original_pkg;
                }
            }
        );

        $cq->run();
    };

    my $remote_undo = sub ($node_obj) {
        try {
            my $api_obj   = Cpanel::LinkedNode::Worker::WHM::create_node_api_obj($node_obj);
            my %base_opts = ( node_obj => $node_obj, api_obj => $api_obj );

            my $original_pkg = $pkg_existed{ $node_obj->alias() };

            if ( !$original_pkg ) {
                Cpanel::LinkedNode::Worker::WHM::do_whmapi1_call( %base_opts, function => 'killpkg', api_opts => { pkgname => $pkgname } );
            }
            else {
                _filter_package_by_remote_roles( $node_obj, $original_pkg );
                _fix_magic_zeros($original_pkg);
                require Whostmgr::Packages::Legacy;
                my $pkg_opts = Whostmgr::Packages::Legacy::pkgref_to_whmapi1_addpkg_args( { name => $pkgname, %$original_pkg } );
                Cpanel::LinkedNode::Worker::WHM::do_whmapi1_call( %base_opts, function => 'editpkg', api_opts => $pkg_opts );
            }
        }
        catch {
            warn "Failed to undo package sync: $_";
        };

        $undo_feature_list_cr->() if $undo_feature_list_cr;
    };

    return Cpanel::LinkedNode::Worker::WHM::do_on_all_nodes(
        local_action  => $local_action,
        local_undo    => $local_undo,
        remote_action => $remote_action,
        remote_undo   => $remote_undo,
    );
}

=head2 synchronize_package_on_remotes( \%PACKAGE_SETTINGS )

Like C<create_or_update_package()>, except:

=over

=item * This does B<NOT> filter the given package name through
C<Whostmgr::Packages::Mod::_get_package_name_for_user()>.

=item * This doesn’t attempt to edit a local package.

=item * This doesn’t roll back on failure (though any failure still produces
a thrown exception).

=back

=cut

sub synchronize_package_on_remotes ($package_settings) {
    my $pkgname = get_pkgname_from_package_settings($package_settings);

    return Cpanel::LinkedNode::Worker::WHM::do_on_all_nodes(
        remote_action => sub ($node_obj) {
            _ensure_remote_node_has_package_and_is_in_sync( $node_obj, $package_settings, $pkgname );
        },
    );
}

sub get_pkgname_from_package_settings ($package_settings) {
    my $pkgname = $package_settings->{'pkgname'} || $package_settings->{'name'};

    if ( !$pkgname ) {
        require Cpanel::Exception;
        die Cpanel::Exception->create( "You must specify either the “[_1]” or “[_2]” parameter.", [ "pkgname", "name" ] );
    }

    return $pkgname;
}

#
# This is for loading a package after saving it so all the
# privilege-based parameter adjustments will be applied
# This needed to be moved to a separate function for mocking purposes
#
sub _reload_package ( $pkgname, $is_edit ) {

    my $package_settings = _load_local_package_if_exists($pkgname);
    _fix_package_settings( $pkgname, $package_settings, $is_edit );

    return $package_settings;
}

#
# Take package settings that have been loaded from an existing
# package and make them suitable to send back to __modpkg
#
sub _fix_package_settings ( $pkgname, $package_settings, $is_edit ) {
    require Whostmgr::Packages::Mod;

    # When passing keys to _modpkg, it assumes that keys with capital letters
    # came from cpuser data and will perform translations on things like the quota.
    # This can be prevented by converting the package keys to lower-case before
    # passing them to __modpkg.
    Whostmgr::Packages::Mod::convert_package_hr_to_lowercase($package_settings);

    _fix_magic_zeros($package_settings);

    $package_settings->{'name'} = $pkgname;
    $package_settings->{'edit'} = 'yes' if $is_edit;

    return;
}

sub _load_local_package_if_exists ($pkgname) {
    require Whostmgr::Packages::Load;
    my %load_result;
    my $local_pkg = Whostmgr::Packages::Load::load_package_if_exists( $pkgname, \%load_result );

    if ( !$load_result{'result'} ) {
        die "Failed to load local package “$pkgname”: $load_result{'reason'}\n";
    }

    return $local_pkg || {};
}

sub _filter_package_by_remote_roles ( $node_obj, $local_pkg ) {
    my $profile_resp = Cpanel::LinkedNode::Worker::WHM::do_whmapi1_call(
        node_obj => $node_obj,
        function => 'get_current_profile',
    );

    require Whostmgr::Accounts::Abilities;

    Whostmgr::Accounts::Abilities::filter_package_by_disabled_roles(
        $local_pkg,
        [ map { $_->{'module'} } @{ $profile_resp->{'disabled_roles'} } ],
    );

    return;
}

# If the package already existed on the remote, then the
# system will call editpkg to make sure it is in sync
# with the local machine and $original_pkg is returned; otherwise, we return undef.
sub _ensure_remote_node_has_package_and_is_in_sync ( $node_obj, $pkg_settings_hr, $pkgname ) {    ## no critic qw(ManyArg)

    # The $pkg_settings_hr hashref from the callers
    # usually contains a “name”. Let’s remove that so we have a
    # hashref that correlates better with what’s actually in packages.
    my $package_settings = {%$pkg_settings_hr};
    delete $package_settings->{'name'};

    my %base_opts = ( node_obj => $node_obj );

    my $local_pkg = _load_local_package_if_exists($pkgname);

    _fix_magic_zeros($local_pkg);

    @{$local_pkg}{ map { tr/a-z/A-Z/r } keys %$package_settings } = @{$package_settings}{ ( keys %$package_settings ) };

    _filter_package_by_remote_roles( $node_obj, $local_pkg );

    delete @{$local_pkg}{ 'name', 'pkgname' };

    require Whostmgr::Packages::Legacy;
    my $pkg_opts = Whostmgr::Packages::Legacy::pkgref_to_whmapi1_addpkg_args( { %$local_pkg, name => $pkgname } );

    my $listpkgs_resp = Cpanel::LinkedNode::Worker::WHM::do_whmapi1_call( %base_opts, function => 'listpkgs', api_opts => {} );

    my ($original_pkg) = grep { $_->{name} eq $pkgname } @$listpkgs_resp;

    if ($original_pkg) {
        Cpanel::LinkedNode::Worker::WHM::do_whmapi1_call( %base_opts, function => 'editpkg', api_opts => $pkg_opts );
        return $original_pkg;
    }

    Cpanel::LinkedNode::Worker::WHM::do_whmapi1_call( %base_opts, function => 'addpkg', api_opts => $pkg_opts );
    return undef;
}

=head2 Whostmgr::LinkedNode::Worker::WHM::Packages->kill_package_if_exists( $package_name )

Kills the package with the specified name if it exists.

This method calls the C<killpkg> WHM API 1 method on the remote nodes, depending on whether
or not the package exists.

On rollback, the C<addpkg> WHM API 1 methods is called on the remote nodes if an existing
package was killed.

=over

=item Input

=over

=item C<SCALAR> - String

The name of the package to kill.

=back

=item Output

=over

Returns the result of the C<Whostmgr::Packages::__killpkg> local action on success, dies
otherwise.

=back

=back

=cut

sub kill_package_if_exists ($pkgname) {

    my %killed;

    my $remote_action = sub ($node_obj) {

        my $api_obj   = Cpanel::LinkedNode::Worker::WHM::create_node_api_obj($node_obj);
        my %base_opts = ( node_obj => $node_obj, api_obj => $api_obj );

        my $listpkgs_resp = Cpanel::LinkedNode::Worker::WHM::do_whmapi1_call( %base_opts, function => 'listpkgs', api_opts => {} );

        if ( my ($existing_pkg) = grep { $_->{name} eq $pkgname } @$listpkgs_resp ) {
            $killed{ $node_obj->alias() } = $existing_pkg;
            return Cpanel::LinkedNode::Worker::WHM::do_whmapi1_call( %base_opts, function => 'killpkg', api_opts => { pkgname => $pkgname } );
        }

        return;
    };

    my $remote_undo = sub ($node_obj) {

        my $killed_pkg = $killed{ $node_obj->alias() };

        if ($killed_pkg) {
            my $api_obj  = Cpanel::LinkedNode::Worker::WHM::create_node_api_obj($node_obj);
            my $pkg_opts = Whostmgr::Packages::Legacy::pkgref_to_whmapi1_addpkg_args($killed_pkg);
            return Cpanel::LinkedNode::Worker::WHM::do_whmapi1_call( node_obj => $node_obj, api_obj => $api_obj, function => 'addpkg', api_opts => $pkg_opts );
        }

        return;
    };

    my $local_action = sub {

        require Whostmgr::Packages::Exists;

        # Whostmgr::Packages::Exists::package_exists also verifys the current
        # logged in user can access the package
        if ( Whostmgr::Packages::Exists::package_exists($pkgname) ) {
            my $pkg_ref = Whostmgr::Packages::Load::load_package($pkgname);
            $pkg_ref->{'name'} = $pkgname;
            $killed{Cpanel::LinkedNode::Alias::Constants::LOCAL} = $pkg_ref;
            return _do_or_die( \&Whostmgr::Packages::__killpkg, { pkg => $pkgname } );
        }

        return;
    };

    my $local_undo = sub {

        require Whostmgr::Packages::Mod;

        my $killed_pkg = $killed{Cpanel::LinkedNode::Alias::Constants::LOCAL};

        if ($killed_pkg) {
            Whostmgr::Packages::Mod::convert_package_hr_to_lowercase($killed_pkg);
            return _do_or_die( \&Whostmgr::Packages::Mod::__modpkg, $killed_pkg );
        }

        return;
    };

    return Cpanel::LinkedNode::Worker::WHM::do_on_all_nodes(
        local_action  => $local_action,
        local_undo    => $local_undo,
        remote_action => $remote_action,
        remote_undo   => $remote_undo,
    );
}

sub _do_or_die ( $cr, $opts_hr ) {
    my ( $status, $resp, %extra ) = $cr->(%$opts_hr);

    if ( !$status ) {
        die $extra{exception_obj} if $extra{exception_obj};
        require Cpanel::Exception;
        die Cpanel::Exception->create_raw($resp);
    }

    return ( $status, $resp, %extra );
}

sub _fix_magic_zeros ($package_settings) {

    # The validator for max_defer_fail_percentage specifically rejects zero even though that’s
    # the value that’s stored in the package file. In order to pass the parameter to _modpkg or
    # the WHM API 1 addpkg or editpkg methods, this must be changed to a literal “unlimited”
    # string value.
    foreach my $key (qw(max_defer_fail_percentage MAX_DEFER_FAIL_PERCENTAGE)) {
        if ( exists $package_settings->{$key} && $package_settings->{$key} !~ tr/0-9//c && $package_settings->{$key} == 0 ) {
            $package_settings->{$key} = "unlimited";
        }
    }
    return;
}

1;
