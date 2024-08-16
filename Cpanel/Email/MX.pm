package Cpanel::Email::MX;

# cpanel - Cpanel/Email/MX.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::AcctUtils::DomainOwner::Tiny ();
use Cpanel::Config::HasCpUserFile        ();
use Cpanel::Config::LoadCpUserFile       ();
use Whostmgr::DNS::MX                    ();

sub get_mxcheck_configuration {
    my ( $domain, $user, $cpuser_ref ) = @_;

    $user //= $Cpanel::user // Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner($domain);
    if ( scalar keys %Cpanel::CPDATA && exists $Cpanel::CPDATA{'DNS'} ) { $cpuser_ref = \%Cpanel::CPDATA }

    if ( my $mxcheck = Whostmgr::DNS::MX::_get_mx_type_from_node_linkage( $cpuser_ref, $domain ) ) {
        return $mxcheck;
    }

    # Not sure this key can exist without the file, except in our tests!
    if ( !Cpanel::Config::HasCpUserFile::has_cpuser_file($user) ) {
        return 'auto';
    }
    else {
        $cpuser_ref //= Cpanel::Config::LoadCpUserFile::loadcpuserfile($user);
        if ( !exists $cpuser_ref->{"MXCHECK-$domain"} ) {
            return 'auto';
        }
    }

    return cpuser_key_to_mx_compat( $cpuser_ref->{"MXCHECK-$domain"} );
}

sub cpuser_key_to_mx_compat {
    my $mxcheck = shift;
    if ( length $mxcheck && $mxcheck eq '0' ) { return 'local'; }
    return $mxcheck;
}

sub mx_compat {
    my $mxcheck = shift;
    if ( defined $mxcheck ) {
        if    ( $mxcheck eq '0' ) { return 'auto'; }
        elsif ( $mxcheck eq '1' ) { return 'local'; }
    }
    return $mxcheck;
}

sub does_alwaysaccept {
    my $setting = get_mxcheck_configuration(@_);
    return ( $setting eq 'local' ? 1 : 0 );
}

sub get_mxcheck_messages {
    my ( $domain, $checkmx ) = @_;

    my $mxstatus;
    if ( $checkmx->{'isprimary'} ) {
        $mxstatus = "LOCAL MAIL EXCHANGER: This server will serve as a primary mail exchanger for ${domain}'s mail.";
    }
    elsif ( $checkmx->{'issecondary'} ) {
        $mxstatus = "BACKUP MAIL EXCHANGER: This server will serve as a backup mail exchanger for ${domain}'s mail.";
    }
    else {
        $mxstatus = "REMOTE MAIL EXCHANGER: This server will NOT serve as a mail exchanger for ${domain}'s mail.";
    }

    my $mxcheck;
    if ( $checkmx->{'mxcheck'} eq 'local' ) {
        $mxcheck = 'This configuration has been manually selected.';
    }
    elsif ( $checkmx->{'mxcheck'} eq 'secondary' ) {
        $mxcheck = 'This configuration has been manually selected.';
    }
    elsif ( $checkmx->{'mxcheck'} eq 'remote' ) {
        $mxcheck = 'This configuration has been manually selected.';
    }
    else {
        $mxcheck = 'This configuration has been automatically detected based on your mx entries.';
    }

    my $warnings = $checkmx->{'warnings'};
    my $set      = $checkmx->{'changed'};

    $Cpanel::CPVAR{'mxstatus'} = $mxstatus;
    $Cpanel::CPVAR{'mxcheck'}  = $mxcheck;
    $Cpanel::CPVAR{'warnings'} = join( "\n", @$warnings );
    $Cpanel::CPVAR{'mxset'}    = $set;

    return ( $set, $mxstatus, $mxcheck, $warnings );
}

1;
