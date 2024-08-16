package Whostmgr::XMLUI::Docs;

# cpanel - Whostmgr/XMLUI/Docs.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Whostmgr::Docs       ();
use Whostmgr::ApiHandler ();

sub fetch_doc_key {
    my $ref = shift;
    return Whostmgr::ApiHandler::out(
        {

            'doc' => scalar Whostmgr::Docs::fetch_key(
                $ref->{'module'},
                $ref
            ),
        },
        RootName => 'fetch_doc_key',
        NoAttr   => 1
    );

}

1;
