package Whostmgr::XMLUI::Meta;

# cpanel - Whostmgr/XMLUI/Meta.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# XXX: This module contains the dispatch layer for WHM API v0. This API
# version is FROZEN and is not to be changed: neither new functionality
# added nor existing functionality altered/removed.
#----------------------------------------------------------------------

use strict;
use warnings;

use Whostmgr::ACLS     ();
use Cpanel::Context    ();
use Cpanel::LoadModule ();

#Exposed for tests
our %_APPLIST = (
    'listaccts' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::Accounts;
            Whostmgr::XMLUI::Accounts::listaccts(
                'search'       => $args->{'search'},
                'searchtype'   => $args->{'searchtype'},
                'searchmethod' => $args->{'searchmethod'},
                'want'         => $args->{'want'},
            );
        },
        'check' => sub {
            return Whostmgr::ACLS::xml_checkacl('list-accts');
        },
        needs_role => undef,
    ],
    'domainuserdata' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::Accounts;
            Whostmgr::XMLUI::Accounts::domainuserdata(%$args);
        },
        'check' => sub {
            my $args = shift;
            return 1 if Whostmgr::ACLS::hasroot();
            return 0 if !Whostmgr::ACLS::checkacl('acct-summary');
            return _owns_account_with_domain( $args->{'domain'} );
        },
        needs_role => undef,
    ],
    'unfreeze_messages_mail_queue' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::Exim;
            Whostmgr::XMLUI::Exim::unfreeze_messages_mail_queue($args);
        },
        'check' => sub {
            return Whostmgr::ACLS::hasroot();
        },
        needs_role => 'MailSend',
    ],
    'deliver_messages_mail_queue' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::Exim;
            Whostmgr::XMLUI::Exim::deliver_messages_mail_queue($args);
        },
        'check' => sub {
            return Whostmgr::ACLS::hasroot();
        },
        needs_role => 'MailSend',
    ],
    'remove_messages_mail_queue' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::Exim;
            Whostmgr::XMLUI::Exim::remove_messages_mail_queue($args);
        },
        'check' => sub {
            return Whostmgr::ACLS::hasroot();
        },
        needs_role => 'MailSend',
    ],
    'purge_mail_queue' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::Exim;
            Whostmgr::XMLUI::Exim::purge_mail_queue($args);
        },
        'check' => sub {
            return Whostmgr::ACLS::hasroot();
        },
        needs_role => 'MailSend',
    ],
    'remove_in_progress_exim_config_edit' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::Exim;
            Whostmgr::XMLUI::Exim::remove_in_progress_exim_config_edit($args);
        },
        'check' => sub {
            return Whostmgr::ACLS::hasroot();
        },
        needs_role => undef,
    ],
    'exim_configuration_check' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::Exim;
            Whostmgr::XMLUI::Exim::exim_configuration_check($args);
        },
        'check' => sub {
            return Whostmgr::ACLS::hasroot();
        },
        needs_role => undef,
    ],
    'validate_current_installed_exim_config' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::Exim;
            Whostmgr::XMLUI::Exim::validate_current_installed_exim_config($args);
        },
        'check' => sub {
            return Whostmgr::ACLS::hasroot();
        },
        needs_role => undef,
    ],

    'validate_exim_configuration_syntax' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::Exim;
            Whostmgr::XMLUI::Exim::validate_exim_configuration_syntax($args);
        },
        'check' => sub {
            return Whostmgr::ACLS::hasroot();
        },
        needs_role => undef,
    ],

    'deliver_mail_queue' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::Exim;
            Whostmgr::XMLUI::Exim::deliver_mail_queue($args);
        },
        'check' => sub {
            return Whostmgr::ACLS::hasroot();
        },
        needs_role => 'MailSend',
    ],
    'fetch_doc_key' => [

        # legacy method : do not make sense to convert it to API v1
        #   as format depends on Module, section, key... and can be in html...
        #   we should answer a clean json output with fixed / predictabled keys
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::Docs;
            Whostmgr::XMLUI::Docs::fetch_doc_key($args);
        },
        'check' => sub {
            return Whostmgr::ACLS::hasroot();
        },
        needs_role => undef,
    ],
    'nvget' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::NVData;
            Whostmgr::XMLUI::NVData::nvget( $args->{'key'}, $args->{'stor'} );
        },
        'check' => sub {
            return Whostmgr::ACLS::checkacl('basic-whm-functions');
        },
        needs_role => undef,
    ],
    'nvset' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::NVData;
            Whostmgr::XMLUI::NVData::nvset(%$args);
        },
        'check' => sub {
            return Whostmgr::ACLS::checkacl('basic-whm-functions');
        },
        needs_role => undef,
    ],
    'myprivs' => [
        'code' => sub {
            require Whostmgr::XMLUI::ACLS;
            Whostmgr::XMLUI::ACLS::myprivs();
        },
        'check' => sub {
            return Whostmgr::ACLS::checkacl('basic-whm-functions');
        },
        needs_role => undef,
    ],
    'listzones' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::DNS;
            Whostmgr::XMLUI::DNS::listzones(%$args);
        },
        'check' => sub {
            return Whostmgr::ACLS::checkacl('manage-dns-records');
        },
        needs_role => undef,
    ],
    'sethostname' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::Hostname;
            Whostmgr::XMLUI::Hostname::sethostname(%$args);
        },
        'check' => sub {
            return Whostmgr::ACLS::hasroot();
        },
        needs_role => undef,
    ],
    'setresolvers' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::Resolvers;
            Whostmgr::XMLUI::Resolvers::setresolvers(%$args);
        },
        'check' => sub {
            return Whostmgr::ACLS::hasroot();
        },
        needs_role => undef,
    ],
    'addip' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::Ips;
            Whostmgr::XMLUI::Ips::addip(%$args);
        },
        'check' => sub {
            return Whostmgr::ACLS::hasroot();
        },
        needs_role => undef,
    ],
    'delip' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::Ips;
            Whostmgr::XMLUI::Ips::delip(%$args);
        },
        'check' => sub {
            return Whostmgr::ACLS::hasroot();
        },
        needs_role => undef,
    ],
    'listips' => [
        'code' => sub {
            require Whostmgr::XMLUI::Ips;
            Whostmgr::XMLUI::Ips::listips();
        },
        'check' => sub {
            return Whostmgr::ACLS::hasroot();
        },
        needs_role => undef,
    ],
    'setsiteip' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::Accounts;
            Whostmgr::XMLUI::Accounts::setsiteip(%$args);
        },
        'check' => sub {
            return Whostmgr::ACLS::hasroot();
        },
        needs_role => 'WebServer',
    ],
    'dumpzone' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::DNS;
            Whostmgr::XMLUI::DNS::dumpzone(%$args);
        },
        'check' => sub {
            return Whostmgr::ACLS::checkacl('manage-dns-records');
        },
        needs_role => 'DNS',
    ],
    'listpkgs' => [
        'code' => sub {
            require Whostmgr::XMLUI::Packages;
            Whostmgr::XMLUI::Packages::listpkgs();
        },
        'check' => sub {
            return Whostmgr::ACLS::checkacl('list-pkgs');
        },
        needs_role => undef,
    ],
    'limitbw' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::Bandwidth;
            Whostmgr::XMLUI::Bandwidth::limitbw(%$args);
        },
        'check' => sub {
            my $args = shift;
            return if !_owns_account( $args->{'user'} );
            return Whostmgr::ACLS::xml_checkacl('limit-bandwidth');
        },
        needs_role => undef,
    ],
    'showbw' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::Bandwidth;
            Whostmgr::XMLUI::Bandwidth::showbw(%$args);
        },
        'check' => sub {
            return Whostmgr::ACLS::xml_checkacl('show-bandwidth');
        },
        needs_role => undef,
    ],
    'killdns' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::DNS;
            Whostmgr::XMLUI::DNS::killdns(%$args);
        },
        'check' => sub {
            my $args = shift;
            return 1 if Whostmgr::ACLS::hasroot();
            return 0 if !Whostmgr::ACLS::xml_checkacl('kill-dns');
            return 1 if _owns_domain( $args->{'domain'} );
            return _owns_account_with_domain( $args->{'domain'} );
        },
        needs_role => 'DNS',
    ],
    'adddns' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::DNS;
            if ( !exists $args->{'trueowner'} ) {
                $args->{'trueowner'} = $ENV{'REMOTE_USER'};
            }
            Whostmgr::XMLUI::DNS::adddns(%$args);
        },
        'check' => sub {
            my $args = shift;
            return 1 if Whostmgr::ACLS::hasroot();
            return 0 if !Whostmgr::ACLS::xml_checkacl('create-dns');
            return !exists $args->{'trueowner'} || _owns_account( $args->{'trueowner'} );
        },
        needs_role => 'DNS',
    ],
    'getzonerecord' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::DNS;
            return Whostmgr::XMLUI::DNS::getzonerecord(%$args);
        },
        'check' => sub {
            my $args = shift;
            return 1 if Whostmgr::ACLS::hasroot();
            return 0 if !Whostmgr::ACLS::checkacl('manage-dns-records');
            my $domain = _domain_or_zone_from_args($args);
            return _owns_account_with_domain($domain);
        },
        needs_role => 'DNS',
    ],
    'resetzone' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::DNS;
            return Whostmgr::XMLUI::DNS::resetzone(%$args);
        },
        'check' => sub {
            my $args = shift;
            return 1 if Whostmgr::ACLS::hasroot();
            return 0 if !Whostmgr::ACLS::checkacl('manage-dns-records');
            my $domain = _domain_or_zone_from_args($args);
            return _owns_account_with_domain($domain);
        },
        needs_role => 'DNS',
    ],
    'addzonerecord' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::DNS;
            return Whostmgr::XMLUI::DNS::addzonerecord(%$args);
        },
        'check' => sub {
            my $args = shift;
            return 1 if Whostmgr::ACLS::hasroot();
            return 0 if !Whostmgr::ACLS::checkacl('manage-dns-records');
            my $domain = _domain_or_zone_from_args($args);
            return _owns_account_with_domain($domain);
        },
        needs_role => 'DNS',
    ],
    'editzonerecord' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::DNS;
            return Whostmgr::XMLUI::DNS::editzonerecord(%$args);
        },
        'check' => sub {
            my $args = shift;
            return 1 if Whostmgr::ACLS::hasroot();
            return 0 if !Whostmgr::ACLS::checkacl('manage-dns-records');
            my $domain = _domain_or_zone_from_args($args);
            return _owns_account_with_domain($domain);
        },
        needs_role => 'DNS',
    ],
    'removezonerecord' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::DNS;
            return Whostmgr::XMLUI::DNS::removezonerecord(%$args);
        },
        'check' => sub {
            my $args = shift;
            return 1 if Whostmgr::ACLS::hasroot();
            return 0 if !Whostmgr::ACLS::checkacl('manage-dns-records');
            my $domain = _domain_or_zone_from_args($args);
            return _owns_account_with_domain($domain);
        },
        needs_role => 'DNS',
    ],
    'changepackage' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::Accounts;
            Whostmgr::XMLUI::Accounts::changepackage(%$args);
        },
        'check' => sub {
            return Whostmgr::ACLS::xml_checkacl('upgrade-account');
        },
        needs_role => undef,
    ],
    'modifyacct' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::Accounts;
            Whostmgr::XMLUI::Accounts::modifyacct(%$args);
        },
        'check' => sub {
            my $args = shift;
            return 1 if Whostmgr::ACLS::hasroot();
            return   if !Whostmgr::ACLS::xml_checkacl('edit-account');
            return _owns_account( $args->{'user'} );
        },
        needs_role => undef,
    ],
    'createacct' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::Accounts;
            Whostmgr::XMLUI::Accounts::createacct(%$args);
        },
        'check' => sub {
            my $args = shift;
            return 1 if Whostmgr::ACLS::hasroot();
            return 0 if ( $args->{'force'} || $args->{'forcedns'} || $args->{'is_restore'} );
            return 0 if !Whostmgr::ACLS::xml_checkacl('create-acct');
            return !$args->{'owner'} || $args->{'owner'} eq $ENV{'REMOTE_USER'};
        },
        needs_role => undef,
    ],
    'removeacct' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::Accounts;
            Whostmgr::XMLUI::Accounts::removeacct(%$args);
        },
        'check' => sub {
            my $args = shift;
            return 1 if Whostmgr::ACLS::hasroot();
            return   if !Whostmgr::ACLS::xml_checkacl('kill-acct');
            return _owns_account( $args->{'user'} );
        },
        needs_role => undef,
    ],
    'suspendacct' => [
        'code' => sub {
            my $args = shift;

            require Whostmgr::XMLUI::Accounts;
            Whostmgr::XMLUI::Accounts::suspendacct(
                'user'       => $args->{'user'},
                'reason'     => $args->{'reason'},
                'disallowun' => $args->{'disallowun'},
            );
        },
        'check' => sub {
            my $args = shift;
            return 1 if Whostmgr::ACLS::hasroot();
            return   if !Whostmgr::ACLS::xml_checkacl('suspend-acct');
            return _owns_account( $args->{'user'} );
        },
        needs_role => undef,
    ],
    'unsuspendacct' => [
        'code' => sub {

            require Whostmgr::XMLUI::Accounts;
            my $args = shift;
            Whostmgr::XMLUI::Accounts::unsuspendacct( 'user' => $args->{'user'} );
        },
        'check' => sub {
            my $args = shift;
            return 1 if Whostmgr::ACLS::hasroot();
            return   if !Whostmgr::ACLS::xml_checkacl('suspend-acct');
            return _owns_account( $args->{'user'} );
        },
        needs_role => undef,
    ],
    'listsuspended' => [
        'code' => sub {
            require Whostmgr::XMLUI::Accounts;
            Whostmgr::XMLUI::Accounts::listsuspended();
        },
        'check' => sub {
            return Whostmgr::ACLS::xml_checkacl('suspend-acct');
        },
        needs_role => undef,
    ],
    'addpkg' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::Packages;
            Whostmgr::XMLUI::Packages::addpkg(%$args);
        },
        'check' => sub {
            return Whostmgr::ACLS::xml_checkacl('add-pkg');
        },
        needs_role => undef,
    ],
    'killpkg' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::Packages;
            Whostmgr::XMLUI::Packages::killpkg(%$args);
        },
        'check' => sub {
            return Whostmgr::ACLS::xml_checkacl('add-pkg');
        },
        needs_role => undef,
    ],
    'editpkg' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::Packages;
            Whostmgr::XMLUI::Packages::editpkg(%$args);
        },
        'check' => sub {
            return Whostmgr::ACLS::xml_checkacl('edit-pkg');
        },
        needs_role => undef,
    ],

    'setacls' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::Resellers;
            Whostmgr::XMLUI::Resellers::setacls(%$args);
        },
        'check' => sub {
            return Whostmgr::ACLS::hasroot();
        },
        needs_role => undef,
    ],
    'terminatereseller' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::Resellers;
            Whostmgr::XMLUI::Resellers::terminate(%$args);
        },
        'check' => sub {
            return Whostmgr::ACLS::hasroot();
        },
        needs_role => undef,
    ],
    'resellerstats' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::Resellers;
            Whostmgr::XMLUI::Resellers::resellerstats(%$args);
        },
        'check' => sub {
            return Whostmgr::ACLS::hasroot();
        },
        needs_role => undef,
    ],
    'setupreseller' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::Resellers;
            Whostmgr::XMLUI::Resellers::setupreseller(
                'user'      => $args->{'user'},
                'makeowner' => $args->{'makeowner'}
            );
        },
        'check' => sub {
            return Whostmgr::ACLS::hasroot();
        },
        needs_role => undef,
    ],
    'setresellermainip' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::Resellers;
            Whostmgr::XMLUI::Resellers::setresellermainip(%$args);
        },
        'check' => sub {
            return Whostmgr::ACLS::hasroot();
        },
        needs_role => undef,
    ],
    'getresellerips' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::Resellers;
            Whostmgr::XMLUI::Resellers::getresellerips(%$args);
        },
        'check' => sub {
            my $args = shift;
            return 1 if Whostmgr::ACLS::hasroot();
            return 0 if !Whostmgr::ACLS::checkacl('ns-config');
            return _owns_account( $args->{'user'} );
        },
        needs_role => undef,
    ],
    'setresellerips' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::Resellers;
            Whostmgr::XMLUI::Resellers::setresellerips(%$args);
        },
        'check' => sub {
            return Whostmgr::ACLS::hasroot();
        },
        needs_role => undef,
    ],
    'setresellerlimits' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::Resellers;
            Whostmgr::XMLUI::Resellers::setresellerlimits(%$args);
        },
        'check' => sub {
            return Whostmgr::ACLS::hasroot();
        },
        needs_role => undef,
    ],
    'setresellerpackagelimit' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::Resellers;
            Whostmgr::XMLUI::Resellers::setresellerpackagelimit(%$args);
        },
        'check' => sub {
            return Whostmgr::ACLS::hasroot();
        },
        needs_role => undef,
    ],
    'setresellernameservers' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::Resellers;
            Whostmgr::XMLUI::Resellers::setresellernameservers(%$args);
        },
        'check' => sub {
            my $args = shift;
            return 1 if Whostmgr::ACLS::hasroot();
            return 0 if !Whostmgr::ACLS::checkacl('ns-config');
            return _owns_account( $args->{'user'} );
        },
        needs_role => undef,
    ],
    'suspendreseller' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::Resellers;
            Whostmgr::XMLUI::Resellers::suspendreseller(%$args);
        },
        'check' => sub {
            return Whostmgr::ACLS::hasroot();
        },
        needs_role => undef,
    ],
    'unsuspendreseller' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::Resellers;
            Whostmgr::XMLUI::Resellers::unsuspendreseller(%$args);
        },
        'check' => sub {
            return Whostmgr::ACLS::hasroot();
        },
        needs_role => undef,
    ],
    'lookupnsip' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::Nameserver;
            Whostmgr::XMLUI::Nameserver::lookupnsip( $args->{'nameserver'} );
        },
        'check' => sub {
            return Whostmgr::ACLS::checkacl('ns-config');
        },
        needs_role => undef,
    ],
    'lookupnsips' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::Nameserver;
            Whostmgr::XMLUI::Nameserver::lookupnsips( $args->{'nameserver'} );
        },
        'check' => sub {
            return Whostmgr::ACLS::checkacl('ns-config');
        },
        needs_role => undef,
    ],
    'listresellers' => [
        'code' => sub {
            require Whostmgr::XMLUI::Resellers;
            Whostmgr::XMLUI::Resellers::list();
        },
        'check' => sub {
            return Whostmgr::ACLS::hasroot();
        },
        needs_role => undef,
    ],
    'acctcounts' => [
        'code' => sub {
            my $args = shift;
            $args->{'user'} ||= $ENV{'REMOTE_USER'};
            require Whostmgr::XMLUI::Resellers;
            Whostmgr::XMLUI::Resellers::acctcounts(%$args);
        },
        'check' => sub {
            my $args = shift;
            return 1 if Whostmgr::ACLS::hasroot();
            return 0 if !Whostmgr::ACLS::checkacl('acct-summary');
            return _owns_account( $args->{'user'} );
        },
        needs_role => undef,
    ],
    'listacls' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::ACLS;
            Whostmgr::XMLUI::ACLS::listacls(%$args);
        },
        'check' => sub {
            return Whostmgr::ACLS::hasroot();
        },
        needs_role => undef,
    ],
    'saveacllist' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::ACLS;
            Whostmgr::XMLUI::ACLS::saveacllist(%$args);
        },
        'check' => sub {
            return Whostmgr::ACLS::hasroot();
        },
        needs_role => undef,
    ],
    'unsetupreseller' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::Resellers;
            Whostmgr::XMLUI::Resellers::unsetupreseller( 'user' => $args->{'user'} );
        },
        'check' => sub {
            return Whostmgr::ACLS::hasroot();
        },
        needs_role => undef,
    ],
    'gethostname' => [
        'code' => sub {
            require Whostmgr::XMLUI::Sys;
            Whostmgr::XMLUI::Sys::gethostname();
        },
        'check' => sub {
            return Whostmgr::ACLS::checkacl('basic-system-info') || Whostmgr::ACLS::checkacl('clustering');
        },
        needs_role => undef,
    ],
    'version' => [
        'code' => sub {
            require Whostmgr::XMLUI::Version;
            Whostmgr::XMLUI::Version::show();
        },
        'check' => sub {
            return Whostmgr::ACLS::checkacl('basic-system-info') || Whostmgr::ACLS::checkacl('clustering');
        },
        needs_role => undef,
    ],
    'generatessl' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::SSL;
            Whostmgr::XMLUI::SSL::generate(%$args);
        },
        'check' => sub {
            return Whostmgr::ACLS::xml_checkacl('ssl');
        },
        needs_role => undef,
    ],
    'fetchsslinfo' => [
        'code' => sub {
            my $args    = shift;
            my $domain  = $args->{'domain'};
            my $crtdata = $args->{'crtdata'};
            my %opts    = ( 'domain' => $domain, 'crtdata' => $crtdata, );
            require Whostmgr::XMLUI::SSL;
            Whostmgr::XMLUI::SSL::fetchinfo(%opts);
        },
        'check' => sub {
            return Whostmgr::ACLS::xml_checkacl('ssl');
        },
        needs_role => undef,
    ],
    'installssl' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::SSL;
            Whostmgr::XMLUI::SSL::installssl(%$args);
        },
        'check' => sub {
            return 1 if Whostmgr::ACLS::hasroot();
            return Whostmgr::ACLS::xml_checkacl('ssl') ? 1 : 0;
        },
        needs_role => undef,
    ],
    'listcrts' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::SSL;
            Whostmgr::XMLUI::SSL::listcrts(%$args);
        },
        'check' => sub {
            return Whostmgr::ACLS::checkacl('ssl-info');
        },
        needs_role => undef,
    ],
    'passwd' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::Passwd;
            Whostmgr::XMLUI::Passwd::passwd(%$args);
        },
        'check' => sub {
            return Whostmgr::ACLS::xml_checkacl('passwd');
        },
        needs_role => undef,
    ],
    'reboot' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::Sys;
            Whostmgr::XMLUI::Sys::reboot(%$args);
        },
        'check' => sub {
            return Whostmgr::ACLS::hasroot();
        },
        needs_role => undef,
    ],
    'accountsummary' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::Accounts;
            Whostmgr::XMLUI::Accounts::summary(%$args);
        },
        'check' => sub {
            return Whostmgr::ACLS::checkacl('acct-summary');
        },
        needs_role => undef,
    ],
    'editquota' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::Accounts;
            Whostmgr::XMLUI::Accounts::editquota(%$args);
        },
        'check' => sub {
            my $args = shift;
            return 1 if Whostmgr::ACLS::hasroot();
            return ( Whostmgr::ACLS::xml_checkacl('quota') && _owns_account( $args->{'user'} ) );
        },
        needs_role => undef,
    ],

    # The following two commands have similar implementations in cpsrvd
    'loadavg' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::Utils;
            Whostmgr::XMLUI::Utils::loadavg(%$args);
        },
        needs_role => undef,
    ],
    'cpanel' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::cPanel;
            Whostmgr::XMLUI::cPanel::cpanel_exec( \%$args );
        },
        'check' => sub {
            return Whostmgr::ACLS::checkacl('cpanel-api');
        },
        needs_role => undef,
    ],

    'servicestatus' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::Services;
            Whostmgr::XMLUI::Services::status(%$args);
        },
        'check' => sub {
            return 1 if Whostmgr::ACLS::hasroot();
            return Whostmgr::ACLS::xml_checkacl('status');
        },
        needs_role => undef,
    ],
    'configureservice' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::Services;
            Whostmgr::XMLUI::Services::configure(%$args);
        },
        'check' => sub {
            return Whostmgr::ACLS::hasroot();
        },
        needs_role => undef,
    ],
    'restartservice' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::Services;
            Whostmgr::XMLUI::Services::restart(%$args);
        },
        'check' => sub {
            return Whostmgr::ACLS::xml_checkacl('restart');
        },
        needs_role => undef,
    ],
    'set_tier' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::Version;
            return Whostmgr::XMLUI::Version::set_tier(%$args);
        },
        'check' => sub {
            return Whostmgr::ACLS::hasroot();
        },
        needs_role => undef,
    ],
    'set_cpanel_updates' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::Version;
            return Whostmgr::XMLUI::Version::set_cpanel_updates(%$args);
        },
        'check' => sub {
            return Whostmgr::ACLS::hasroot();
        },
        needs_role => undef,
    ],
    'get_available_tiers' => [
        'code' => sub {
            my $args = shift;
            require Whostmgr::XMLUI::Version;
            return Whostmgr::XMLUI::Version::get_available_tiers(%$args);
        },
        'check' => sub {
            return Whostmgr::ACLS::hasroot();
        },
        needs_role => undef,
    ],

    applist => [
        'code'  => \&_applist,
        'check' => sub {
            return Whostmgr::ACLS::checkacl('basic-whm-functions');
        },
        needs_role => undef,
    ],
);

sub find_api {
    my ( $app, $api ) = @_;

    Cpanel::Context::must_be_list();

    if ( !exists $_APPLIST{$app} ) {
        return 0, "Unknown app ($app) requested for this version (0) of the API.";
    }

    my $entry_hr = { @{ $_APPLIST{$app} } };

    if ( 'CODE' ne ref $entry_hr->{'code'} ) {
        die "“$app” has a hash entry but no code … this should never happen!";
    }

    if ( !exists $entry_hr->{'needs_role'} ) {
        die "“$app” has no “needs_role” entry!";
    }

    if ( my $role = $entry_hr->{'needs_role'} ) {
        Cpanel::LoadModule::load_perl_module("Cpanel::Server::Type::Role::$role")->verify_enabled();
    }

    %$api = (
        %$entry_hr,
        version => 0,
    );

    return 1, 'OK';
}

sub _owns_account {

    # Nobody owns an account that doesn't exist, not even root.
    require Cpanel::AcctUtils::Account;
    require Whostmgr::AcctInfo::Owner;
    return unless Cpanel::AcctUtils::Account::accountexists( $_[0] );
    return Whostmgr::AcctInfo::Owner::checkowner( $ENV{'REMOTE_USER'}, $_[0] );
}

sub _owns_account_with_domain {
    require Cpanel::AcctUtils::DomainOwner::Tiny;
    return _owns_account( Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner( $_[0] ) );
}

sub _owns_domain {
    require Cpanel::AcctUtils::DomainOwner::Tiny;
    return $ENV{'REMOTE_USER'} eq Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner( $_[0] );
}

sub _domain_or_zone_from_args {
    my $args   = shift;
    my $domain = $args->{'domain'};
    if ( !$domain && $args->{'zone'} ) {
        $domain = $args->{'zone'};
        $domain =~ s/\.db$//g;
    }
    return $domain;
}

#NOTE: Largely the same code as xml-api.pl::applist_v1()
sub _applist {
    my ( undef, $metadata ) = @_;

    require Whostmgr::XMLUI::Guts;

    my @apps;
    foreach my $app ( sort keys %_APPLIST ) {
        my %api;
        my ( $result, $reason ) = find_api( $app, \%api );
        if ( $result && ( !exists $api{'check'} || $api{'check'}->() ) ) {
            push @apps, $app;
        }
    }

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';

    return Whostmgr::XMLUI::Guts::applist( \@apps );
}

#For API shell
sub raw_applist {
    return keys %_APPLIST;
}

1;
