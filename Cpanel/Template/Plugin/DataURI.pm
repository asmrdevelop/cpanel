package Cpanel::Template::Plugin::DataURI;

# cpanel - Cpanel/Template/Plugin/DataURI.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use base 'Template::Plugin';

use strict;
use warnings;

use Cpanel::App           ();
use Cpanel::DataURI       ();
use Cpanel::Debug         ();
use Cpanel::MagicRevision ();

my %cached_datauri;

sub DEFAULT_MIME_TYPE { 'application/octet-stream' }

sub datauri {
    my ( undef, $url, $mime_type ) = @_;

    return if index( $url, '..' ) > -1;

    $url = ( split( m{\?}, $url ) )[0];
    $url =~ s{(?:/cpsess\d*)?}{}g;
    $url =~ s{/+$Cpanel::MagicRevision::MAGIC_PREFIX[\.\d]+/+}{/}go;

    $mime_type ||= DEFAULT_MIME_TYPE();

    my $docroot = (
        ( index( $Cpanel::App::appname, 'whostmgr' ) > -1 && $Cpanel::App::context ne 'unauthenticated' )
        ? '/usr/local/cpanel/whostmgr/docroot'
        : '/usr/local/cpanel/base'
    );

    my $path;
    if ( index( $url, '/' ) == 0 ) {
        $path = $docroot . $url;
    }
    else {
        my $req_uri = $ENV{'REQUEST_URI'};
        $req_uri =~ s{[^/]*\z}{};
        $path = "$docroot/$req_uri/$url";
    }

    $path =~ tr{/}{}s;

    if ( $cached_datauri{$mime_type}{$path} ) {
        return ${ $cached_datauri{$mime_type}{$path} };
    }
    elsif ( open my $bfh, '<', $path ) {
        $cached_datauri{$mime_type}{$path} = \Cpanel::DataURI::create_from_fh( $mime_type, $bfh );
        return ${ $cached_datauri{$mime_type}{$path} };
    }
    else {
        Cpanel::Debug::log_warn("Could not open file $path for base64 encoding: $!");
    }

    return;
}

1;
