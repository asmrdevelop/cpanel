package Cpanel::CachedCommand::Save;

# cpanel - Cpanel/CachedCommand/Save.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::CachedCommand::Utils ();
use Cpanel::FileUtils::Write     ();
use Cpanel::Debug                ();
use Cpanel::Exception            ();

use Try::Tiny;

sub _savefile {
    my ( $filename, $content ) = @_;
    return if !defined $content;    #should be able to store 0

    $filename =~ tr{/}{}s;          # collapse //s to /
    my @path = split( /\//, $filename );
    my $file = pop(@path);
    my $dir  = join( '/', @path );

    my $dir_uid = ( stat($dir) )[4];

    if ( !defined $dir_uid ) {
        Cpanel::Debug::log_warn("Unable to write datastore file: $filename: target directory: $dir does not exist.");
        return;

    }
    elsif ( $dir_uid != $> ) {
        Cpanel::Debug::log_warn("Unable to write datastore file: $filename: target directory: $dir does not match uid $>");
        return;
    }

    local $!;
    my $ret;
    try {
        $ret = Cpanel::FileUtils::Write::overwrite( $filename, ( ref $content ? $$content : $content ), 0600 );
    }
    catch {
        my $err = $_;

        # Logger it but do not throw into the UI
        # We do not die here since its just a problem writing
        # the cache and that is not fatal (just slow)
        Cpanel::Debug::log_warn( Cpanel::Exception::get_string($err) );
    };

    return $ret;
}

sub store {
    my %OPTS = @_;
    _savefile( Cpanel::CachedCommand::Utils::_get_datastore_filename( $OPTS{'name'} ), $OPTS{'data'} );
}

1;
