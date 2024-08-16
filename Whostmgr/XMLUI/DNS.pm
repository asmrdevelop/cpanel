package Whostmgr::XMLUI::DNS;

# cpanel - Whostmgr/XMLUI/DNS.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Try::Tiny;

use Cpanel::DnsUtils::Add                ();
use Cpanel::DnsUtils::Exists             ();
use Cpanel::DnsUtils::List               ();
use Whostmgr::ACLS                       ();
use Cpanel::AcctUtils::DomainOwner::Tiny ();
use Whostmgr::ApiHandler                 ();
use Whostmgr::DNS                        ();
use Whostmgr::XMLUI                      ();
use Whostmgr::AcctInfo::Owner            ();
use Whostmgr::DNS::Kill                  ();

sub dumpzone {
    my %OPTS = @_;

    my $domain = $OPTS{'domain'};
    if ( !$domain && $OPTS{'zone'} ) {
        $domain = $OPTS{'zone'};
        $domain =~ s/\.db$//g;
    }

    my @RSD;
    if ( !$domain ) {
        push @RSD, { 'status' => 0, 'statusmsg' => 'You must specify a domain to dump.' };
    }
    elsif ( !Cpanel::DnsUtils::Exists::domainexists($domain) ) {
        push @RSD, { 'status' => 0, 'statusmsg' => 'Zone does not exist.' };
    }
    elsif ( !Whostmgr::ACLS::hasroot() && !Whostmgr::AcctInfo::Owner::checkowner( $ENV{'REMOTE_USER'}, Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner($domain) ) ) {
        push @RSD, { 'status' => 0, 'statusmsg' => "Access Denied, you don't seem to own $domain" };
    }
    else {
        require Cpanel::Validate::Domain::Normalize;
        require Cpanel::QuickZoneFetch;
        my $normal_domain = Cpanel::Validate::Domain::Normalize::normalize($domain);
        my $zf            = Cpanel::QuickZoneFetch::fetch($normal_domain);
        if ( exists $zf->{'dnszone'} && ref $zf->{'dnszone'} ) {
            push @RSD, { 'status' => 1, 'statusmsg' => 'Zone Serialized', 'record' => $zf->{'dnszone'} };
        }
        else {
            push @RSD, { 'status' => 0, 'statusmsg' => 'Failed to retrieve zone: ' . $domain };
        }
    }

    Whostmgr::XMLUI::xmlencode( \@RSD );
    my %RS;
    $RS{'result'} = \@RSD;
    return Whostmgr::ApiHandler::out( \%RS, RootName => 'dumpzone', NoAttr => 1 );
}

sub getzonerecord {
    my %OPTS = @_;

    if ( !exists $OPTS{'Line'} && exists $OPTS{'line'} ) {
        $OPTS{'Line'} = $OPTS{'line'};
    }

    my $domain = $OPTS{'domain'};
    if ( !$domain && exists $OPTS{'zone'} ) {
        $domain = $OPTS{'zone'};
        $domain =~ s/\.db$//g;
        $OPTS{'domain'} = $domain;
    }

    my @RSD;
    if ( !Cpanel::DnsUtils::Exists::domainexists($domain) ) {
        push @RSD, { 'status' => 0, 'statusmsg' => 'Zone does not exist.' };
    }
    else {
        my $record;
        my ( $result, $msg ) = Whostmgr::DNS::get_zone_record( \$record, %OPTS );
        my $output_hash_ref = { 'status' => $result, 'statusmsg' => $msg };
        if ($result) {
            $output_hash_ref->{'record'} = $record;
        }
        push @RSD, $output_hash_ref;
    }

    Whostmgr::XMLUI::xmlencode( \@RSD );
    my %RS = ( 'result' => \@RSD );
    return Whostmgr::ApiHandler::out( \%RS, RootName => 'getzonerecord', NoAttr => 1 );
}

sub resetzone {
    my %OPTS = @_;

    my $domain = $OPTS{'domain'};
    if ( !$domain && exists $OPTS{'zone'} ) {
        $domain = $OPTS{'zone'};
        $domain =~ s/\.db$//g;
        $OPTS{'domain'} = $domain;
    }

    require Whostmgr::DNS::Rebuild;
    my ( $result, $msg ) = Whostmgr::DNS::Rebuild::restore_dns_zone_to_defaults(%OPTS);

    my @RSD;
    push @RSD, { status => $result, statusmsg => $msg };

    Whostmgr::XMLUI::xmlencode( \@RSD );
    my %RS;
    $RS{'result'} = \@RSD;
    return Whostmgr::ApiHandler::out( \%RS, RootName => 'resetzone', NoAttr => 1 );
}

sub addzonerecord {
    my %OPTS = @_;

    my $domain = $OPTS{'domain'};
    if ( !$domain && exists $OPTS{'zone'} ) {
        $domain = $OPTS{'zone'};
        $domain =~ s/\.db$//g;
        $OPTS{'domain'} = $domain;
    }

    my ( $result, $msg ) = Whostmgr::DNS::add_zone_record( \%OPTS );

    my @RSD;
    push @RSD, { status => $result, statusmsg => $msg };

    Whostmgr::XMLUI::xmlencode( \@RSD );
    my %RS;
    $RS{'result'} = \@RSD;
    return Whostmgr::ApiHandler::out( \%RS, RootName => 'addzonerecord', NoAttr => 1 );
}

sub editzonerecord {
    my %OPTS = @_;

    if ( !exists $OPTS{'Line'} && exists $OPTS{'line'} ) {
        $OPTS{'Line'} = $OPTS{'line'};
    }

    my $domain = $OPTS{'domain'};
    if ( !$domain && exists $OPTS{'zone'} ) {
        $domain = $OPTS{'zone'};
        $domain =~ s/\.db$//g;
        $OPTS{'domain'} = $domain;
    }

    my ( $result, $msg ) = Whostmgr::DNS::edit_zone_record( \%OPTS );

    my @RSD;
    push @RSD, { status => $result, statusmsg => $msg };

    Whostmgr::XMLUI::xmlencode( \@RSD );
    my %RS;
    $RS{'result'} = \@RSD;
    return Whostmgr::ApiHandler::out( \%RS, RootName => 'editzonerecord', NoAttr => 1 );
}

sub removezonerecord {
    my %OPTS = @_;

    if ( !exists $OPTS{'Line'} && exists $OPTS{'line'} ) {
        $OPTS{'Line'} = $OPTS{'line'};
    }

    my $domain = $OPTS{'domain'};
    if ( !$domain && exists $OPTS{'zone'} ) {
        $domain = $OPTS{'zone'};
        $domain =~ s/\.db$//g;
        $OPTS{'domain'} = $domain;
    }

    my ( $result, $msg ) = Whostmgr::DNS::remove_zone_record( \%OPTS );

    my @RSD;
    push @RSD, { status => $result, statusmsg => $msg };

    Whostmgr::XMLUI::xmlencode( \@RSD );
    my %RS;
    $RS{'result'} = \@RSD;
    return Whostmgr::ApiHandler::out( \%RS, RootName => 'removezonerecord', NoAttr => 1 );
}

sub adddns {
    my %OPTS = @_;

    my %RS;
    my $domain    = $OPTS{'domain'};
    my $trueowner = $OPTS{'trueowner'};
    my $ip        = $OPTS{'ip'};
    my $template  = $OPTS{'template'};

    my ( $status, $statusmsg ) = Cpanel::DnsUtils::Add::doadddns(
        'domain'         => $domain,
        'ip'             => $ip,
        'trueowner'      => $trueowner,
        'allowoverwrite' => Whostmgr::ACLS::hasroot(),
        'template'       => $template,
    );

    my @RSD;
    push @RSD, { 'status' => $status, 'statusmsg' => $statusmsg };
    Whostmgr::XMLUI::xmlencode( \@RSD );
    $RS{'result'} = \@RSD;
    return Whostmgr::ApiHandler::out( \%RS, RootName => 'adddns', NoAttr => 1 );
}

sub killdns {
    my %OPTS = @_;

    my @RSD;

    try {
        my $domain = $OPTS{'domain'} or die "A domain is required.\n";

        my $out = Whostmgr::DNS::Kill::kill_multiple($domain);
        push @RSD, { 'status' => 1, 'statusmsg' => 'OK', 'rawout' => $out };
    }
    catch {
        push @RSD, { 'status' => 0, 'statusmsg' => "$_" };
    };

    Whostmgr::XMLUI::xmlencode( \@RSD );

    my %RS = ( 'result' => \@RSD );
    return Whostmgr::ApiHandler::out( \%RS, RootName => 'killdns', NoAttr => 1 );
}

sub listzones {

    my @RSD;
    my $domain_ref = Cpanel::DnsUtils::List::listzones( 'hasroot' => Whostmgr::ACLS::hasroot() );
    foreach my $domain (@$domain_ref) {
        push @RSD, { 'domain' => $domain, 'zonefile' => $domain . '.db' };
    }

    Whostmgr::XMLUI::xmlencode( \@RSD );
    my %RS;
    $RS{'zone'} = \@RSD;
    return Whostmgr::ApiHandler::out( \%RS, 'RootName' => 'listzones', 'NoAttr' => 1 );
}

1;
