package Cpanel::ActiveSync;

# cpanel - Cpanel/ActiveSync.pm                     Copyright 2022 cPanel L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::AcctUtils::DomainOwner::Tiny ();
use Cpanel::Security::Authz              ();

=pod

=encoding utf-8

=head1 NAME

Cpanel::ActiveSync - Get information about Z-Push, our ActiveSync server

=head1 FUNCTIONS

=head2 is_z_push_installed()

Returns 1 if Z-Push is installed, 0 otherwise.

=cut

sub is_z_push_installed {
    return -e '/usr/local/cpanel/3rdparty/usr/share/z-push/src/index.php' ? 1 : 0;
}

=head2 get_ports()

Returns a hashref with the key 'ssl'. The value is the port number on which cpdavd
is listening. Previously there was also a 'non_ssl' key, but this is no longer used.

=cut

sub get_ports {
    return { ssl => 2091 };
}

=head2 should_showcase_z_push()

Returns 1 if CCS or Z-Push are not already installed and should be spotlighted in the Feature Showcase, 0 otherwise.

=cut

sub should_showcase_z_push {
    return ( !_is_ccs_installed() || !is_z_push_installed() ) ? 1 : 0;
}

=head2 is_activesync_available_for_user( USER )

Returns 1 if ActiveSync is available for the user to use, 0 otherwise.

"Available" means:

=over

=item * Z-Push is installed.

=item * The user has the "caldavcarddav" feature.

=item * The user has the "activesync" feature.

=back

Context: Can be used within a cPanel session or API call.

=head3 ARGUMENTS

=over

=item USER - string [REQUIRED] - A cPanel username or a sub-account in user@domain form.

=back

=head3 THROWS

=over

=item When the required USER argument is missing.

=back

=cut

sub is_activesync_available_for_user {
    my ($user) = @_;
    if ( !$user ) {
        require Carp;
        Carp::croak('is_activesync_available_for_user(): Required user argument is missing or empty.');
    }

    return 0 if !is_z_push_installed();

    # When running in root context this isn't strictly necessary, but finding
    # the domain's owner here ensures that verify_user_has_features can do the
    # right thing when running in Cpanel context
    if ( my ($domain) = $user =~ /\@(.+)/ ) {
        $user = Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner( $domain, { default => '' } );
        return 0 if !$user;
    }

    local $@;
    my $has_features = eval {
        Cpanel::Security::Authz::verify_user_has_features(
            $user,
            { match => 'all', features => [ 'caldavcarddav', 'activesync' ] }
        );
        1;
    } ? 1 : 0;
    my $error = $@;
    die $error if $error && ref $error ne 'Cpanel::Exception::FeaturesNotEnabled';
    return $has_features;
}

sub _is_ccs_installed {
    require Cpanel::DAV::Provider;
    return Cpanel::DAV::Provider::installed() eq 'CCS' ? 1 : 0;
}

1;

