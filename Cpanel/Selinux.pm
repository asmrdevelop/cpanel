package Cpanel::Selinux;

# cpanel - Cpanel/Selinux.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Selinux - SELinux controls

=cut

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 is_enabled()

Check if SeLinux is enabled.
Returns a boolean, 'true' when enabled.

=cut

sub is_enabled() {
    my $config = '/etc/selinux/config';
    if ( open( my $fh, '<', $config ) ) {
        while ( my $line = <$fh> ) {
            next if $line =~ m{^\s*#};
            if ( $line =~ /^\s*SELINUX\s*=\s*(?:enforcing|permissive)\b/i ) {
                return 1;
            }
        }
        close($fh);
    }
    return 0;
}

=head2 set_context( $CONTEXT, @FILES )

Sets SELinux context $CONTEXT on @FILES. Throws an exception if
the C<chcon> utility is unavailable or if it fails.

=cut

sub set_context ( $context, @files ) {

    return unless is_enabled();

    require File::Which;
    my $cmd = File::Which::which('chcon') or    #
      die "Can’t set SELinux context “$context” on [@files]: system lacks “chcon”.";

    require Cpanel::SafeRun::Object;
    Cpanel::SafeRun::Object->new_or_die(
        program => $cmd,
        args    => [ $context, @files ],
    );

    return;
}

1;
