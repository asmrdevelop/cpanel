#!/usr/local/cpanel/3rdparty/bin/perl

use strict;
use warnings;

use Cpanel::ConfigFiles::Apache ();
use Cpanel::Logd::Dynamic       ();

my $apacheconf = Cpanel::ConfigFiles::Apache->new();

Cpanel::Logd::Dynamic::whm_cgi_app(
    {
        'defheader_uri' => '/scripts2/displayapachesetup',
        'path'          => $apacheconf->dir_logs(),
        'name'          => 'Apache',
        'prefix'        => '_apache_',
        'ignore'        => {
            'modsec_audit.log' => 'This is parsed and rotated via the TailWatch system.',
        },
    }
);
