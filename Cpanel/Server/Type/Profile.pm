package Cpanel::Server::Type::Profile;

# cpanel - Cpanel/Server/Type/Profile.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Server::Type::Profile - Helper module to determine server state.

=head1 SYNOPSIS

    use Cpanel::Server::Type::Profile ();

    my $profile_id = Cpanel::Server::Type::Profile::get_current_profile();

    my %profiles = Cpanel::Server::Type::Profile::get_meta();

=head1 DESCRIPTION

This module is used to read information from the license file. Currently, this only has one function, but we may want to display more later.
The getting this information from the license file is generally considered safe since any changes to the file will cause the whole cPanel system to stop working.

=head1 FUNCTIONS

=cut

use Cpanel::Server::Type                     ();
use Cpanel::Server::Type::Profile::Constants ();

our %ENABLED_IN_ALL_ROLES = (
    'Cpanel::Server::Type::Role::MailSend'      => 1,
    'Cpanel::Server::Type::Role::MailLocal'     => 1,
    'Cpanel::Server::Type::Role::RegularCpanel' => 1,
);

use constant all_roles => sort map { 'Cpanel::Server::Type::Role::' . $_ } qw/
  CalendarContact
  DNS
  FTP
  FileStorage
  MailLocal
  MailReceive
  MailRelay
  MailSend
  MySQL
  Postgres
  RegularCpanel
  SpamFilter
  Webmail
  WebDisk
  WebServer
  /;

our %_META = (
    STANDARD => {
        experimental  => 0,
        enabled_roles => [all_roles]
    },
    MAILNODE => {
        experimental  => 0,
        enabled_roles => [
            qw(
              Cpanel::Server::Type::Role::CalendarContact
              Cpanel::Server::Type::Role::MailReceive
              Cpanel::Server::Type::Role::MailRelay
              Cpanel::Server::Type::Role::Webmail
            ), keys %ENABLED_IN_ALL_ROLES
        ],
        optional_roles => [
            qw(
              Cpanel::Server::Type::Role::MySQL
              Cpanel::Server::Type::Role::Postgres
              Cpanel::Server::Type::Role::DNS
              Cpanel::Server::Type::Role::SpamFilter
            )
        ]
    },
    DNSNODE => {
        experimental  => 0,
        enabled_roles => [
            qw(
              Cpanel::Server::Type::Role::DNS
            ), keys %ENABLED_IN_ALL_ROLES
        ],
        optional_roles => [
            qw(
              Cpanel::Server::Type::Role::MySQL
              Cpanel::Server::Type::Role::MailRelay
            )
        ],
    },
    DATABASENODE => {
        experimental  => 1,
        enabled_roles => [
            qw(
              Cpanel::Server::Type::Role::MySQL
            ), keys %ENABLED_IN_ALL_ROLES
        ],
        optional_roles => [
            qw(
              Cpanel::Server::Type::Role::Postgres
            )
        ]

    }
);

our ( $DNSNODE_MODE, $MAILNODE_MODE, $DATABASENODE_MODE );

my $_CURRENT_PROFILE;

=head2 get_current_profile

Gets the current server profile

=over 2

=item Input

=over 3

None

=back

=item Output

=over 3

=item C<SCALAR>

Returns a unique identifier representing the current server profile

=back

=back

=cut

sub get_current_profile {

    return $_CURRENT_PROFILE if defined $_CURRENT_PROFILE;

    # Check for the license-based node types
    my $product_type = Cpanel::Server::Type::get_producttype();

    if ( $product_type && $product_type ne Cpanel::Server::Type::Profile::Constants::STANDARD() ) {

        # Ideally this would die since DNSONLY should not be using the server profile to verify
        # its capabilities, but for now just log a warning to uncover any lurking issues.
        # Uncomment this during testing to determine when the profile checks are mistakenly called on DNSONLY
        # if ( $product_type eq Cpanel::Server::Type::Profile::Constants::DNSONLY() ) {
        #     require Cpanel::Debug;
        #     Cpanel::Debug::log_warn("Attempt to check current server profile on DNSONLY.");
        # }

        return $_CURRENT_PROFILE = $product_type;
    }

    # If we’re not running a license-based node type, we have to deterministically figure out
    # if the standard node is running one of the alternate profiles.
    my $roles = {};

    require Cpanel::LoadModule;

  PROFILE: foreach my $profile ( keys %_META ) {

        # Skip the STANDARD profile as that is our default fallback
        next if $profile eq Cpanel::Server::Type::Profile::Constants::STANDARD();

        my $disabled_roles_ar = get_disabled_roles_for_profile($profile);

        if ($disabled_roles_ar) {

            # If any disabled role is enabled, it can't be this profile
            foreach my $role (@$disabled_roles_ar) {

                if ( !exists $roles->{$role} ) {
                    Cpanel::LoadModule::load_perl_module($role);
                    $roles->{$role} = $role->is_enabled();
                }

                next PROFILE if $roles->{$role};
            }

        }

        if ( $_META{$profile}{enabled_roles} ) {

            # If any enabled role is disabled, it can't be this profile
            foreach my $role ( @{ $_META{$profile}{enabled_roles} } ) {

                if ( !exists $roles->{$role} ) {
                    Cpanel::LoadModule::load_perl_module($role);
                    $roles->{$role} = $role->is_enabled();
                }

                next PROFILE if !$roles->{$role};
            }

        }

        # All of the roles for this profile are in the proper enabled or disabled state
        return $_CURRENT_PROFILE = $profile;
    }

    # If none of the other profiles matched, we fallback to the FULL profile
    return $_CURRENT_PROFILE = Cpanel::Server::Type::Profile::Constants::STANDARD();
}

=head2 current_profile_matches

Matches current profile against a single profile or array of profiles

=over 2

=item Input

=over 3

$profiles_ar - A single profile name 'STANDARD' or an array ref of profile names ['STANDARD', 'MAIL']

=back

=item Output

=over 3

=item C<SCALAR>

Returns a unique identifier representing the current server profile

=back

=back

=cut

sub current_profile_matches {
    my ($profiles_ar) = @_;

    $profiles_ar = [$profiles_ar] if 'ARRAY' ne ref $profiles_ar;

    my $current_profile = get_current_profile();

    return grep { $_ eq $current_profile } @{$profiles_ar};
}

=head2 is_valid_for_profile( $rule )

Check if the current profile match the rule using Cpanel::Validate::AnyAllMatcher::match

=over 2

=item Input

=over 3

$rule - a rule in Cpanel::Validate::AnyAllMatcher definition

Example:

        {
            "match": "none", # any, all
            "items": ["WP2"]
        }

=back

=item Output

=over 3

=item C<SCALAR>

Returns a boolean to check if it matches or not.

=back

=back

=cut

sub is_valid_for_profile ($rule) {

    if ( ref $rule ne 'HASH' ) {
        return current_profile_matches($rule);
    }

    if ( !ref $rule->{items} ) {
        require Data::Dumper;
        die q[Invalid rule 'missing items entry' ] . Data::Dumper::Dumper($rule);
    }

    require Cpanel::Validate::AnyAllMatcher;
    return Cpanel::Validate::AnyAllMatcher::match( $rule, \&current_profile_matches );
}

=head2 get_meta

Gets metadata describing the available server profiles

=over 2

=item Input

=over 3

None

=back

=item Output

=over 3

=item C<HASHREF>

Returns a hashref containing the metadata in the format:

    {
        PROFILE_IDENTIFIER => {
            enabled_roles  => [],
            optional_roles => []
        },
        ...
    }

C<PROFILE_IDENTIFIER> is a unique identifier for the profile

C<enabled_roles> and C<optional_roles> are optional ARRAYREFs of strings identifying which C<Cpanel::Server::Type::Role> modules will be enabled or disabled when activating a profile

=back

=back

=cut

my $_loaded_descriptions;

sub get_meta {
    if ($_loaded_descriptions) {
        foreach my $profile ( keys %_META ) {
            delete @{ $_META{$profile} }{qw(name description)};
            $_loaded_descriptions = 0;
        }
    }

    return \%_META;
}

=head2 get_meta_with_descriptions

This function exactly the same data as get_meta except is adds the following keys values
to each PROFILE_IDENTIFIER like:

    {
        PROFILE_IDENTIFIER => {
            name           => "Profile Name",
            description    => "A longer description describing the profile",
            enabled_roles  => [],
            optional_roles => []
        },
        ...
    }

C<name> is a C<Cpanel::LocaleString> with the friendly name of the profile.    ## no extract maketext

C<description> is a C<Cpanel::LocaleString> with the friendly description of the profile.    ## no extract maketext

=cut

sub get_meta_with_descriptions {
    if ( !$_loaded_descriptions ) {
        require 'Cpanel/Server/Type/Profile/Descriptions.pm';    ## no critic qw(Bareword) - hide from perlpkg
        my $add_hr = \%Cpanel::Server::Type::Profile::Descriptions::_META;
        foreach my $profile ( keys %$add_hr ) {
            @{ $_META{$profile} }{ keys %{ $add_hr->{$profile} } } = values %{ $add_hr->{$profile} };
        }
    }
    return \%_META;
}

=head2 get_disabled_roles_for_profile($profile)

Get an arrayref of disabled roles for a given profile
or returns undef if there are no disabled roles.

=over 2

=item Input

=over 3

=item $profile C<SCALAR>

    The profile to fetch the disabled roles for.

=back

=item Output

=over 3

=item C<ARRAYREF>

    An arrayref of roles that are disabled for the given profile.

=back

=back

=cut

sub get_disabled_roles_for_profile {
    my ($profile)          = @_;
    my $all_possible_roles = get_all_possible_roles();
    my $meta               = get_meta();                 # call get_meta since it may be mocked

    die "No META for profile “$profile”!" if !defined $meta->{$profile};

    my %profile_roles  = map  { $_ => 1 } ( ( $meta->{$profile}{enabled_roles} ? @{ $meta->{$profile}{enabled_roles} } : () ), ( $meta->{$profile}{optional_roles} ? @{ $meta->{$profile}{optional_roles} } : () ) );
    my @disabled_roles = grep { !$profile_roles{$_} } @$all_possible_roles;
    return @disabled_roles ? \@disabled_roles : undef;
}

=head2 get_all_possible_roles()

Get an arrayref of all possible roles.

=over 2

=item Output

=over 3

=item C<ARRAYREF>

    Returns an arrayref of all possible roles.

=back

=back

=cut

sub get_all_possible_roles {
    return [all_roles];
}

=head2 $subdomains_ar = get_service_subdomains_for_profile( $PROFILE )

This looks up which service subdomains are associated with a given profile.

=over

=item Input

=over

=item $profile C<SCALAR>

    The profile to fetch the service subdomains for.

=back

=item Output

=over

=item C<ARRAYREF>

    Returns an ARRAYREF of service subdomains.

=back

=back

=cut

sub get_service_subdomains_for_profile {
    my ($profile) = @_;

    my $meta = get_meta();    # call get_meta since it may be mocked
    die "No META for profile “$profile”!" if !defined $meta->{$profile};

    my @profile_roles = ( ( $meta->{$profile}{enabled_roles} ? @{ $meta->{$profile}{enabled_roles} } : () ), ( $meta->{$profile}{optional_roles} ? @{ $meta->{$profile}{optional_roles} } : () ) );

    require 'Cpanel/Server/Type/Change/Backend.pm';    ## no critic qw(Bareword) - hide from perlpkg

    my @service_subdomains;
    push @service_subdomains, Cpanel::Server::Type::Change::Backend::get_role_service_subs($_) for @profile_roles;

    return \@service_subdomains;
}

#----------------------------------------------------------------------

sub _reset_cache {
    undef $_CURRENT_PROFILE;
    return;
}

1;
