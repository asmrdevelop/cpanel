package Whostmgr::XMLUI::SSL;

# cpanel - Whostmgr/XMLUI/SSL.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Whostmgr::XMLUI      ();
use Whostmgr::ACLS       ();
use Whostmgr::ApiHandler ();
use Cpanel::SSLInstall   ();
use Whostmgr::SSL        ();
use Cpanel::NAT          ();

my %generate_parameter_translation = qw(
  country countryName
  host    domains
  email   emailAddress
  city    localityName
  co      organizationName
  cod     organizationalUnitName
  state   stateOrProvinceName
);

sub generate {
    my %OPTS = @_;

    @OPTS{ values %generate_parameter_translation } = delete @OPTS{ keys %generate_parameter_translation };

    my $results = Whostmgr::SSL::generate(%OPTS);

    #A little rickety, but this should be fine.
    #Do this so that errors don't mention parameters that the caller didn't
    #actually pass in.
    while ( my ( $old, $new ) = each %generate_parameter_translation ) {
        $results->{'message'} =~ s{$new}{$old}g;
    }

    $results->{'statusmsg'} = $results->{'message'};

    my %RS;
    $RS{'results'} = $results;

    #FIXME: XMLUI::xmlencode should convert CODE elements to 'DUMMY' see case 10578
    foreach my $code_element (qw(fglob uniq wildcard_safe file_test locale MagicRevision)) {
        delete $RS{'results'}->{$code_element};
    }
    foreach my $element ( keys %{ $RS{'results'} } ) {
        delete $RS{'results'}->{$element} if ref $element eq 'CODE';
    }

    return Whostmgr::ApiHandler::out( \%RS, 'RootName' => 'generatessl', 'NoAttr' => 1 );
}

sub fetchinfo {
    my %OPTS    = @_;
    my $domain  = $OPTS{'domain'};
    my $crtdata = $OPTS{'crtdata'};
    my $sslinfo;

    if ( !length $crtdata && !length $domain ) {
        $sslinfo = { 'status' => 0, 'statusmsg' => 'No certificate data or domain supplied.' };
    }
    else {
        $sslinfo = Whostmgr::SSL::reseller_aware_fetch_sslinfo( $domain, $crtdata ) || { 'status' => 0, 'statusmsg' => 'Can not find the requested certificate or the certificate is invalid.' };
    }

    #Legacy compatibility
    if ( !$sslinfo->{'crt'} ) {
        $sslinfo->{'status'} = 0;
    }

    my @RSD = ($sslinfo);
    Whostmgr::XMLUI::xmlencode( \@RSD );

    my %RS;
    $RS{'sslinfo'} = \@RSD;

    return Whostmgr::ApiHandler::out( \%RS, 'RootName' => 'fetchsslinfo', 'NoAttr' => 1 );
}

sub listcrts {
    my %OPTS = @_;

    my ( $ok, $rsd_ar ) = Whostmgr::SSL::list_cert_domains_with_owners(
        user       => $ENV{'REMOTE_USER'},
        registered => $OPTS{'registered'},
    );

    return Whostmgr::ApiHandler::out(
        { 'crt' => ( $ok ? $rsd_ar : undef ) },
        'RootName' => 'listcrts',
        'NoAttr'   => 1,
    );
}

sub installssl {
    my %OPTS = @_;

    # assume same 'inputs' as :2087/scripts2/installssl
    # go=Submit, crt, domain, user, ip, key, cabundle
    # except cabundle is 'cab', see case 8874

    my $res_hr = {
        'status'    => 0,
        'statusmsg' => '',
        'rawout'    => '',
    };

    $OPTS{'ip'} = Cpanel::NAT::get_local_ip( $OPTS{'ip'} );
    my $installssl_hr = Cpanel::SSLInstall::install_or_do_non_sni_update(
        ( map { $_ => $OPTS{$_} } qw(domain ip key cab) ),
        crt                => $OPTS{'cert'},
        disclose_user_data => Whostmgr::ACLS::hasroot(),
    );

    $res_hr->{'rawout'}    = $installssl_hr->{'html'};
    $res_hr->{'status'}    = $installssl_hr->{'status'};
    $res_hr->{'statusmsg'} = $installssl_hr->{'message'};

    return Whostmgr::ApiHandler::out( $res_hr, 'RootName' => 'installssl', 'NoAttr' => 1 );
}

1;
