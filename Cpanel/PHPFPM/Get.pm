package Cpanel::PHPFPM::Get;

# cpanel - Cpanel/PHPFPM/Get.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::Httpd::EA4          ();
use Cpanel::Config::userdata::Constants ();
use Digest::SHA                         ();

sub get_php_fpm {
    my ( $user, $domain ) = @_;

    return 0 if !Cpanel::Config::Httpd::EA4::is_ea4() || !defined $user || !defined $domain;

    return -e "$Cpanel::Config::userdata::Constants::USERDATA_DIR/$user/$domain.php-fpm.yaml" ? 1 : 0;
}

sub get_proxy_from_php_config_for_domain {
    my ($php_config_for_domain) = @_;

    {
        # eval used instead of Try::Tiny since this is called in the vhost update tight loop
        local $@;
        if ( !eval { $php_config_for_domain->isa('Cpanel::PHP::Config::Domain') } ) {
            die 'get_proxy_from_php_config_for_domain requires a Cpanel::PHP::Config::Domain object';
        }
    }

    my $documentroot    = $php_config_for_domain->{'documentroot'};
    my $scrubbed_domain = $php_config_for_domain->{'scrubbed_domain'};
    my $domain          = $php_config_for_domain->{'domain'};
    my $phpversion      = $php_config_for_domain->{'phpversion'} or die "The system could not determine PHP version for the domain “$domain”";

    my $obscure_domain = Digest::SHA::sha1_hex($scrubbed_domain);
    my $socket_path    = "/opt/cpanel/$phpversion/root/usr/var/run/php-fpm/${obscure_domain}.sock";

    my $proxy = qq{unix:${socket_path}|fcgi://${domain}${documentroot}/};

    return ( $proxy, $socket_path );
}

1;
