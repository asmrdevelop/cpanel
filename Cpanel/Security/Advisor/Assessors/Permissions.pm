package Cpanel::Security::Advisor::Assessors::Permissions;

# cpanel - Cpanel/Security/Advisor/Assessors/Permissions.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::OS ();

use base 'Cpanel::Security::Advisor::Assessors';

sub generate_advice {
    my ($self) = @_;
    $self->_check_for_unsafe_permissions();

    return 1;
}

sub _check_for_unsafe_permissions {
    my ($self) = @_;

    my @allowed_shadow_gids = map { scalar getgrnam($_) } @{ Cpanel::OS::etc_shadow_groups() };

    my %test_files = (
        '/etc/shadow' => { 'perms' => Cpanel::OS::etc_shadow_perms(), 'uid' => 0, 'allowed_gids' => \@allowed_shadow_gids },
        '/etc/passwd' => { 'perms' => [0644],                         'uid' => 0, 'allowed_gids' => [0] }
    );

    for my $file ( keys %test_files ) {
        my $expected_attributes = $test_files{$file};
        my ( $current_mode, $uid, $gid ) = ( stat($file) )[ 2, 4, 5 ];
        my $perms_ok = 0;
        foreach my $allowed_perms ( @{ $expected_attributes->{'perms'} } ) {
            if ( ( $allowed_perms & 07777 ) == ( $current_mode & 07777 ) ) {
                $perms_ok = 1;
                last;
            }
        }
        if ( !$perms_ok ) {
            my $expected_mode = join( ' ', map { sprintf( '%04o', $_ ) } @{ $expected_attributes->{'perms'} } );
            my $actual_mode   = sprintf( "%04o", $current_mode & 07777 );
            $self->add_warn_advice(
                'key'        => q{Permissions_are_non_default},
                'text'       => $self->_lh->maketext( "[_1] has non default permissions. Expected: [_2], Actual: [_3].", $file, $expected_mode, $actual_mode ),
                'suggestion' => $self->_lh->maketext( "Review the permissions on [_1] to ensure they are safe", $file ),
            );
        }

        my $gid_is_allowed = grep { $_ eq $gid } @{ $expected_attributes->{'allowed_gids'} };

        if ( $uid != $expected_attributes->{'uid'} || !$gid_is_allowed ) {
            $self->add_warn_advice(
                'key'        => q{Permissions_has_non_root_users},
                'text'       => $self->_lh->maketext( "[_1] has non root user and/or group",      $file ),
                'suggestion' => $self->_lh->maketext( "Review the ownership permissions on [_1]", $file ),
            );
        }
    }

    return 1;
}

1;
