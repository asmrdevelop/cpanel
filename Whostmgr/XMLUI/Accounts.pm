package Whostmgr::XMLUI::Accounts;

# cpanel - Whostmgr/XMLUI/Accounts.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::AcctUtils::DomainOwner::Tiny ();
use Cpanel::Config::userdata::Load       ();
use Cpanel::PwCache::Helpers             ();
use Cpanel::PwDiskCache                  ();
use Whostmgr::XMLUI                      ();
use Whostmgr::Accounts::Create           ();
use Whostmgr::Accounts::List             ();
use Whostmgr::Accounts::Suspension       ();
use Whostmgr::Accounts::Upgrade          ();
use Whostmgr::Accounts::Modify           ();
use Whostmgr::ApiHandler                 ();
use Whostmgr::Quota                      ();
use Cpanel::NAT                          ();

sub modifyacct {
    my %OPTS = @_;
    my @RSD;

    delete $OPTS{'status_callback'};
    if ( exists $OPTS{'CPTHEME'} && !exists $OPTS{'RS'} ) { $OPTS{'RS'} = $OPTS{'CPTHEME'}; }

    my @MISSING;
    my @REQUIRED = ('user');

    # support legacy LANG key
    if ( !exists $OPTS{'LOCALE'} || !$OPTS{'LOCALE'} && exists $OPTS{'LANG'} ) {
        require Cpanel::Locale::Utils::Legacy;
        $OPTS{'LOCALE'} = Cpanel::Locale::Utils::Legacy::map_any_old_style_to_new_style( $OPTS{'LANG'} );
    }

    foreach my $req (@REQUIRED) {
        if ( !exists $OPTS{$req} ) {
            push @MISSING, $req;
        }
    }

    if (@MISSING) {
        push @RSD,
          {
            'status'        => 0,
            'statusmsg'     => 'Required fields missing',
            'missingfields' => \@MISSING,
          };
    }
    else {
        my @status = Whostmgr::Accounts::Modify::modify(%OPTS);
        push @RSD,
          {
            'status'    => $status[0],
            'statusmsg' => $status[1],
            'messages'  => $status[2],
            'warnings'  => $status[3],
            'newcfg'    => $status[4],
          };
    }

    Whostmgr::XMLUI::xmlencode( \@RSD );
    my %RS;
    $RS{'result'} = \@RSD;
    return Whostmgr::ApiHandler::out( \%RS, 'RootName' => 'modifyacct', 'NoAttr' => 1 );
}

sub unsuspendacct {
    my %OPTS = @_;

    my @RSD;
    my @status = Whostmgr::Accounts::Suspension::unsuspendacct( $OPTS{'user'} );
    push( @RSD, { 'status' => $status[0], 'statusmsg' => $status[1] } );

    Whostmgr::XMLUI::xmlencode( \@RSD );
    my %RS;
    $RS{'result'} = \@RSD;
    return Whostmgr::ApiHandler::out( \%RS, 'RootName' => 'unsuspendacct', 'NoAttr' => 1 );
}

sub suspendacct {
    my %OPTS = @_;

    my @RSD;
    my @status = Whostmgr::Accounts::Suspension::suspendacct( $OPTS{'user'}, $OPTS{'reason'}, $OPTS{'disallowun'} );
    push( @RSD, { 'status' => $status[0], 'statusmsg' => $status[1] } );

    Whostmgr::XMLUI::xmlencode( \@RSD );
    my %RS;
    $RS{'result'} = \@RSD;
    return Whostmgr::ApiHandler::out( \%RS, 'RootName' => 'suspendacct', 'NoAttr' => 1 );
}

sub _filter_account_info {
    my $filter_data      = shift;
    my $account_data_ref = shift;

    return if ( !defined $filter_data || !length $filter_data );
    my @filter_terms = split( /,/, $filter_data );

    foreach my $filter (@filter_terms) {
        if ( !length $filter ) {
            return 0;
        }
    }

    foreach my $account (@$account_data_ref) {
        my $temp_account = {
            'user'   => $account->{'user'},
            'domain' => $account->{'domain'},
        };

        foreach my $want (@filter_terms) {
            next if !exists $account->{$want};
            $temp_account->{$want} = $account->{$want};
        }

        $account = $temp_account;
    }

    return 1;
}

sub summary {
    my %OPTS = @_;

    my $cache_is_previous_tied = Cpanel::PwCache::Helpers::istied();
    Cpanel::PwDiskCache::enable() if !$cache_is_previous_tied;

    my ( $accounts_count, $accounts_ref );
    my $status;
    my $statusmsg;
    if ( $OPTS{'user'} || $OPTS{'domain'} ) {
        if ( $OPTS{'user'} ) {
            $OPTS{'searchtype'}   = 'user';
            $OPTS{'searchmethod'} = 'exact';
            $OPTS{'search'}       = $OPTS{'user'};
        }
        elsif ( $OPTS{'domain'} ) {
            $OPTS{'searchtype'}   = 'user';
            $OPTS{'searchmethod'} = 'exact';
            $OPTS{'search'}       = Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner( $OPTS{'domain'} );
        }
        ( $accounts_count, $accounts_ref ) = Whostmgr::Accounts::List::listaccts(%OPTS);

        if ( ref $accounts_ref eq 'ARRAY' ) {
            foreach my $acct (@$accounts_ref) {
                $acct->{'ip'} = Cpanel::NAT::get_public_ip( $acct->{'ip'} );
            }
        }

        _filter_account_info( $OPTS{'want'}, $accounts_ref );
        if ($accounts_count) {
            Whostmgr::XMLUI::xmlencode($accounts_ref);
            $status    = 1;
            $statusmsg = 'Ok';
        }
        else {
            $status    = 0;
            $statusmsg = 'Account does not exist';
        }
    }
    else {
        $status    = 0;
        $statusmsg = 'You must specify a user or domain to get a summary of';
    }

    Cpanel::PwDiskCache::disable() if !$cache_is_previous_tied;

    my %RS;
    $RS{'acct'}      = $accounts_ref;
    $RS{'status'}    = $status;
    $RS{'statusmsg'} = $statusmsg;

    return Whostmgr::ApiHandler::out( \%RS, 'RootName' => 'accountsummary', 'NoAttr' => 1 );
}

sub listsuspended {
    my %OPTS = @_;

    my $rsdref = Whostmgr::Accounts::List::listsuspended(%OPTS);

    Whostmgr::XMLUI::xmlencode($rsdref);

    my %RS;
    $RS{'status'}    = 1;
    $RS{'statusmsg'} = 'Ok';
    $RS{'accts'}     = $rsdref;
    return Whostmgr::ApiHandler::out( \%RS, 'RootName' => 'listsuspended', 'NoAttr' => 1 );
}

sub listaccts {
    my %OPTS = @_;

    my ( $accounts_count, $accounts_ref ) = Whostmgr::Accounts::List::listaccts(%OPTS);

    if ( ref $accounts_ref eq 'ARRAY' ) {
        foreach my $acct (@$accounts_ref) {
            $acct->{'ip'} = Cpanel::NAT::get_public_ip( $acct->{'ip'} );
        }
    }

    _filter_account_info( $OPTS{'want'}, $accounts_ref );
    Whostmgr::XMLUI::xmlencode($accounts_ref);

    my %RS;
    $RS{'status'}    = 1;
    $RS{'statusmsg'} = 'Ok';
    $RS{'acct'}      = $accounts_ref;
    return Whostmgr::ApiHandler::out( \%RS, 'RootName' => 'listaccts', 'NoAttr' => 1 );
}

sub changepackage {
    my %OPTS = @_;

    #user
    #pkg
    my ( $result, $reason, $rawout ) = Whostmgr::Accounts::Upgrade::upacct(%OPTS);

    my @RSD;
    push @RSD, { 'status' => $result, 'statusmsg' => $reason, 'rawout' => $rawout };

    my %RS;
    $RS{'result'} = \@RSD;
    return Whostmgr::ApiHandler::out( \%RS, 'RootName' => 'changepackage', 'NoAttr' => 1 );
}

sub createacct {
    my %OPTS = @_;

    $OPTS{'customip'} //= "";
    my $given_ip = $OPTS{'customip'};

    $OPTS{'customip'} = Cpanel::NAT::get_local_ip( $OPTS{'customip'} ) if $OPTS{'customip'};
    my ( $result, $reason, $output, $opref ) = Whostmgr::Accounts::Create::_createaccount(%OPTS);
    $output =~ s/$OPTS{'customip'}/$given_ip/g;
    $output ||= undef;

    $reason =~ s/$OPTS{'customip'}/$given_ip/g;
    $reason ||= undef;

    $opref->{'ip'} = Cpanel::NAT::get_public_ip( $opref->{'ip'} ) if $result;

    my @RSD;
    push @RSD, { 'status' => $result, 'statusmsg' => $reason, 'options' => $opref, 'rawout' => $output };

    my %RS;
    $RS{'result'} = \@RSD;
    return Whostmgr::ApiHandler::out( \%RS, 'RootName' => 'createacct', 'NoAttr' => 1 );
}

sub removeacct {
    my %OPTS = @_;

    require Whostmgr::Accounts::Remove;
    my $user    = $OPTS{'user'} || $OPTS{'username'};                           #compat with wwwacct/createacct
    my $keepdns = ( $OPTS{'keepdns'} && $OPTS{'keepdns'} =~ /[y1]/ ) ? 1 : 0;
    my ( $result, $reason, $output ) = Whostmgr::Accounts::Remove::_removeaccount(
        'user'    => $user,
        'keepdns' => $keepdns
    );

    my @RSD;
    push @RSD, { 'status' => $result, 'statusmsg' => $reason, 'rawout' => $output };

    my %RS;
    $RS{'result'} = \@RSD;
    return Whostmgr::ApiHandler::out( \%RS, 'RootName' => 'removeacct', 'NoAttr' => 1 );
}

sub domainuserdata {
    my %OPTS = @_;
    my $result;
    my $msg;

    my $domain = $OPTS{'domain'};
    my $user;
    my $userdata;

    if ( !$domain ) {
        $result = 0;
        $msg    = 'A domain is required.';
    }
    elsif ( !( $user = Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner( $domain, { 'default' => 0 } ) ) ) {
        $result = 0;
        $msg    = 'Unable to determine account owner for domain.';
    }
    else {
        my $domain_file = Cpanel::Config::userdata::Load::get_real_domain( $user, $domain );    #this is done to ensure that addon domains are properly checked
        $userdata = Cpanel::Config::userdata::Load::load_userdata( $user, $domain_file );
        $result   = 1;
        $msg      = 'Obtained userdata.';
    }

    my @RSD = ( { 'status' => $result, 'statusmsg' => $msg } );
    my %RS;
    if ( defined $userdata ) {
        $RS{'userdata'} = $userdata;
    }
    $RS{'result'} = \@RSD;
    return Whostmgr::ApiHandler::out( \%RS, 'RootName' => 'domainuserdata', 'NoAttr' => 1 );
}

sub editquota {
    my %OPTS = @_;
    my $result;
    my $msg;
    my $output;

    my $user  = $OPTS{'user'};
    my $quota = $OPTS{'quota'};

    if ( $quota !~ m/^(unlimited)|(\d+)$/ ) {
        $result = 0;
        $msg    = 'Invalid value for quota supplied.';
    }

    if ( !defined $result || $result ) {
        ( $result, $msg, $output ) = Whostmgr::Quota::setusersquota( $user, $quota );
    }

    my @RSD = ( { 'status' => $result, 'statusmsg' => $msg } );
    my %RS;
    $RS{'result'} = \@RSD;
    $RS{'output'} = $output;
    return Whostmgr::ApiHandler::out( \%RS, 'RootName' => 'editquota', 'NoAttr' => 1 );
}

sub setsiteip {
    my %OPTS   = @_;
    my $user   = $OPTS{'user'};
    my $ip     = Cpanel::NAT::get_local_ip( $OPTS{'ip'} );
    my $result = 1;
    my $msg    = "";

    if ( exists $OPTS{'domain'} ) {
        $user = Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner( $OPTS{'domain'} );

        if ( exists $OPTS{'user'} && $user ne $OPTS{'user'} ) {
            $result = 0;
            $msg    = 'User does not own the domain provided.';
        }
    }

    require Whostmgr::Accounts::SiteIP;
    if ($result) {
        ( $result, $msg ) = Whostmgr::Accounts::SiteIP::set( $user, undef, $ip, 1 );
    }

    my @RSD = ( { 'status' => $result, 'statusmsg' => $result ? 'OK' : $msg } );
    my %RS;
    $RS{'result'} = \@RSD;
    return Whostmgr::ApiHandler::out( \%RS, 'RootName' => 'setsiteip', 'NoAttr' => 1 );
}

1;
