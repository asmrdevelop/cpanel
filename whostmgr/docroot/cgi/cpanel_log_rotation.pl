#!/usr/local/cpanel/3rdparty/bin/perl

use strict;
use warnings;

use Cpanel::Logd::Dynamic ();

Cpanel::Logd::Dynamic::whm_cgi_app(
    {
        'path' => '/usr/local/cpanel/logs',
        'name' => 'cPanel',
    }
);
