
# cpanel - Cpanel/Quota/Utils.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Quota::Utils;

use strict;
use warnings;

sub has_effective_limit {
    my ( $limits, $types_ar ) = @_;

    $types_ar ||= [ 'block', 'inode' ];

    for my $device_limits ( values %$limits ) {
        for my $type (@$types_ar) {
            my $type_type_hr = $device_limits->{$type};
            return 1 if $type_type_hr->{'soft'} || $type_type_hr->{'hard'};
        }
    }
    return 0;
}

sub has_usage {
    my ($limits) = @_;

    for my $path ( keys %$limits ) {
        for my $type ( keys %{ $limits->{$path} } ) {
            return 1 if $limits->{$path}{$type}{'blocks'} || $limits->{$path}{$type}{'inodes'};
        }
    }
    return 0;
}

sub reboot_required {
    return -e '/var/cpanel/reboot_required_for_quota' ? 1 : 0;
}

# TODO: Move broken quota detection into its own module?

sub quota_broken {
    return -e '/var/cpanel/quota_broken' ? 1 : 0;
}

1;

__END__

=head1 NAME

Cpanel::Quota::Utils - Quota utility functions

=head1 DESCRIPTION

Quota utility functions

=head1 FUNCTIONS

=head2 C<< has_effective_limit($limits) >>

Check if the user has any limits, whatsoever.

=over

=item C<$limits> [in, required]

The limits data, as returned by C<< Cpanel::Quota::Common->get_limits() >>.

=back

B<Returns:> 1 if user has limits; 0 otherwise.

=head2 C<< has_usage($limits) >>

Check if the user has any disk usage, whatsoever.

=over

=item C<$limits> [in, required]

The limits data, as returned by C<< Cpanel::Quota::Common->get_limits() >>.

=back

B<Returns:> 1 if user has disk usage; 0 otherwise.

=head2 C<< reboot_required() >>

Check if the system needs a reboot for quotas to work.

Some filesystems, like XFS, require a reboot before the quota system will start running.

B<Returns:> 1 if the system needs a reboot, 0 otherwise.

=cut
