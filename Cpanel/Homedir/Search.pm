package Cpanel::Homedir::Search;

# cpanel - Cpanel/Homedir/Search.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Homedir::Search

=head1 SYNOPSIS

    my $used_yn = Cpanel::Homedir::Search::is_used( '/maybe/a/homedir' );

=head1 DESCRIPTION

This module exposes logic to search (potential) homedirs.

=cut

#----------------------------------------------------------------------

use Cpanel::Path::Normalize ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $user_reldir = get_users( $HOMEDIR_BASE )

Returns a hashref that represents user home directories that exist under
$HOMEDIR_BASE.

For example, if C<bob>’s home directory is C</usr/home/bob>, and
$HOMEDIR_BASE is C</usr>, then ( C<bob> => C<home/bob> ) will be in
the returned hashref.

C<is_used()> returns falsy if and only if C<get_users()> returns an
empty hashref.

=cut

sub get_users ($homedir_base) {
    return _do_cr(
        $homedir_base,
        sub ($norm_homedir_base) {
            my %user_homedir;

            while ( my @ent = getpwent ) {
                my $ent_homedir = Cpanel::Path::Normalize::normalize( $ent[7] );

                if ( rindex( $ent_homedir, $norm_homedir_base, 0 ) == 0 ) {
                    $user_homedir{ $ent[0] } = substr( $ent_homedir, length $norm_homedir_base );
                }
            }

            return \%user_homedir;
        },
    );
}

=head2 $yn = is_used( $HOMEDIR_BASE )

A slightly-optimized version of C<get_users()> that returns a simple
boolean instead of the full hashref. This returns falsy if and only if
C<get_users()> would return an empty hashref.

=cut

sub is_used ($homedir_base) {
    return _do_cr(
        $homedir_base,
        sub ($norm_homedir_base) {
            while ( my @ent = getpwent ) {
                return 1 if rindex( $ent[7], $norm_homedir_base, 0 ) == 0;
            }

            return 0;
        },
    );
}

sub _do_cr ( $homedir_base, $cr ) {
    local $!;

    $homedir_base = Cpanel::Path::Normalize::normalize($homedir_base);
    $homedir_base .= '/';

    # Simple optimization: don’t load the shadow stuff since
    # we don’t need it.
    #
    local $> = 1 if !$>;

    setpwent;

    return $cr->($homedir_base);
}

1;
