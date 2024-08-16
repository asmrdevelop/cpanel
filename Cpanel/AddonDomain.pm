package Cpanel::AddonDomain;

# cpanel - Cpanel/AddonDomain.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel                    ();
use Cpanel::AcctUtils::Domain ();
use Cpanel::DomainLookup      ();
use Cpanel::LoadModule        ();
use Cpanel::Locale            ();
use Cpanel::API::Ftp          ();

our %API = (
    'deladdondomain' => {},
    ## PASSWORD AUDIT (complete): cp's addon functionality
    ## pek ???: is this kosher?
    'addaddondomain' => {
        'modify'      => 'none',
        'xss_checked' => 1,
        needs_role    => 'WebServer',
    },
    'listaddondomains' => {}
);

*countftp = *Cpanel::API::Ftp::_countftp;

sub api2_addaddondomain {
    my %CFG = @_;
    Cpanel::LoadModule::loadmodule('Park');
    Cpanel::LoadModule::loadmodule('SubDomain');

    if ( $CFG{'subdomain'} =~ /\*/ ) {
        $Cpanel::CPERROR{'addondomain'} = "You cannot create a wildcard addon domain.";
        return;
    }

    my ( $result, $reason );
    my $already_has_subdomain = 0;
    my $domain                = Cpanel::AcctUtils::Domain::getdomain($Cpanel::user);

    if ( !defined $domain ) {
        $Cpanel::CPERROR{'addondomain'} = "Failed to find primary domain.";
        return;
    }

    # Don't allow the user to make the primary domain a subdomain of the addon domain.
    if ( $domain =~ /\.\Q$CFG{'newdomain'}\E$/ ) {
        $Cpanel::CPERROR{'addondomain'} = "Primary domain may not be subdomain of addon domain.";
        return;
    }

    if ( grep( /^\Q$CFG{'subdomain'}\E$/, @Cpanel::DOMAINS ) ) {
        $already_has_subdomain = 1;
    }

    $CFG{'newdomain'} =~ s/\.\Q$domain\E$//;
    $CFG{'subdomain'} =~ s/\.\Q$domain\E$//;

    my $locale = Cpanel::Locale->get_handle();
    my $maxaddon =
      !exists $Cpanel::CPDATA{'MAXADDON'} || $Cpanel::CPDATA{'MAXADDON'} eq '' || $Cpanel::CPDATA{'MAXADDON'} =~ m/unlimited/i
      ? 'unlimited'
      : int $Cpanel::CPDATA{'MAXADDON'};

    my @ADDONS                   = api2_listaddondomains();
    my $current_number_of_addons = $#ADDONS + 1;
    if ( $maxaddon ne 'unlimited' && $maxaddon <= $current_number_of_addons ) {
        $Cpanel::CPERROR{'addondomain'} = $locale->maketext( 'Your addon domain limit of [quant,_1,addon domain,addon domains] has been reached. The addon domain [_2] was not added.', $maxaddon, $CFG{'newdomain'} . "\n" );
        return { 'result' => 0, 'reason' => $Cpanel::CPERROR{'addondomain'} };
    }

    # Moved this out of the park admin bin since its more about business logic for a specific ui
    # and a hard requirement of adding a additional domain to an account.
    my $ftp_is_optional = defined $CFG{'ftp_is_optional'} && $CFG{'ftp_is_optional'};
    if ( !$ftp_is_optional ) {
        my $maxftp =
          !exists $Cpanel::CPDATA{'MAXFTP'} || $Cpanel::CPDATA{'MAXFTP'} eq '' || $Cpanel::CPDATA{'MAXFTP'} =~ m/unlimited/i
          ? 'unlimited'
          : int $Cpanel::CPDATA{'MAXFTP'};

        if ( $maxftp ne 'unlimited' && $maxftp <= countftp() ) {
            $Cpanel::CPERROR{'addondomain'} = $locale->maketext_plain_context('You have exceeded the maximum allowed [output,acronym,FTP,File Transfer Protocol] accounts.');
            return { 'result' => 0, 'reason' => $Cpanel::CPERROR{'addondomain'} };
        }
    }

    if ($already_has_subdomain) {
        $result = 1;
        $reason = 'Subdomain already exists';
    }
    else {
        ( $result, $reason ) = Cpanel::SubDomain::_addsubdomain( $CFG{'subdomain'}, $Cpanel::CPDATA{'DNS'}, 1, $CFG{'disallowdot'}, $CFG{'dir'}, $Cpanel::SubDomain::SKIP_SSL_SETUP, 1, 1 );
    }

    if ($result) {
        my $phpfpm_domain = $CFG{'subdomain'} . '.' . $Cpanel::CPDATA{'DNS'};
        $CFG{'do_ssl_setup'} = 1;
        ( $result, $reason ) = Cpanel::Park::_park( $CFG{'newdomain'}, $CFG{'subdomain'}, $CFG{'disallowdot'}, $CFG{'do_ssl_setup'}, $phpfpm_domain );

        if ( !$result ) {
            $Cpanel::CPERROR{'addondomain'} = $reason;
            if ( !$already_has_subdomain ) {
                my ( $result1, $reason1 ) = Cpanel::SubDomain::_delsubdomain( "$CFG{'subdomain'}_$Cpanel::CPDATA{'DNS'}", $CFG{'disallowdot'} );

                # Publish any delete errors into the current context.
                if ( !$result1 ) {
                    $Cpanel::CPERROR{'addondomain'} .= "\n$reason1";
                    $result = 0;
                }
            }
        }
    }
    else {
        $Cpanel::CPERROR{'addondomain'} = $reason;
    }

    # Force the context back into this methods context since _addsubdomain, _park and _delsubdomain could have changed it.
    $Cpanel::context = 'addondomain';
    return { 'result' => $result, 'reason' => $reason };
}

sub api2_listaddondomains {
    Cpanel::LoadModule::loadmodule('Park');
    goto &Cpanel::Park::api2_listaddondomains;
}

sub _flag_error {
    my ($reason) = @_;
    $Cpanel::CPERROR{'addondomain'} = $reason;
    return { 'result' => 0, 'reason' => $reason };
}

sub api2_deladdondomain {
    my %CFG = @_;
    Cpanel::LoadModule::loadmodule('Park');
    Cpanel::LoadModule::loadmodule('SubDomain');

    if ( !length $CFG{'subdomain'} || !length $CFG{'domain'} ) {
        return _flag_error("The subdomain and domain parameters must exist and be non-empty.");
    }

    my $fullsub = $CFG{'subdomain'} =~ s/_/./r;
    my %parked  = Cpanel::DomainLookup::getparked($fullsub);
    if ( !defined $parked{ $CFG{'domain'} } ) {
        return _flag_error("The subdomain $CFG{'subdomain'} does not correspond to $CFG{'domain'}.");
    }

    ## pek 10734: mod in SubDomain::_delsubdomain
    my ( $result, $reason ) = do {

        # _unpark() overwrites this value. We need that overwrite not to
        # apply globally because API2 needs “addondomain” to be the value
        # in order to report failures correctly.
        local $Cpanel::context;
        Cpanel::Park::_unpark( $CFG{'domain'}, $CFG{'subdomain'} );
    };

    # Avoid having a stale cache that produces errors.
    Cpanel::DomainLookup::flushmultiparked();

    ## case 42685: deladdondomain removes subdomain even if other domains are parked on top of it.
    my $has_parked     = 0;
    my %parked_domains = Cpanel::DomainLookup::getmultiparked();
    if ( ( exists $parked_domains{ $CFG{'subdomain'} } ) && keys %{ $parked_domains{ $CFG{'subdomain'} } } > 0 ) {
        $has_parked = 1;
        $reason .= "\nSubdomain $CFG{'subdomain'} was not removed because other domains are parked on top of it";
    }

    if ( $result && !$has_parked ) {
        ( $result, $reason ) = Cpanel::SubDomain::_delsubdomain( $CFG{'subdomain'}, $CFG{'disallowdot'} );
    }
    else {
        $Cpanel::CPERROR{'addondomain'} = $reason;
    }
    return { 'result' => $result, 'reason' => $reason };
}

sub api2 {
    my $func = shift;
    return $API{$func};
}

1;
