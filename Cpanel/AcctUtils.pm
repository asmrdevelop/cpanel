package Cpanel::AcctUtils;

# cpanel - Cpanel/AcctUtils.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::PwCache                      ();
use Cpanel::PwCache::Get                 ();
use Cpanel::AccessIds::SetUids           ();
use Cpanel::AcctUtils::Account           ();
use Cpanel::AcctUtils::DomainOwner       ();
use Cpanel::AcctUtils::Load              ();
use Cpanel::AcctUtils::Domain            ();
use Cpanel::AcctUtils::DomainOwner::Tiny ();

*getshell           = *Cpanel::PwCache::Get::getshell;
*gethomedir         = *Cpanel::PwCache::gethomedir;
*loadaccountcache   = *Cpanel::AcctUtils::Load::loadaccountcache;
*accountexists      = *Cpanel::AcctUtils::Account::accountexists;
*getdomain          = *Cpanel::AcctUtils::Domain::getdomain;
*setuids            = *Cpanel::AccessIds::SetUids::setuids;
*getdomainowner     = *Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner;
*gettruedomainowner = *Cpanel::AcctUtils::DomainOwner::gettruedomainowner;

1;
