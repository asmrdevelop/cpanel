package Cpanel::Email::AutoConfig;

# cpanel - Cpanel/Email/AutoConfig.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Encoder::XML                ();
use Cpanel::Form::Timed                 ();
use Cpanel::Config::LoadCpConf          ();
use Cpanel::Config::LoadConfig          ();
use Cpanel::ConfigFiles                 ();
use Cpanel::Email::AutoConfig::Settings ();
use Try::Tiny;

my $FALLBACK_AUTODISCOVER_HOST = 'cpanelemaildiscovery.cpanel.net';
my $CRLF                       = "\x0d\x0a";

sub thunderbird {
    my $email = _get_thunderbird_email();

    my $ac_data = Cpanel::Email::AutoConfig::Settings::get_autoconfig_data($email);
    my $body    = _make_thunderbird_xml($ac_data);

    # Kmail chokes on utf8
    my $headers = qq{Status: 200$CRLF} . qq{Content-Length: } . length($body) . qq{$CRLF} . qq{Content-Type: application/xml$CRLF$CRLF};

    return ( 1, $headers, $body );
}

sub outlook {
    my ($fh_to_read) = @_;

    my $email = _get_outlook_email($fh_to_read);

    if ($email) {
        my $remotedomains_ref = Cpanel::Config::LoadConfig::loadConfig( $Cpanel::ConfigFiles::REMOTEDOMAINS_FILE, {}, '' );
        my ( $local_part, $domain ) = split( m{\@}, $email, 2 );
        if ( $remotedomains_ref->{$domain} ) {
            my $body = "$domain is a remote domain and cannot be configured with autodiscovery.";
            return (
                1, qq{Status: 400$CRLF} . qq{Content-Length: } . length($body) . qq{$CRLF} . qq{Content-Type: text/plain; charset="UTF-8"$CRLF$CRLF},
                $body
            );
        }

        my $ac_data = Cpanel::Email::AutoConfig::Settings::get_autoconfig_data($email);
        my $body    = _make_outlook_xml($ac_data);
        my $headers = qq{Status: 200$CRLF} . qq{Content-Length: } . length($body) . qq{$CRLF} . qq{Content-Type: application/xml; charset="UTF-8"$CRLF$CRLF};
        return ( 1, $headers, $body );
    }

    # Outlook will not provide us an email address over a plaintext channel so
    # we need to redirect them to a valid https URL to get the email address.

    #
    # TODO: backport skipping 127.0.0.1 to all supported versions
    #
    # Note: we should not enforce ssl requirements for loopback 127.0.0.1
    # because service (formerly proxy) subdomains connect to the non-secure ports
    #
    # This avoids the overhead added in FB-185581 the need to have
    #
    # (CLIENT) -> SSL(APACHE) -> SSL(APACHE)
    #
    # when the connection between APACHE and APACHE
    # is already secure because its 127.0.0.1
    #
    # (CPANEL) -> SSL(APACHE) -> (APACHE)
    #
    #
    elsif ( !_is_secure_connection() ) {
        my $body              = '';
        my $cpconf_ref        = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
        my $autodiscover_host = $cpconf_ref->{autodiscover_host};

        #If Apache serves up valid SSL for the original host, then
        #redirect Outlook to there rather than to the default autodiscover host.
        if ( !$autodiscover_host || $autodiscover_host eq $FALLBACK_AUTODISCOVER_HOST ) {
            my $original_host = _get_original_http_host();

            require Cpanel::SSL::CheckPeer;
            require Cpanel::SocketIP;
            require Cpanel::IP::LocalCheck;

            my $ip = Cpanel::SocketIP::_resolveIpAddress(
                $original_host,
                timeout => 5,
            );

            #Ensure that we only test a local IP address.
            if ( $ip && Cpanel::IP::LocalCheck::ip_is_on_local_server($ip) ) {

                #For now we don’t really care what the failure is.
                #In the future it might be nice to warn if the failure
                #is something like an expired certificate--i.e., something that
                #someone may not know and likely would want to remedy. That
                #would involve making CheckPeer throw more easily parsable
                #errors, though, which would be a significant undertaking.
                try {
                    Cpanel::SSL::CheckPeer::check(
                        $ip,
                        ( $cpconf_ref->{'apache_ssl_port'} =~ s<.*:><>r ),
                        $original_host,
                    );

                    $autodiscover_host = $original_host;
                };
            }
        }

        $autodiscover_host ||= $FALLBACK_AUTODISCOVER_HOST;

        # we have to redirect them instead since we are not over https
        my $headers = "Status: 302$CRLF" . "Location: https://$autodiscover_host/autodiscover/autodiscover.xml$CRLF" . "Content-Length: " . length($body) . "$CRLF" . "Content-Type: application/xml$CRLF$CRLF";
        return ( 1, $headers, $body );
    }

    # We didn't get a valid email address and we didn't redirect them because
    # we are already on https.  We need to present an error.
    my $body = "autodiscovery must be provided a valid email address";
    return (
        1, qq{Status: 400$CRLF} . qq{Content-Length: } . length($body) . qq{$CRLF} . qq{Content-Type: text/plain; charset="UTF-8"$CRLF$CRLF},
        $body
    );

}

sub _get_thunderbird_email {
    my $formref = shift || Cpanel::Form::Timed::timed_parseform(15);

    return $formref->{'emailaddress'};
}

sub _to_xml {
    my $opts = shift;
    $opts->{$_} = Cpanel::Encoder::XML::xmlencode( $opts->{$_} ) for keys %$opts;

    return $opts;
}

#cf. https://wiki.mozilla.org/Thunderbird:Autoconfiguration:ConfigFileFormat
sub _make_thunderbird_xml {
    my $opts = _to_xml(shift);

    # Kmail chokes on utf8
    my $xml = <<END;
<?xml version="1.0"?>
<clientConfig version="1.1">
    <emailProvider id="$opts->{'domain'}">
        <domain>$opts->{'domain'}</domain>
        <displayName>$opts->{'display'}</displayName>
        <displayShortName>$opts->{'display'}</displayShortName>
        <incomingServer type="$opts->{'inbox_service'}">
            <hostname>$opts->{'inbox_host'}</hostname>
            <port>$opts->{'inbox_port'}</port>
            <socketType>SSL</socketType>
            <authentication>password-cleartext</authentication>
            <username>$opts->{'inbox_username'}</username>
        </incomingServer>
        <outgoingServer type="smtp">
            <hostname>$opts->{'smtp_host'}</hostname>
            <port>$opts->{'smtp_port'}</port>
            <socketType>SSL</socketType>
            <authentication>password-cleartext</authentication>
            <username>$opts->{'smtp_username'}</username>
        </outgoingServer>
    </emailProvider>
</clientConfig>
END

    return $xml;
}

sub _get_outlook_email {
    my ($fh_to_read) = @_;

    if ( $ENV{'REQUEST_METHOD'} eq 'GET' ) {
        my $formref = Cpanel::Form::Timed::timed_parseform(15);    #this is not MS standard, however we have a GET back request in our email auto discovery service
        return lc( $formref->{'email'} ) if $formref && ref $formref && exists $formref->{'email'};
    }

    my $content_length = $ENV{'CONTENT_LENGTH'};

    return if !$content_length;

    die "The submitted content is too large.\n" if $content_length > 32768;

    my $bytes_to_read    = int $content_length;
    my $total_bytes_read = 0;

    my $formdata = q{};

    alarm(15);
    local $SIG{'ALRM'} = sub {
        die "Failed to read post data in allotted time";
    };

    $fh_to_read ||= \*STDIN;

    while ( $total_bytes_read < $bytes_to_read ) {
        my $bytes2 = read( $fh_to_read, $formdata, $bytes_to_read - $total_bytes_read, length $formdata );
        last if $bytes2 <= 0;
        $total_bytes_read += $bytes2;
    }
    alarm(0);

    my $email;

    if ( $formdata =~ m/<EMailAddress>([^<]+)<\/EMailAddress>/ ) {
        $email = lc $1;
    }

    return $email;
}

sub _make_outlook_xml {
    my $opts = shift;

    $opts->{'inbox_service'} =~ tr{a-z}{A-Z};

    _to_xml($opts);

    return <<END;
<Autodiscover xmlns="http://schemas.microsoft.com/exchange/autodiscover/responseschema/2006">
    <Response xmlns="http://schemas.microsoft.com/exchange/autodiscover/outlook/responseschema/2006a">
        <User>
            <DisplayName>$opts->{'display'}</DisplayName>
        </User>
        <Account>
            <AccountType>email</AccountType>
            <Action>settings</Action>
            <Protocol>
                <Type>$opts->{'inbox_service'}</Type>
                <Server>$opts->{'inbox_host'}</Server>
                <Port>$opts->{'inbox_port'}</Port>
                <DomainRequired>off</DomainRequired>
                <SPA>off</SPA>
                <SSL>on</SSL>
                <AuthRequired>on</AuthRequired>
                <LoginName>$opts->{'inbox_username'}</LoginName>
            </Protocol>
            <Protocol>
                <Type>SMTP</Type>
                <Server>$opts->{'smtp_host'}</Server>
                <Port>$opts->{'smtp_port'}</Port>
                <DomainRequired>off</DomainRequired>
                <SPA>off</SPA>
                <SSL>on</SSL>
                <AuthRequired>on</AuthRequired>
                <LoginName>$opts->{'smtp_username'}</LoginName>
            </Protocol>
        </Account>
    </Response>
</Autodiscover>
END

}

sub _is_secure_connection {
    return 1 if $ENV{'HTTPS'};                                                              # pre v64 EA4 templates
    return 1 if $ENV{'HTTP_X_HTTPS'};                                                       # v64 and later EA4 templates
    return 0 if $ENV{'HTTP_X_FORWARDED_HOST'} && $ENV{'SERVER_PORT'} == 80;
    return 1 if $ENV{'REMOTE_ADDR'} eq '127.0.0.1' || $ENV{'SERVER_ADDR'} eq '127.0.0.1';

    return 0;
}

sub _get_original_http_host {
    my $host;
    if ( $ENV{'REMOTE_ADDR'} eq '127.0.0.1' || $ENV{'SERVER_ADDR'} eq '127.0.0.1' ) {
        $host = $ENV{'HTTP_X_FORWARDED_HOST'};
    }

    return ( $host || $ENV{'HTTP_HOST'} );
}
1;
