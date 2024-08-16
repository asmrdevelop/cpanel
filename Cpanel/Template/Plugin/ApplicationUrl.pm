
# cpanel - Cpanel/Template/Plugin/ApplicationUrl.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Template::Plugin::ApplicationUrl;

use strict;
use warnings;

use base 'Template::Plugin';

use Cpanel::Proxy::Tiny     ();
use Cpanel::Services::Ports ();

=head1 NAME

Cpanel::Template::Plugin::ApplicationUrl

=head1 DESCRIPTION

Helpers that build secure URLs to access a specific application.

=head1 SYNOPSIS

 USE ApplicationUrl;

 # Handling fqdns
 SET whostmgr_secure_url = ApplicationUrl.get_secure_url(host => 'abc.tld', port => 2086);
 SET cpanel_secure_url   = ApplicationUrl.get_secure_url(host => 'abc.tld', port => 2082);
 SET webmail_secure_url  = ApplicationUrl.get_secure_url(host => 'abc.tld', port => 2095);

 # Handling IP Addresses
 SET from_ipv4_secure_url  = ApplicationUrl.get_secure_url(host => '1.1.1.1', port => 2082);
 SET from_ipv6_secure_url  = ApplicationUrl.get_secure_url(host => 'beef::dead', port => 2082);

 # Handling standard service (formerly proxy) subdomains.
 SET cpanel_secure_url_with_proxy_considered = ApplicationUrl.get_secure_url(host => 'cpanel.abc.tld', port => 80, proxysubdomain => 1);

=head1 FUNCTIONS

=head2 get_secure_url(host => ..., app_name => ..., proxysubdomains => ...)

=head3 ARGUMENTS

=over

=item host - string

The server name from the request. Usually passed from SERVER_NAME or similar
environment variable.

=item port - number

Used to lookup the correct secure port for the application.

=item proxysubdomains - Boolean (Optional)

If provided will distinguish service (formerly proxy) subdomains from regular server names.
When service (formerly proxy) subdomains are identified, it will not append the port since
the proxy takes care of that. Defaults to 0.

=back

=head3 RETURNS

String - The secure version of the url.

=cut

=head1 INTERNAL FUNCTIONS

=head2 _is_subdomain_proxy(DOMAIN)

Check if the subdomain is one of the known service (formerly proxy) subdomains

=head3 PRIVATE

=cut

sub _is_subdomain_proxy {
    my $domain = shift;
    my @parts  = split( /\./, $domain );
    return 0 if @parts <= 2;

    my $subdomain = $parts[0];
    my $known     = Cpanel::Proxy::Tiny::get_known_proxy_subdomains();
    return defined $known->{$subdomain};
}

=head2 _is_subdomain_proxy(URL, PORT)

Append the app specific secure port to the url based on the current requests port.

=head3 PRIVATE

=cut

sub _with_port {
    my ( $url, $current_port ) = @_;

    # Find the app name from the current port
    my $app_name = $Cpanel::Services::Ports::PORTS{$current_port};

    # Since all apps in this list end with 's' for
    # securewe add 's' if it not the last character.
    $app_name .= 's' if substr( $app_name, -1 ) ne 's';

    # Lookup the secure port from the 'secure' version of the app_name
    my $secure_port = $Cpanel::Services::Ports::SERVICE{$app_name};
    return $url . ':' . $secure_port;
}

=head2 _get_secure_url(host => ..., app_name => ..., proxysubdomains => ...)

See documentation of behavior above in the public interface docs

=head3 PRIVATE

=cut

sub _get_secure_url {
    my ($opts) = @_;

    my $host            = $opts->{host} or die 'Must provide the host argument';
    my $current_port    = $opts->{port} or die 'Must provide the port argument';
    my $proxysubdomains = $opts->{proxysubdomains} || 0;

    my $url;
    if (   $host =~ m/^\d*\.\d*\.\d*\.\d*$/
        || $host =~ m/:/ ) {

        $host = '[' . $host . ']' if $host =~ m/:/ && $host !~ m/^\[[^\]]*\]/;    # Unescaped IPv6 address.

        $url = "https://$host";

        # its an ip address
        return _with_port( $url, $current_port );
    }

    $url = "https://$host";
    if ( !$proxysubdomains || !_is_subdomain_proxy($host) ) {
        return _with_port( $url, $current_port );
    }

    # its a service (formerly proxy) subdomain so just return the https version
    return $url;
}

=head2 new(CONTEXT)

Constructor for the plugin.

=cut

sub new {
    my ($class) = @_;
    my $plugin = { 'get_secure_url' => \&_get_secure_url };

    return bless $plugin, $class;
}

1;
