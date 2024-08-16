package Cpanel::Team::Config::Fix;

# cpanel - Cpanel/Team/Config/Fix.pm               Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Team::Constants ();

sub fix_team_user {
    my ( $team_user, $opts ) = @_;

    my %field_check_for = (
        team_user_name => {
            min_length   => 1,
            max_length   => 16,
            invalid_char => qr(#\/\\\|=\(\)*&^\[\]\{\},<>),
            valid_char   => '',
            default      => undef,
            cannot_fix   => 1,
        },
        notes => {
            min_length   => 0,
            max_length   => 100,
            invalid_char => '',
            valid_char   => '',
            default      => sub { substr shift, 0, 100 },
            cannot_fix   => 0,
        },
        password => {
            min_length   => 80,
            max_length   => 200,
            invalid_char => '',
            valid_char   => '',
            default      => '!!',    # Forces user to reset password
            cannot_fix   => 0,
        },
        created => {
            min_length   => 10,
            max_length   => 10,
            invalid_char => qr(\D),
            valid_char   => qr([0-9]+),
            default      => time,
            cannot_fix   => 0,
        },
        contact_email => {
            min_length   => 6,
            max_length   => 255,
            invalid_char => '',      # TODO add email validation
            valid_char   => '',      # TODO add email validation
            default      => undef,
            cannot_fix   => 1,
        },
        secondary_contact_email => {
            min_length   => 0,
            max_length   => 255,
            invalid_char => '',      # TODO add email validation
            valid_char   => '',      # TODO add email validation
            default      => '',
            cannot_fix   => 0,
        },
        subacct_guid => {
            min_length   => 0,
            max_length   => 330,
            invalid_char => '',
            valid_char   => qr(.*:.*:.*:.*),    # It's decoded at this point.
            default      => '',
            cannot_fix   => 0,
        },
        locale => {
            min_length   => 0,
            max_length   => 20,
            invalid_char => '',
            valid_char   => qr/^[a-z\d_-]*$/i,
            default      => '',
            cannot_fix   => 0,
        },
        tfa => {
            min_length   => 0,
            max_length   => 0,
            invalid_char => qr/./s,
            valid_char   => '',
            default      => '',
            cannot_fix   => 0,
        },
        suspend => {
            min_length   => 0,
            max_length   => 10,
            invalid_char => qr(\D),
            valid_char   => qr([0-9]+),
            default      => '',
            cannot_fix   => 0,
        },
        suspend_date => {
            min_length   => 0,
            max_length   => 10,
            invalid_char => qr(\D),
            valid_char   => qr([0-9]+),
            default      => '',
            cannot_fix   => 0,
        },
        suspend_reason => {
            min_length   => 0,
            max_length   => 100,
            invalid_char => '',
            valid_char   => '',
            default      => sub { substr shift, 0, 100 },
            cannot_fix   => 0,
        },
        expire_date => {
            min_length   => 0,
            max_length   => 10,
            invalid_char => qr(\D),
            valid_char   => qr(^\d+$),
            default      => '',
            cannot_fix   => 0,
        },
        expire_reason => {
            min_length   => 0,
            max_length   => 100,
            invalid_char => '',
            valid_char   => '',
            default      => sub { substr shift, 0, 100 },
            cannot_fix   => 0,
        },
    );

    foreach my $field ( sort keys %$team_user ) {
        if ( $field eq 'roles' ) {
            my @valid_roles = ();

            # Up to v1.0 all roles are valid in all versions.  If a role is
            # created in a future version that is not valid in an older
            # version, then here's where that needs to be handled.
            foreach my $role ( @{ $team_user->{roles} } ) {
                if ( $role && exists $Cpanel::Team::Constants::TEAM_ROLES{$role} && $role ne 'default' ) {
                    push @valid_roles, $role;
                }
                else {
                    print STDERR "Removing unknown role '$role'.\n" if $opts->{verbose};
                }
            }
            $team_user->{$field} = \@valid_roles;
            next;
        }
        if ( !ref $team_user->{$field} && length $team_user->{$field} < $field_check_for{$field}{min_length} ) {

            if ( _check_cannot_fix( $field_check_for{$field}, $field, $team_user, $opts ) ) {
                $team_user = undef if $opts->{remove};
                return $team_user;
            }
            if ( $field eq 'password' ) {
                if ( $team_user->{$field} !~ /^!!/ ) {
                    print STDERR "Invalid password.  Reset password to re-enable locked account.\n" if $opts->{verbose};
                }
            }
            else {
                print STDERR "Using default for $field because it is too short.\n" if $opts->{verbose};
            }
            $team_user->{$field} = $field_check_for{$field}{default};
        }
        elsif ( !ref $team_user->{$field} && length $team_user->{$field} > $field_check_for{$field}{max_length} ) {

            if ( _check_cannot_fix( $field_check_for{$field}, $field, $team_user, $opts ) ) {
                $team_user = undef if $opts->{remove};
                return $team_user;
            }
            print STDERR "Using default for $field because it is too long.\n" if $opts->{verbose};
            $team_user->{$field} = ref $field_check_for{$field}{default} eq 'CODE' ? &{ $field_check_for{$field}{default} }( $team_user->{$field} ) : $field_check_for{$field}{default};
        }
        elsif (
              !ref $team_user->{$field}
            && length $team_user->{$field} > 0
            && (   ( $field_check_for{$field}{invalid_char} && $team_user->{$field} =~ /$field_check_for{$field}{invalid_char}/ )
                || ( $field_check_for{$field}{valid_char} && $team_user->{$field} !~ /$field_check_for{$field}{valid_char}/ ) )
        ) {
            if ( defined $field_check_for{$field}{default} ) {

                print STDERR "Using default for $field because it contains invalid character.\n" if $opts->{verbose};
                $team_user->{$field} = $field_check_for{$field}{default};
            }
        }
    }
    return $team_user;
}

sub _check_cannot_fix {
    my ( $field_specs, $field, $team_user, $opts ) = @_;

    if ( $field_specs->{cannot_fix} ) {
        my $error = "Team user '$team_user->{team_user_name}' has '$field' value of '$team_user->{$field}' that cannot be fixed.";
        die "$error  Cannot continue.\n" if !$opts->{remove};
        return 1;
    }
    return 0;
}

1;
