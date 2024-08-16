package Whostmgr::Accounts;

# cpanel - Whostmgr/Accounts.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Whostmgr::Accounts::List ();

*_listaccts    = *Whostmgr::Accounts::List::listaccts;
*getlockedlist = *Whostmgr::Accounts::List::getlockedlist;
*listsuspended = *Whostmgr::Accounts::List::listsuspended;
*search        = *Whostmgr::Accounts::List::search;

1;
