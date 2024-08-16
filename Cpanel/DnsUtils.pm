package Cpanel::DnsUtils;

# cpanel - Cpanel/DnsUtils.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::DnsUtils::Config    ();
use Cpanel::DnsUtils::Remove    ();
use Cpanel::DnsUtils::List      ();
use Cpanel::DnsUtils::Add       ();
use Cpanel::DnsUtils::UpdateIps ();
use Cpanel::DnsUtils::Exists    ();
use Cpanel::DnsUtils::Template  ();

our $VERSION = 3.1;

*find_zonedir    = *Cpanel::DnsUtils::Config::find_zonedir;
*usenamedjail    = *Cpanel::DnsUtils::Config::usenamedjail;
*removezone      = *Cpanel::DnsUtils::Remove::removezone;
*dokilldns       = *Cpanel::DnsUtils::Remove::dokilldns;
*doadddns        = *Cpanel::DnsUtils::Add::doadddns;
*getzonetemplate = *Cpanel::DnsUtils::Template::getzonetemplate;
*listzones       = *Cpanel::DnsUtils::List::listzones;
*updatemasterips = *Cpanel::DnsUtils::UpdateIps::updatemasterips;
*domainexists    = *Cpanel::DnsUtils::Exists::domainexists;

1;
