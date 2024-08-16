package Cpanel::DnsUtils::Remove;

# cpanel - Cpanel/DnsUtils/Remove.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::CpUserGuard     ();
use Cpanel::Config::LoadUserDomains ();
use Cpanel::Debug                   ();
use Cpanel::DnsUtils::AskDnsAdmin   ();
use Cpanel::MailTools               ();
use Cpanel::Userdomains             ();
use Whostmgr::Accounts::DB::Remove  ();

sub removezone {
    my ( $domain, $noprint ) = @_;
    if ( !$domain ) {    # Domains called '' or 0 are silly and undef makes dnsutils go crazy
        print "Unable to remove zone <undef>\n" unless $noprint;
        return;
    }

    my $output = Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( "REMOVEZONE", 0, $domain );
    print $output unless $noprint;
    return;
}

################################################################
# dokilldns - Removes a dns entry by whatever method is configured
#  Params:
#     domains  -       A reference to an array of domains
sub dokilldns {
    my %OPTS = @_;

    return ( 0, 'No zones defined' ) unless defined $OPTS{'domains'};

    my $domains_ref = $OPTS{'domains'};
    my @DOMAINS     = ref $domains_ref eq 'ARRAY' ? @{$domains_ref} : [$domains_ref];
    my @OUTPUT;
    my %REMOVEZONES = map { $_ => 1 } @DOMAINS;
    if ( ( scalar keys %REMOVEZONES ) > 1 ) {
        push @OUTPUT, Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( "REMOVEZONES", 0, join( ',', keys %REMOVEZONES ) );
    }
    else {
        push @OUTPUT, Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( "REMOVEZONE", 0, $DOMAINS[0] );
    }

    my $needs_update_userdomains = 0;
    my $userdomains_ref          = Cpanel::Config::LoadUserDomains::loaduserdomains( undef, 1 );
    foreach my $domain (@DOMAINS) {
        my $user = $userdomains_ref->{$domain};
        unless ($user) {
            Cpanel::Debug::log_info("No owner found for domain '$domain'");
            next;
        }
        my $cpuser_guard = Cpanel::Config::CpUserGuard->new($user);
        if ($cpuser_guard) {
            @{ $cpuser_guard->{'data'}->{'DOMAINS'} } = grep { $_ ne $domain } @{ $cpuser_guard->{'data'}->{'DOMAINS'} };
            push @{ $cpuser_guard->{'data'}->{'DEADDOMAINS'} }, $domain;
            $cpuser_guard->save();
            $needs_update_userdomains = 1;
        }

        my $is_root = 0;

        # Only piggyback on an existing WHM ACLs initialization;
        # do not do an initialization here.
        if ( $user eq 'nobody' && $INC{'Whostmgr/ACLS.pm'} ) {
            $is_root = Whostmgr::ACLS::hasroot();
        }

        if ($is_root) {
            $cpuser_guard = Cpanel::Config::CpUserGuard->new('system');
            if ($cpuser_guard) {
                @{ $cpuser_guard->{'data'}->{'DOMAINS'} } = grep { $_ ne $domain } @{ $cpuser_guard->{'data'}->{'DOMAINS'} };
                push @{ $cpuser_guard->{'data'}->{'DEADDOMAINS'} }, $domain;
                $cpuser_guard->save();
                $needs_update_userdomains = 1;
            }
        }
    }
    Cpanel::MailTools::removedomain($_) for @DOMAINS;
    Whostmgr::Accounts::DB::Remove::remove_user_and_domains( undef, \@DOMAINS );
    if ($needs_update_userdomains) {
        Cpanel::Userdomains::updateuserdomains(1);
    }

    return ( 1, 'Zones Removed', join( "\n", @OUTPUT ) );
}
1;
