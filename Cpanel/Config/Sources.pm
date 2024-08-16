package Cpanel::Config::Sources;

# cpanel - Cpanel/Config/Sources.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::LoadConfig ();

use constant MY_IPV4_ENDPOINT => 'https://myip.cpanel.net/v1.0/';

# Needs to be changeable for testing.
our $cpsources_conf_file = '/etc/cpsources.conf';

=head1 METHODS

=over 4

=item B<loadcpsources>

Responsible for returning a hash of connect options, augmented by cpsources.conf

=cut

sub get_source {
    my ($want_key) = @_;

    return unless length $want_key;
    my $conf = loadcpsources();
    return $conf->{$want_key} // '';
}

my $load_cpsources_cache;

sub set_cache {
    return $load_cpsources_cache = shift;
}

sub loadcpsources {
    if ( !$load_cpsources_cache ) {

        if ( ${^GLOBAL_PHASE} && ${^GLOBAL_PHASE} eq 'START' && lc($0) ne '-e' ) {
            die q[FATAL: loadcpsources is called during compile time. You should postpone this call.];
        }

        my $update_default = 'httpupdate.cpanel.net';
        my %sources        = (
            'NEWS'               => 'web.cpanel.net',
            'RSYNC'              => 'rsync.cpanel.net',
            'HTTPUPDATE'         => $update_default,
            'MYIP'               => MY_IPV4_ENDPOINT,               # URL to determine a local IP's public IP (1to1 NAT)
            'STORE_SERVER_URL'   => 'https://store.cpanel.net',
            'TICKETS_SERVER_URL' => 'https://account.cpanel.net',
            'VERIFY_URL'         => 'https://verify.cpanel.net',
            'MANAGE2_URL'        => 'https://manage2.cpanel.net',
        );

        if ( -e $cpsources_conf_file ) {
            Cpanel::Config::LoadConfig::loadConfig( $cpsources_conf_file, \%sources );
        }

        # Strip white space off front and back of values
        foreach my $key ( keys %sources ) {
            next if ( !defined $sources{$key} );
            $sources{$key} =~ s/^\s+//;
            $sources{$key} =~ s/\s+$//;
        }

        $load_cpsources_cache = \%sources;
    }

    return wantarray ? %$load_cpsources_cache : $load_cpsources_cache;
}

=back

=cut

1;
