package Cpanel::Config;

# cpanel - Cpanel/Config.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::Services        ();
use Cpanel::Config::Sources         ();
use Cpanel::Config::LoadCpUserFile  ();
use Cpanel::Config::ModCpUserFile   ();
use Cpanel::Config::LoadUserOwners  ();
use Cpanel::Config::LoadCpConf      ();
use Cpanel::Config::LoadConfig      ();
use Cpanel::Config::LocalDomains    ();
use Cpanel::Config::FlushConfig     ();
use Cpanel::Config::Httpd::EA4      ();
use Cpanel::Config::Hulk::Load      ();
use Cpanel::Config::Httpd::IpPort   ();
use Cpanel::Config::Users           ();
use Cpanel::Config::LoadWwwAcctConf ();
use Cpanel::Config::LoadUserDomains ();
use Cpanel::Config::Hulk::Conf      ();
use Cpanel::Config::Contact         ();

$Cpanel::Config::VERSION = '2.3';

# Refactored sub routines
*service_enabled      = *Cpanel::Config::Services::service_enabled;
*loadcpuserfile       = *Cpanel::Config::LoadCpUserFile::loadcpuserfile;
*adddomaintouser      = *Cpanel::Config::ModCpUserFile::adddomaintouser;
*removedomainfromuser = *Cpanel::Config::ModCpUserFile::removedomainfromuser;
*loadcpsources        = *Cpanel::Config::Sources::loadcpsources;
*loadcphulkconf       = *Cpanel::Config::Hulk::Load::loadcphulkconf;
*savecphulkconf       = *Cpanel::Config::Hulk::Conf::savecphulkconf;
*loadwwwacctconf      = *Cpanel::Config::LoadWwwAcctConf::loadwwwacctconf;
*get_server_contact   = *Cpanel::Config::Contact::get_server_contact;
*get_public_contact   = *Cpanel::Config::Contact::get_public_contact;
*get_server_pager     = *Cpanel::Config::Contact::get_server_pager;
*loadtrueuserdomains  = *Cpanel::Config::LoadUserDomains::loadtrueuserdomains;
*loaduserdomains      = *Cpanel::Config::LoadUserDomains::loaduserdomains;
*loadConfig           = *Cpanel::Config::LoadConfig::loadConfig;
*flushConfig          = *Cpanel::Config::FlushConfig::flushConfig;
*_hashify_ref         = *Cpanel::Config::LoadConfig::_hashify_ref;
*loadcpconf           = *Cpanel::Config::LoadCpConf::loadcpconf;
*get_main_httpd_port  = *Cpanel::Config::Httpd::IpPort::get_main_httpd_port;
*get_ssl_httpd_port   = *Cpanel::Config::Httpd::IpPort::get_ssl_httpd_port;
*is_ea4               = *Cpanel::Config::Httpd::EA4::is_ea4;
*getcpusers           = *Cpanel::Config::Users::getcpusers;
*loadtrueuserowners   = *Cpanel::Config::LoadUserOwners::loadtrueuserowners;
*loadlocaldomains     = *Cpanel::Config::LocalDomains::loadlocaldomains;

sub loadbackupconf {
    require Cpanel::Config::Backup;
    goto &Cpanel::Config::Backup::load;
}

sub savebackupconf {
    require Cpanel::Config::Backup;
    goto &Cpanel::Config::Backup::save;
}

sub loaduserdomains_normal {
    return Cpanel::Config::LoadUserDomains::loaduserdomains( undef, 1 );
}

1;
