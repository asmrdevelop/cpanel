package Cpanel::Server::Type::Profile::Roles;

# cpanel - Cpanel/Server/Type/Profile/Roles.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use constant _MATCH_DEFAULT => 'all';
use Cpanel::Server::Type::Profile ();

=encoding utf-8

=head1 NAME

Cpanel::Server::Type::Profile::Roles - Helper module check the state of a server profile

=head1 SYNOPSIS

    use Cpanel::Server::Type::Profile::Roles ();

    Cpanel::Server::Type::Profile::Roles::is_role_enabled( $role_name );

=head1 DESCRIPTION

This module provides additional utility functions to check the state of a role or profile that
are note needed in the base Cpanel::Server::Type::Profile.  In order to keep Cpanel::Server::Type::Profile
as small as possible they exist in this namespace

=head1 FUNCTIONS

=head2 is_role_enabled

A wrapper around a role’s module’s C<is_enabled()> method.

=over 2

=item Input

=over 3

=item C<SCALAR>

A string specifying the role to check, which should correspond to the name of
a module subclassing C<Cpanel::Server::Type::Role>. For example, C<MailReceive> as
input would correlate to the C<Cpanel::Server::Type::Role::MailReceive> module.

=back

=item Output

=over 3

=item C<SCALAR>

Returns 1 if the specified role is enabled, undef if not.

=back

=back

=cut

sub is_role_enabled {
    my ($role_to_check) = @_;
    return 1 if $Cpanel::Server::Type::Profile::ENABLED_IN_ALL_ROLES{$role_to_check};
    my $role = "Cpanel::Server::Type::Role::${role_to_check}";
    require Cpanel::LoadModule;
    Cpanel::LoadModule::load_perl_module($role) if !$INC{"Cpanel/Server/Type/Role/${role_to_check}.pm"};
    return $role->new()->is_enabled();
}

=head2 are_roles_enabled

Determines if a specified set of roles are enabled

=over 2

=item Input

=over 3

=item C<SCALAR> or  C<HASHREF> or C[LIST]

If the input is a C<SCALAR>, it is treated as a single role to check and this function's behavior is identical to C<is_role_enabled>

If the input is a C<HASHREF>, it should be in the form of:

    { match: <any|all>, roles: ["role1", "role2", … ] }

If the input is a C[LIST], it will call itself with a hashref

WHhere:

C<match> - (optional) Determines whether C<all> the roles must be enabled, or C<any> of them. If not specified, it defaults to C<all>.

C<roles> - An C<ARRAYREF> of role names to check

=back

=item Output

=over 3

Returns 1 if the roles are enabled, 0 otherwise

=back

=back

=cut

sub are_roles_enabled {
    my ($args) = @_;

    if ( 'HASH' eq ref $args ) {

        # Avoid altering the passed-in object.
        $args = { %$args, items => $args->{'roles'} };
        delete $args->{roles};
    }
    elsif ( scalar @_ > 1 ) {
        $args = { match => 'all', items => [@_] };
    }

    require Cpanel::Validate::AnyAllMatcher;
    return Cpanel::Validate::AnyAllMatcher::match( $args, \&is_role_enabled );
}

#----------------------------------------------------------------------

=head2 verify_roles_enabled( $ROLE_STR_OR_HR )

Throws L<Cpanel::Exception::System::RequiredRoleDisabled> if the given
argument returns falsy from C<are_roles_enabled()> above.

=cut

sub verify_roles_enabled {
    my ($role_str_or_hr) = @_;

    my @roles;

    if ( ref $role_str_or_hr ) {
        my @disabled = grep { !is_role_enabled($_) } @{ $role_str_or_hr->{'roles'} };

        my $match = _normalize_match_type( $role_str_or_hr->{match} );

        my $fail_yn;

        if ( $match eq 'all' ) {
            $fail_yn = !!@disabled;
        }
        else {
            $fail_yn = ( @disabled == @{ $role_str_or_hr->{'roles'} } );
        }

        if ($fail_yn) {
            die Cpanel::Exception::create( 'System::RequiredRoleDisabled', [ role => \@disabled ] );
        }
    }
    else {
        return 1 if $Cpanel::Server::Type::Profile::ENABLED_IN_ALL_ROLES{$role_str_or_hr};
        Cpanel::LoadModule::load_perl_module("Cpanel::Server::Type::Role::$role_str_or_hr")->verify_enabled();
    }

    return;
}

#----------------------------------------------------------------------

=head2 $yn = is_service_allowed( $SERVICE_NAME )

Determines if a service is allowed by the currently configured roles.

=cut

sub is_service_allowed {
    my ($svc_name) = @_;

    my @roles = _get_service_roles($svc_name);

    return 1 if !@roles;

    for my $role (@roles) {
        return 1 if Cpanel::LoadModule::load_perl_module("Cpanel::Server::Type::Role::$role")->is_enabled();
    }

    return 0;
}

=head2 $roles_hr = get_optional_roles_for_profile("PROFILE")

=over

=item Input

=over

=item $profile C<SCALAR>

    The profile to fetch the optional roles for.

=back

=item Output

=over

=item C<HASHREF>

    An hashref where the keys are the roles and the values are either 1 or undef to indicate whether the role is currently enabled.

=back

=back

=cut

sub get_optional_roles_for_profile {

    my ($profile) = @_;

    my $optional_roles = {};

    my $meta = Cpanel::Server::Type::Profile::get_meta();

    die Cpanel::Exception::create( "InvalidParameter", "Invalid server profile specified: “[_1]”.", [$profile] ) if !$meta->{$profile};

    if ( $meta->{$profile}{optional_roles} ) {
        foreach my $role ( @{ $meta->{$profile}{optional_roles} } ) {
            my $name = substr( $role, rindex( $role, ':' ) + 1 );
            $optional_roles->{$role} = is_role_enabled($name);
        }
    }

    return $optional_roles;
}

sub _normalize_match_type {
    my ($match) = @_;

    $match ||= _MATCH_DEFAULT();

    if ( $match ne 'any' && $match ne 'all' ) {
        require Cpanel::Exception;
        die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” parameter must be “[_2]” or “[_3]” value.', [qw(match any all)] );
    }

    return $match;
}

#=head2 @roles = _get_service_roles( $SERVICE_NAME )
#
#This looks up the roles that depend on $SERVICE_NAME and returns their
#names (e.g., C<Mail>).
#
#In scalar context, this returns the number of roles that would be returned
#in list context.
#
#cPanel-managed services that no role module “claims” will prompt an empty
#return.
#
#=cut
#
sub _get_service_roles {
    my ($svc_name) = @_;

    my $all_possible_roles = Cpanel::Server::Type::Profile::get_all_possible_roles();

    my @roles;

    require Cpanel::LoadModule;
    for my $role_module_name (@$all_possible_roles) {
        Cpanel::LoadModule::load_perl_module($role_module_name);

        if ( grep { $svc_name eq $_ } @{ $role_module_name->SERVICES() } ) {
            my $copy = $role_module_name;
            substr( $copy, 0, 1 + rindex( $copy, ':' ) ) = q<>;

            push @roles, $copy;
        }
    }

    return @roles;
}

#----------------------------------------------------------------------

1;
