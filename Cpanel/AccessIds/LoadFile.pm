package Cpanel::AccessIds::LoadFile;

# cpanel - Cpanel/AccessIds/LoadFile.pm                       Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::AccessIds::Normalize         ();
use Cpanel::AccessIds::ReducedPrivileges ();
use Cpanel::LoadFile                     ();

=encoding utf-8

=head1 NAME

Cpanel::AccessIds::LoadFile - Load files as a user

=head1 SYNOPSIS

    use Cpanel::AccessIds::LoadFile;

    my $contents = Cpanel::AccessIds::LoadFile::loadfile_as_user($user, $path);

=head2 loadfile_as_user( $USERNAME, $PATH )

Load a file as the given user. Returns the contents, or undef if the file does
not exist. An exception is thrown if the file exists but for whatever reason
cannot be read.

This may be used to ensure that filesystem permissions are respected when
loading a file on behalf of an unprivileged user.

=cut

sub loadfile_as_user {
    my ( $user, $path ) = @_;
    my ( $uid,  $gid )  = Cpanel::AccessIds::Normalize::normalize_user_and_groups($user);
    my $privs = $uid == $> ? undef : Cpanel::AccessIds::ReducedPrivileges->new( $uid, $gid );
    return Cpanel::LoadFile::load_if_exists($path);
}

1;
