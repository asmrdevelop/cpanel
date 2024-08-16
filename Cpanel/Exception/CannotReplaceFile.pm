package Cpanel::Exception::CannotReplaceFile;

# cpanel - Cpanel/Exception/CannotReplaceFile.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception );

use Cpanel::LocaleString ();

#Parameters:
#   pid
#   euid
#   egid
#   fs_uid
#   fs_gid
#   path    (optional)
#
sub _default_phrase {
    my ($self) = @_;

    if ( length $self->get('path') ) {
        return Cpanel::LocaleString->new(
            'Process “[_1]” ([asis,EUID] “[_2]”, [asis,EGID] “[_3]”) cannot replace “[_4]” because this file has [asis,UID] “[_5]” and [asis,GID] “[_6]”.',
            ( map { $self->get($_) } qw( pid euid egid path fs_uid fs_gid ) ),
        );
    }

    return Cpanel::LocaleString->new(
        'Process “[_1]” ([asis,EUID] “[_2]”, [asis,EGID] “[_3]”) cannot replace a file with [asis,UID] “[_4]” and [asis,GID] “[_5]”.',
        ( map { $self->get($_) } qw( pid euid egid fs_uid fs_gid ) ),
    );
}

1;
