
# cpanel - Cpanel/ImagePrep/Check/remotemysql.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::ImagePrep::Check::remotemysql;

use cPstrict;
use parent 'Cpanel::ImagePrep::Check';
use Cpanel::MysqlUtils::RemoteMySQL::ProfileManager ();
use Cpanel::IP::Loopback                            ();

=head1 NAME

Cpanel::ImagePrep::Check::remotemysql - A subclass of C<Cpanel::ImagePrep::Check>.

=cut

sub _description {
    return <<EOF;
Check whether a remote MySQL profile is set up.
EOF
}

sub _check ($self) {
    my $profiles = Cpanel::MysqlUtils::RemoteMySQL::ProfileManager->new->read_profiles;
    for my $profile_name ( keys %$profiles ) {    # could be localhost with a non-default profile name
        delete $profiles->{$profile_name}
          if Cpanel::IP::Loopback::is_loopback( $profiles->{$profile_name}{mysql_host} );
    }

    if (%$profiles) {
        die <<EOF;
You have a remote MySQL profile. This is not a supported configuration for template VMs.

Remote MySQL profile(s):
@{[join "\n", map { "  - $_ ($profiles->{$_}{mysql_user}\@$profiles->{$_}{mysql_host})" } sort keys %$profiles]}
EOF
    }
    $self->loginfo('No remote MySQL profiles');
    return;
}

1;
